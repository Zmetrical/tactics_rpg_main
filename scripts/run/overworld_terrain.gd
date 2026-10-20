extends RefCounted
## Diorama slab under the overworld: one block of land with a natural silhouette (see "Land mask" below), drawn from our own blocks
## (no GridMap, no TerrainTiles ids). Every cell has a height level (heights[]) and a colour (Style.top_color), and
## the two never read each other. Heights roll between level 1 and Style "roll_level_max" (noise seeded with
## seed ^ Style.NOISE_SALT) and blend to level 1 around every room and corridor cell. The four side walls
## show two bands: a grass lip, then soil; a step to a lower neighbour is one grass band. Light is baked into
## the vertex colours (top-left). No sea, no lakes (the river below is the one water), no collider. The slab is
## layout.bounds grown by slab_margin, and by slab_extra_east more on the boss side (step 19: the grid is grown to hold the
## land mask, see Style.COAST_*; the old rectangle is only used for the build log).
## River: one per slab, from the main range's foot to the slab edge (north or south). 1 cell wide at the source, 2 in the lower
## half, meandering about +-2 cells around a guide line and bending around every room (never within RIVER_ROOM_CLEAR
## cells of a footprint). Water cells sit 1 level below the lowest ground next to them, never rise downstream, and the
## banks step down to them. Ask the returned node: terrain.is_water(cell). Meta "bridge_cells" (Dictionary cell -> true)
## lists the corridor cells under water; OverworldDecor spans them with plank bridges at normal road height.
## Regions: the biomes on a 2x2 coarse grid, flood-filled (4-way, same biome); every connected area of at least
## REGION_MIN_CELLS cells gets one of the REGION_NAMES_* below, picked by a seeded rng (names repeat only when a biome
## has more areas than names). Ask the returned node: terrain.region_name_at(cell), "" outside a named area.
## Biomes (meadow / forest / rock) are a second per-cell array; they pick the ground colour and, for rock, add
## height: massifs, i.e. one main range, a band 8-12 cells deep along the boss (east) edge, and 2-3 smaller ones
## elsewhere (_raise_massifs). Each rises from level 2 at the foot to 5-6 at the core, about 1 level per 1.5-2 cells
## inward, with outline and summit from ridged noise; the whole footprint is rock, lighter on high cells. A massif never
## enters the blend zone around rooms and corridors, and its flanks may break the 1-level rule. No biome border runs
## straight for more than 8 cells. Forests are ground colour only. Ask the returned node: terrain.biome_at(cell).
## Land mask (step 19): land = distance d to the nearest room footprint or corridor cell < Style.COAST_R0 + n * Style.COAST_A
## (n = 2-octave noise, seed ^ NOISE_SALT, -1..1). Cells nearer than Style.COAST_FORCE_D are always land. Then: holes filled
## (non-land cells the sea cannot reach from the grid border become land), 1-cell-wide necks and spurs peeled off, and only the
## land piece holding the layout kept. Non-land cells get no block, height level -1 and biome Style.NONE, so the decor sampler
## skips them. The wall (grass lip, then soil) is drawn on every side that faces a non-land cell. Ask the returned node:
## terrain.is_land(cell); terrain.biome_at(cell) is "" outside the mask. Biomes, massifs, forests and the river use land only;
## the river ends on the shoreline cell nearest to its old mouth point. Meta "min" / "max" box the land, not the grid.
## Coordinates: layout x -> X, layout y -> Z, cell centres on whole numbers, height -> Y; identity transform.
## The returned node carries meta "levels" (PackedInt32Array, one per cell), "x0", "z0", "nx", "nz" for
## OverworldDecor.height_fn_from_terrain, and "min" / "max" (Vector3, the slab's outer box including the wall)
## for the camera framing. Same (layout, seed) gives the same slab.

const Layout = preload("res://scripts/run/overworld_layout.gd")
const Style = preload("res://data/run/overworld_style.gd")
const Stage3D = preload("res://scripts/battle/stage_3d.gd")

## The four sides of a cell as (dx, 0, dz).
const DIRS: Array[Vector3i] = [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]

## Region names (these belong in overworld_style.gd by the project rule; that file is not part of this step).
## Only these are ever shown: no name is generated.
const REGION_COARSE := 2
const REGION_MIN_CELLS := 40
const REGION_NAMES_MEADOW: Array[String] = ["THE FARMLANDS", "GREENMERE", "THE OPEN FIELDS"]
const REGION_NAMES_FOREST: Array[String] = ["THE DARK WOOD", "GLOOMWOOD"]
const REGION_NAMES_ROCK: Array[String] = ["THE HIGH PEAKS", "THE IRON SPINE"]
const REGION_SALT := 0x9E61

## River numbers (these belong in overworld_style.gd by the project rule; that file is not part of this step).
const RIVER_WIDTH_SOURCE := 1        # cells wide in the upper half
const RIVER_WIDTH_LOWER := 2         # cells wide in the lower half
const RIVER_MEANDER := 2.0           # +- cells the centre line wanders from the guide line (rooms may force more)
const RIVER_MEANDER_WEIGHT := 1.5    # path cost per cell of distance from the wandering line
const RIVER_ROOM_CLEAR := 2          # centre line stays more than this many cells (Chebyshev) from every footprint
const RIVER_CORRIDOR_COST := 5.0     # extra path cost on a corridor cell: the river crosses roads, it does not follow them
const RIVER_ROCK_COST := 6.0         # extra path cost on rock
const RIVER_REACH := 0.45            # the guide line runs this share of the slab width west of the source
const RIVER_NOISE_OFFSET := 1200.0   # noise sample offset for the meander
const RIVER_MOUTH_TRIES := 12        # shoreline cells tried, nearest to the old mouth point first, when a route is blocked
const SQRT2 := 1.4142
const LAND_MAX_ROUNDS := 8           # smoothing rounds (peel necks, keep the main piece, fill holes) before giving up

## The node build() returns: the slab plus the biome of every cell.
class Terrain extends Node3D:
	var biomes := PackedByteArray()
	var water := PackedByteArray()   # 1 = river cell, same layout as biomes
	var ridge := PackedByteArray()   # 1 = massif cell (any massif), same layout as biomes
	var land := PackedByteArray()    # 1 = land (has a block), same layout as biomes; 0 = plain background
	var levels := PackedInt32Array() # height level per cell, same layout as biomes (also in meta "levels")
	var region_ids := PackedInt32Array()   # per cell: index into region_names, -1 = no named region
	var region_names: Array[String] = []   # one entry per named region
	var x0 := 0
	var z0 := 0
	var nx := 1
	var nz := 1

	## true when the cell is land (has a block). Cells outside the grid are not land.
	func is_land(cell: Vector2i) -> bool:
		var ix := cell.x - x0
		var iz := cell.y - z0
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz or land.size() != nx * nz:
			return false
		return land[iz * nx + ix] == 1

	## Style.MEADOW, Style.FOREST or Style.ROCK (an int) for a land cell, "" (a String) outside the land mask.
	func biome_at(cell: Vector2i) -> Variant:
		if not is_land(cell):
			return ""
		var ix := clampi(cell.x - x0, 0, nx - 1)
		var iz := clampi(cell.y - z0, 0, nz - 1)
		return biomes[iz * nx + ix]

	## Name of the named region the cell lies in ("THE DARK WOOD"), or "" when its area is under REGION_MIN_CELLS
	## cells or the cell is outside the slab.
	func region_name_at(cell: Vector2i) -> String:
		var ix := cell.x - x0
		var iz := cell.y - z0
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz or region_ids.size() != nx * nz or land[iz * nx + ix] == 0:
			return ""
		var r := region_ids[iz * nx + ix]
		return "" if r < 0 else region_names[r]

	## Height level of the cell's block (cells outside the slab read as the nearest edge cell).
	func level_at(cell: Vector2i) -> int:
		var ix := clampi(cell.x - x0, 0, nx - 1)
		var iz := clampi(cell.y - z0, 0, nz - 1)
		return levels[iz * nx + ix]

	## true when the cell belongs to a massif (false outside the slab). The array is named "ridge" for the sampler.
	func is_ridge_at(cell: Vector2i) -> bool:
		var ix := cell.x - x0
		var iz := cell.y - z0
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
			return false
		return ridge[iz * nx + ix] == 1

	## true when the cell holds river water (cells outside the slab are not water).
	func is_water(cell: Vector2i) -> bool:
		var ix := cell.x - x0
		var iz := cell.y - z0
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
			return false
		return water[iz * nx + ix] == 1

## `style` defaults to Style.GRASSLAND. Returns a Node3D "OverworldTerrain" with the MeshInstance3D "Slab".
@warning_ignore("shadowed_global_identifier")
static func build(layout: Layout.OverworldLayout, seed: int, style: Dictionary = {}) -> Terrain:
	var s: Dictionary = style if not style.is_empty() else Style.GRASSLAND
	var step := Stage3D.STEP

	# Whole cells over bounds + margin. Cell (x, z) covers x +- 0.5, z +- 0.5.
	# The old rectangle (bounds + slab_margin + slab_extra_east), kept only to report the land as a share of it.
	var old_area := layout.bounds.grow(s["slab_margin"])
	old_area.size.x += float(s["slab_extra_east"])
	var old_cells := (int(ceilf(old_area.end.x)) - int(floorf(old_area.position.x)) + 1) * (int(ceilf(old_area.end.y)) - int(floorf(old_area.position.y)) + 1)
	# The grid must reach past the farthest possible coast, so the mask never meets the grid border.
	var area := layout.bounds.grow(maxf(float(s["slab_margin"]), Style.COAST_R0 + Style.COAST_A + Style.COAST_EAST_BONUS + 2.0))
	var x0 := int(floorf(area.position.x))
	var z0 := int(floorf(area.position.y))
	var nx := int(ceilf(area.end.x)) - x0 + 1
	var nz := int(ceilf(area.end.y)) - z0 + 1

	# Flat cells: every room footprint cell and every corridor cell. d_flat = distance to the nearest one.
	var blend: float = s["flat_blend"]
	var reach := ceili(blend)
	var d_flat := PackedFloat32Array()
	d_flat.resize(nx * nz)
	d_flat.fill(INF)
	var is_flat := PackedByteArray()
	is_flat.resize(nx * nz)
	for id in layout.rooms:
		var fp: Rect2i = layout.rooms[id]
		for x in range(fp.position.x, fp.end.x):
			for z in range(fp.position.y, fp.end.y):
				_mark_flat(is_flat, d_flat, nx, nz, x0, z0, Vector2i(x, z), reach)
	for road in layout.roads:
		for c: Vector2i in road["cells"]:
			_mark_flat(is_flat, d_flat, nx, nz, x0, z0, c, reach)

	# Land mask over the grid (silhouette). Everything below works on land cells only.
	var coast := _build_land(layout, nx, nz, x0, z0, is_flat, seed)
	var land: PackedByteArray = coast["land"]
	var land_count: int = coast["count"]
	var land_box: Rect2i = coast["box"]
	var land_idx := PackedInt32Array()
	for i in nx * nz:
		if land[i] == 1:
			land_idx.append(i)

	# Heights: level 1 .. roll_level_max from noise, blended down to level 1 towards flat cells. Colour is not read.
	var lv_min := int(s["slab_level"])
	var lv_max := int(s["roll_level_max"])
	var noise := _noise(seed ^ Style.NOISE_SALT, s["hill_freq"], s["hill_octaves"])
	var heights := PackedInt32Array()
	heights.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			if land[i] == 0:
				heights[i] = -1   # no block here
				continue
			var n := smoothstep(float(s["roll_from"]), float(s["roll_to"]), noise.get_noise_2d(x0 + ix, z0 + iz) * 0.5 + 0.5)
			var w := smoothstep(0.0, blend, minf(d_flat[i], blend))
			heights[i] = lv_min if is_flat[i] == 1 else roundi(lv_min + w * n * (lv_max - lv_min))
	# Biomes start as meadow. The massifs raise heights and make rock.
	var total := nx * nz
	var biomes := PackedByteArray()
	biomes.resize(total)
	biomes.fill(Style.MEADOW)
	for i in total:
		if land[i] == 0:
			biomes[i] = Style.NONE
	var is_ridge := PackedByteArray()   # 1 = massif cell (every massif; the name is kept for the sampler and the river)
	is_ridge.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ Style.NOISE_SALT
	var massif := _raise_massifs(s, nx, nz, x0, z0, d_flat, heights, biomes, is_ridge, rng, seed, land, coast)
	var rock_cells: int = massif["rock_cells"]

	# Neighbours (4-way) differ by at most 1 level: lower the higher cell. Flat cells are never raised; massif cells are
	# exempt (their flanks may break the 1-level rule).
	_relax(heights, is_ridge, land, nx, nz)

	# Forests: ground colour on meadow, grown from random centres to fill what the massifs leave of the
	# non-meadow share. Regions are connected and never within forest_clear of a room or corridor cell.
	var meadow_share := rng.randf_range(s["meadow_share_min"], s["meadow_share_max"])
	var forest_count := rng.randi_range(int(s["forest_count_min"]), int(s["forest_count_max"]))
	var min_cells := int(s["forest_min_cells"])
	var forest_total := maxi(int(round((1.0 - meadow_share) * land_count)) - rock_cells, min_cells * forest_count)
	var forest_sizes: Array[int] = []
	var centres: Array[Vector2] = []
	for k in forest_count:
		var target := maxi(min_cells, int(round(float(forest_total) / forest_count * rng.randf_range(0.8, 1.2))))
		for attempt in 6:
			var best := -1
			var best_d := -1.0
			for cand in 40:
				var i := land_idx[rng.randi_range(0, land_idx.size() - 1)]
				if biomes[i] != Style.MEADOW or d_flat[i] < float(s["forest_clear"]):
					continue
				var p := Vector2(x0 + i % nx, z0 + i / nx)
				var dmin := INF
				for q in centres:
					dmin = minf(dmin, p.distance_to(q))
				if dmin > best_d:
					best_d = dmin
					best = i
			if best < 0:
				continue
			var got := _grow_forest(biomes, d_flat, noise, nx, nz, x0, z0, best, target, s)
			if got.size() >= min_cells:
				forest_sizes.append(got.size())
				centres.append(Vector2(x0 + best % nx, z0 + best / nx))
				break
			for i in got:
				biomes[i] = Style.MEADOW

	# No forest border runs straight for more than border_max_run cells: bite notches into the long ones.
	var max_run := int(s["border_max_run"])
	_bite_straight(biomes, nx, nz, Style.FOREST, Style.MEADOW, max_run, land)

	# River: carved after the forests (it takes no forest cells and does not disturb their rng), then the banks are
	# lowered to it by the same 1-level rule.
	var water := PackedByteArray()
	water.resize(total)
	var river := _carve_river(layout, nx, nz, x0, z0, heights, biomes, is_ridge, water, noise, rng, land, coast)
	_relax(heights, is_ridge, land, nx, nz)
	_bite_straight(biomes, nx, nz, Style.FOREST, Style.MEADOW, max_run, land)   # the river cut new forest edges
	var bridge_cells := {}   # Vector2i -> true: corridor cells under water
	for road in layout.roads:
		for c: Vector2i in road["cells"]:
			var wx := c.x - x0
			var wz := c.y - z0
			if wx >= 0 and wz >= 0 and wx < nx and wz < nz and water[wz * nx + wx] == 1:
				bridge_cells[c] = true
	var crossings := count_groups(bridge_cells)
	var touches := false
	for cell: Vector2i in river["cells"]:
		for id in layout.rooms:
			var fp: Rect2i = layout.rooms[id]
			if fp.grow(1).has_point(cell):
				touches = true
	var max_delta := 0
	var max_flat := 0
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			if is_flat[i] == 1 and land[i] == 1:
				max_flat = maxi(max_flat, heights[i])
			if ix + 1 < nx and is_ridge[i] + is_ridge[i + 1] == 0 and land[i] + land[i + 1] == 2:
				max_delta = maxi(max_delta, absi(heights[i] - heights[i + 1]))
			if iz + 1 < nz and is_ridge[i] + is_ridge[i + nx] == 0 and land[i] + land[i + nx] == 2:
				max_delta = maxi(max_delta, absi(heights[i] - heights[i + nx]))

	var depth: float = s["slab_depth"]
	var lip: float = s["slab_lip"]
	var soil_col := Style.soil_color()
	var bottom := -depth
	# Screen-right of the map's first view: faces turned towards it get the dark (right) light.
	var yaw := deg_to_rad(Stage3D.CAM_START_YAW + Style.VIEW_YAW_OFFSET)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Water tops are their own surface with a flat unshaded material: no vertex light, no checker.
	var st_water := SurfaceTool.new()
	st_water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bank_col := Style.bank_lip_color()
	var lip_w: float = Style.BANK_LIP_WIDTH
	var lip_up: float = Style.BANK_LIP_LIFT
	for iz in nz:
		for ix in nx:
			if land[iz * nx + ix] == 0:
				continue   # outside the mask: no block, plain background
			var bi := biomes[iz * nx + ix]
			var wet := water[iz * nx + ix] == 1
			var face_c := Style.water_side_color() if wet else Style.face_color(bi)
			var y := heights[iz * nx + ix] * step
			var xa := float(x0 + ix) - 0.5
			var za := float(z0 + iz) - 0.5
			var xb := xa + 1.0
			var zb := za + 1.0
			if wet:
				_quad(st_water, Vector3(xa, y, za), Vector3(xb, y, za), Vector3(xa, y, zb), Vector3(xb, y, zb),
						Vector3.UP, Style.water_color())
			else:
				_quad(st, Vector3(xa, y, za), Vector3(xb, y, za), Vector3(xa, y, zb), Vector3(xb, y, zb),
						Vector3.UP, _lit(Style.top_color(bi, posmod(x0 + ix + z0 + iz, 2) == 1, heights[iz * nx + ix]), Style.LIGHT_TOP))
				# Bank: a light strip along each top edge that faces water, so the shoreline reads as an outline.
				var yl := y + lip_up
				var lip_lit := _lit(bank_col, Style.LIGHT_TOP)
				for d in DIRS:
					if not _wet_at(water, nx, nz, ix + d.x, iz + d.z):
						continue
					var sx0 := xa
					var sx1 := xb
					var sz0 := za
					var sz1 := zb
					if d.x < 0:
						sx1 = xa + lip_w
					elif d.x > 0:
						sx0 = xb - lip_w
					elif d.z < 0:
						sz1 = za + lip_w
					else:
						sz0 = zb - lip_w
					_quad(st, Vector3(sx0, yl, sz0), Vector3(sx1, yl, sz0), Vector3(sx0, yl, sz1), Vector3(sx1, yl, sz1),
							Vector3.UP, lip_lit)
			# Faces on the 4 sides: the slab's edge gets the two-band wall, a lower neighbour a one-band step.
			for dir in DIRS:
				var jx: int = ix + dir.x
				var jz: int = iz + dir.z
				var out := Vector3(dir.x, 0, dir.z)
				var f := Style.LIGHT_LEFT if out.dot(right) < 0.0 else Style.LIGHT_RIGHT
				var a: Vector3
				var b: Vector3
				if dir.z < 0:
					a = Vector3(xb, 0.0, za)
					b = Vector3(xa, 0.0, za)
				elif dir.z > 0:
					a = Vector3(xa, 0.0, zb)
					b = Vector3(xb, 0.0, zb)
				elif dir.x < 0:
					a = Vector3(xa, 0.0, za)
					b = Vector3(xa, 0.0, zb)
				else:
					a = Vector3(xb, 0.0, zb)
					b = Vector3(xb, 0.0, za)
				if jx < 0 or jz < 0 or jx >= nx or jz >= nz or land[jz * nx + jx] == 0:
					_wall(st, a, b, y, maxf(y - lip, bottom), bottom, out, _lit(face_c, f), _lit(soil_col, f))
				else:
					var ny := heights[jz * nx + jx] * step
					if ny < y:
						# A bank's face turned to the water takes the light shoreline colour.
						var shore := not wet and water[jz * nx + jx] == 1
						_quad(st, Vector3(a.x, y, a.z), Vector3(b.x, y, b.z), Vector3(a.x, ny, a.z), Vector3(b.x, ny, b.z),
								out, _lit(bank_col if shore else face_c, f))

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # the light is baked into the vertex colours
	st.set_material(mat)

	# Water: flat, unshaded, one colour. No vertex colours, so the baked light never touches it.
	var water_mat := StandardMaterial3D.new()
	water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_mat.albedo_color = Style.water_color()
	water_mat.vertex_color_use_as_albedo = false
	st_water.set_material(water_mat)

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Slab"
	var slab_mesh := st.commit()
	if water.has(1):
		st_water.commit(slab_mesh)   # appended as the last surface; skipped when the map has no river
	mesh_node.mesh = slab_mesh

	var heights_max := 0
	var n_meadow := 0
	var n_water := 0
	for i in total:
		n_water += water[i]
		heights_max = maxi(heights_max, heights[i])
		if biomes[i] == Style.MEADOW:
			n_meadow += 1

	var root := Terrain.new()
	root.name = "OverworldTerrain"
	root.biomes = biomes
	root.water = water
	root.ridge = is_ridge
	root.land = land
	root.levels = heights
	root.x0 = x0
	root.z0 = z0
	root.nx = nx
	root.nz = nz
	root.set_meta("levels", heights)
	root.set_meta("x0", x0)
	root.set_meta("z0", z0)
	root.set_meta("nx", nx)
	root.set_meta("nz", nz)
	root.set_meta("slab_level", lv_min)
	root.set_meta("bridge_cells", bridge_cells)
	root.set_meta("river_crossings", crossings)
	root.set_meta("land", land)
	# The outer box of the land (walls included), not of the grid: the camera framing and the mist read it.
	root.set_meta("min", Vector3(x0 + land_box.position.x - 0.5, bottom, z0 + land_box.position.y - 0.5))
	root.set_meta("max", Vector3(x0 + land_box.end.x - 0.5, float(heights_max) * step, z0 + land_box.end.y - 0.5))
	root.add_child(mesh_node)
	print("slab: %d x %d cells (grid)" % [nx, nz])
	print("land: %d cells, %.1f%% of the old rectangle (%d cells)" % [land_count, 100.0 * land_count / old_cells, old_cells])
	print("land components: %d (must be 1)" % coast["components"])
	print("min distance room/corridor cell to coast: %.2f cells (must be >= 3)" % coast["min_coast"])
	print("necks removed: %d (%d cells); specks removed: %d pieces (%d cells); holes filled: %d cells; land cells on the grid border: %d" % [
			coast["necks"], coast["neck_cells"], coast["specks"], coast["speck_cells"], coast["holes"], coast["border_land"]])
	print("height: max neighbour delta %d (ridge pairs excluded), max level on room/corridor cells %d" % [max_delta, max_flat])
	print("biomes: meadow %.1f%% of land, %d forests, sizes %s" % [100.0 * n_meadow / land_count, forest_sizes.size(), str(forest_sizes)])
	_print_massifs(massif, heights, nx, nz, x0, z0, land_count, biomes, land)
	_name_regions(root, seed ^ Style.NOISE_SALT ^ REGION_SALT)
	if river["cells"].is_empty():
		print("river: none (no route found)")
	else:
		print("river: %d cells, source level %d, mouth level %d, width %d -> %d, max offset from guide %.1f" % [
				river["cells"].size(), river["level_first"], river["level_last"], RIVER_WIDTH_SOURCE, RIVER_WIDTH_LOWER, river["max_dev"]])
	print("river crossings: %d" % crossings)
	var wc := Style.water_color()
	print("water: %d cells, top rgb (%d, %d, %d) = #%s" % [n_water, roundi(wc.r * 255.0), roundi(wc.g * 255.0), roundi(wc.b * 255.0), wc.to_html(false)])
	print("touches room: %s" % str(touches).to_lower())
	return root

## --- massifs ---------------------------------------------------------------------------------------

## Raises the massifs into `heights` / `biomes` / `is_ridge` and returns {rock_cells, comps (Array of PackedInt32Array
## cell indices, one per massif), peaks (Array[int]), main (index into comps), dmax, max_delta}.
## One main range: a band 8-12 cells deep along the boss (east) edge of the slab, tapering at both ends. Plus 2-3 smaller
## massifs elsewhere. The outline of each is wobbled by ridged noise (seed ^ NOISE_SALT), and no massif cell lies within
## massif_clear of a room or corridor cell (that distance is the blend zone, so rooms and corridors stay flat level 1).
## The footprint is fitted to a rock share of all cells, then a distance transform from the outline gives every cell its
## depth inside the massif; height = foot level + depth / step (1.5-2 cells per level, fitted so the deepest cell reaches
## the summit level), plus ridged noise, capped at 5-6. Every cell of a footprint is rock.
static func _raise_massifs(s: Dictionary, nx: int, nz: int, x0: int, z0: int, d_flat: PackedFloat32Array,
		heights: PackedInt32Array, biomes: PackedByteArray, is_ridge: PackedByteArray, rng: RandomNumberGenerator,
		seed: int, land: PackedByteArray, coast: Dictionary) -> Dictionary:
	var total := nx * nz
	# Land only: the main range runs along the east shoreline of each row, the rock share is a share of the land cells.
	var east_ix: PackedInt32Array = coast["east_ix"]
	var box: Rect2i = coast["box"]
	var land_count: int = coast["count"]
	var foot := int(s["massif_foot_level"])
	var ridged := FastNoiseLite.new()
	ridged.seed = seed ^ Style.NOISE_SALT
	ridged.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridged.fractal_octaves = int(s["massif_octaves"])
	ridged.frequency = float(s["massif_freq"])
	# Three independent samples of the ridged noise per cell, each in -1..1: outline, summit wobble, summit cap.
	var edge_n := PackedFloat32Array()
	var lvl_n := PackedFloat32Array()
	var cap_n := PackedFloat32Array()
	edge_n.resize(total)
	lvl_n.resize(total)
	cap_n.resize(total)
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			var px := float(x0 + ix)
			var pz := float(z0 + iz)
			edge_n[i] = (clampf(ridged.get_noise_2d(px, pz) * 0.5 + 0.5, 0.0, 1.0) - 0.5) * 2.0
			lvl_n[i] = (clampf(ridged.get_noise_2d(px + 400.0, pz) * 0.5 + 0.5, 0.0, 1.0) - 0.5) * 2.0
			cap_n[i] = (clampf(ridged.get_noise_2d(px, pz + 700.0) * 0.5 + 0.5, 0.0, 1.0) - 0.5) * 2.0

	var clear: float = s["massif_clear"]
	var amp: float = s["massif_edge_amp"]
	var depth := float(rng.randi_range(int(s["massif_depth_min"]), int(s["massif_depth_max"])))
	var zc := float(z0 + box.position.y) + float(box.size.y - 1) * 0.5 + rng.randf_range(-3.0, 3.0)

	# Smaller massifs: discs placed west of the main range, away from each other, mostly outside the blend zone.
	var want := rng.randi_range(int(s["massif_small_min"]), int(s["massif_small_max"]))
	var smalls: Array[Vector3] = []   # (x, z, r)
	var x_limit := float(x0 + box.end.x - 1) + 0.5 - depth - amp - 2.0
	var tries := 0
	while smalls.size() < want and tries < 800:
		tries += 1
		var r := rng.randf_range(s["massif_small_r_min"], s["massif_small_r_max"])
		var x_lo := float(x0 + box.position.x) + r * 0.5
		var z_lo := float(z0 + box.position.y) + r * 0.5
		var z_hi := float(z0 + box.end.y - 1) - r * 0.5
		var c := Vector2(rng.randf_range(x_lo, x_limit - r * 1.3), rng.randf_range(z_lo, z_hi))
		if c.x < x_lo or c.x > x_limit - r * 1.3 or c.y < z_lo or c.y > z_hi:
			continue
		var ok := true
		for o in smalls:
			if c.distance_to(Vector2(o.x, o.y)) < r + o.z + 4.0:
				ok = false
		if not ok:
			continue
		var inside := 0
		var free := 0
		for iz in range(maxi(0, floori(c.y - r) - z0), mini(nz - 1, ceili(c.y + r) - z0) + 1):
			for ix in range(maxi(0, floori(c.x - r) - x0), mini(nx - 1, ceili(c.x + r) - x0) + 1):
				if Vector2(x0 + ix, z0 + iz).distance_to(c) <= r:
					inside += 1
					if d_flat[iz * nx + ix] >= clear and land[iz * nx + ix] == 1:
						free += 1
		if inside == 0 or float(free) / inside < 0.6:
			continue
		smalls.append(Vector3(c.x, c.y, r))

	var mp := {"nx": nx, "nz": nz, "x0": x0, "z0": z0, "d_flat": d_flat, "edge_n": edge_n, "amp": amp, "clear": clear,
			"depth": depth, "zc": zc, "taper": float(s["massif_taper"]), "smalls": smalls, "max_run": int(s["border_max_run"]),
			"land": land, "east_ix": east_ix, "half_base": float(box.size.y - 1) * 0.5 - 1.0}

	# Fit the footprint to the rock share. The main range keeps at least massif_len_min of the edge: when that much plus
	# the small massifs is too much, the small ones give way first (the last one is dropped down to the minimum count,
	# then they shrink down to massif_small_scale_min). What is left over is bisected on the main range's length.
	var target := rng.randf_range(s["rock_share_min"], s["rock_share_max"])
	var len_min: float = s["massif_len_min"]
	var small_scale := 1.0
	while _mask_count(_massif_mask(mp, len_min, small_scale)) > target * land_count:
		if smalls.size() > int(s["massif_small_min"]):
			smalls.pop_back()
		elif small_scale > float(s["massif_small_scale_min"]):
			small_scale = maxf(float(s["massif_small_scale_min"]), small_scale * 0.9)
		else:
			break
	var len_scale := 1.0
	if _mask_count(_massif_mask(mp, 1.0, small_scale)) > target * land_count:
		var lo := len_min
		var hi := 1.0
		for it in 8:
			var mid := (lo + hi) * 0.5
			if _mask_count(_massif_mask(mp, mid, small_scale)) > target * land_count:
				hi = mid
			else:
				lo = mid
		len_scale = lo
	var mask := _massif_mask(mp, len_scale, small_scale)

	# Massifs = 4-way connected patches; patches under massif_min_cells are dropped.
	var comp := PackedInt32Array()
	comp.resize(total)
	comp.fill(-1)
	var comps: Array[PackedInt32Array] = []
	for start in total:
		if mask[start] == 0 or comp[start] != -1:
			continue
		var cells := PackedInt32Array([start])
		comp[start] = -2
		var head := 0
		while head < cells.size():
			var cur := cells[head]
			head += 1
			var cx := cur % nx
			var cz := cur / nx
			for dir in DIRS:
				var jx: int = cx + dir.x
				var jz: int = cz + dir.z
				if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
					continue
				var j := jz * nx + jx
				if mask[j] == 1 and comp[j] == -1:
					comp[j] = -2
					cells.append(j)
		if cells.size() < int(s["massif_min_cells"]):
			for i in cells:
				mask[i] = 0
			continue
		for i in cells:
			comp[i] = comps.size()
		comps.append(cells)

	# Depth inside the footprint (cells to the nearest non-massif cell; the slab edge counts as inside): chamfer pass.
	var dist := PackedFloat32Array()
	dist.resize(total)
	for i in total:
		dist[i] = INF if mask[i] == 1 or land[i] == 0 else 0.0   # the coast counts as inside, like the old slab edge
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			if mask[i] == 0:
				continue
			var best := dist[i]
			if ix > 0:
				best = minf(best, dist[i - 1] + 1.0)
			if iz > 0:
				best = minf(best, dist[i - nx] + 1.0)
				if ix > 0:
					best = minf(best, dist[i - nx - 1] + 1.4142)
				if ix < nx - 1:
					best = minf(best, dist[i - nx + 1] + 1.4142)
			dist[i] = best
	for iz in range(nz - 1, -1, -1):
		for ix in range(nx - 1, -1, -1):
			var i := iz * nx + ix
			if mask[i] == 0:
				continue
			var best := dist[i]
			if ix < nx - 1:
				best = minf(best, dist[i + 1] + 1.0)
			if iz < nz - 1:
				best = minf(best, dist[i + nx] + 1.0)
				if ix < nx - 1:
					best = minf(best, dist[i + nx + 1] + 1.4142)
				if ix > 0:
					best = minf(best, dist[i + nx - 1] + 1.4142)
			dist[i] = best

	var peak_lo := int(s["massif_peak_min"])
	var peak_hi := int(s["massif_peak_max"])
	var lvl_amp: float = s["massif_level_noise"]
	var peaks: Array[int] = []
	var kept: Array[PackedInt32Array] = []
	var rock_cells := 0
	var dropped := 0
	var main := -1
	for k in comps.size():
		var dmax := 0.0
		var touches_east := false
		for i in comps[k]:
			if dist[i] != INF:
				dmax = maxf(dmax, dist[i])
			if east_ix[i / nx] >= 0 and i % nx >= east_ix[i / nx] - 1:
				touches_east = true
		# Cells per level, fitted so the deepest cell lands half way between peak_lo and peak_lo + 1 above the foot.
		var step := clampf((dmax - 1.0) / (float(peak_lo - foot) + 0.5), float(s["massif_step_min"]), float(s["massif_step_max"]))
		var lvs := PackedInt32Array()
		var peak := 0
		for i in comps[k]:
			var d := minf(dist[i], 99.0)
			var h_f := (d - 1.0) / step + lvl_n[i] * lvl_amp
			var cap := peak_lo + (1 if cap_n[i] > 0.1 and peak_hi > peak_lo else 0)
			var lv := clampi(foot + floori(h_f + 0.5), foot, cap)
			lvs.append(lv)
			peak = maxi(peak, lv)
		# A fragment the blend zone cut too thin to reach the summit levels is not a massif: dropped.
		if peak < peak_lo:
			for i in comps[k]:
				mask[i] = 0
			dropped += 1
			continue
		for n in comps[k].size():
			var i := comps[k][n]
			heights[i] = lvs[n]
			biomes[i] = Style.ROCK
			is_ridge[i] = 1
		peaks.append(peak)
		kept.append(comps[k])
		rock_cells += comps[k].size()
		if touches_east and (main < 0 or comps[k].size() > kept[main].size()):
			main = kept.size() - 1
	comps = kept
	if main < 0 and not comps.is_empty():
		main = 0
		for k in comps.size():
			if comps[k].size() > comps[main].size():
				main = k

	# Largest height step between 4-way neighbours that are both massif cells.
	var max_delta := 0
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			if mask[i] == 0:
				continue
			if ix + 1 < nx and mask[i + 1] == 1:
				max_delta = maxi(max_delta, absi(heights[i] - heights[i + 1]))
			if iz + 1 < nz and mask[i + nx] == 1:
				max_delta = maxi(max_delta, absi(heights[i] - heights[i + nx]))
	return {"rock_cells": rock_cells, "comps": comps, "peaks": peaks, "main": main, "max_delta": max_delta,
			"len_scale": len_scale, "small_scale": small_scale, "depth": depth, "dropped": dropped}

static func _mask_count(mask: PackedByteArray) -> int:
	var n := 0
	for v in mask:
		n += v
	return n

## Footprint of the main range (length scaled by `len_scale`) and the small massifs (radius scaled by `small_scale`),
## minus the blend zone, with the long straight outline stretches bitten out.
static func _massif_mask(mp: Dictionary, len_scale: float, small_scale: float) -> PackedByteArray:
	var nx: int = mp["nx"]
	var nz: int = mp["nz"]
	var x0: int = mp["x0"]
	var z0: int = mp["z0"]
	var d_flat: PackedFloat32Array = mp["d_flat"]
	var edge_n: PackedFloat32Array = mp["edge_n"]
	var amp: float = mp["amp"]
	var clear: float = mp["clear"]
	var depth: float = mp["depth"]
	var taper: float = mp["taper"]
	var smalls: Array = mp["smalls"]
	var land: PackedByteArray = mp["land"]
	var east_ix: PackedInt32Array = mp["east_ix"]
	var half: float = float(mp["half_base"]) * len_scale
	var zs: float = float(mp["zc"]) - half
	var ze: float = float(mp["zc"]) + half
	var mask := PackedByteArray()
	mask.resize(nx * nz)
	for iz in nz:
		var z := float(z0 + iz)
		var tp := smoothstep(0.0, taper, minf(z - zs, ze - z))
		if east_ix[iz] < 0:
			continue   # no land in this row
		var x_edge := float(x0 + east_ix[iz]) + 0.5   # the east shoreline of this row
		for ix in nx:
			var i := iz * nx + ix
			if land[i] == 0 or d_flat[i] < clear:
				continue
			var x := float(x0 + ix)
			var inside := tp > 0.0 and (x_edge - x) < depth * tp + edge_n[i] * amp
			if not inside:
				for o: Vector3 in smalls:
					var r := o.z * small_scale
					if Vector2(x, z).distance_to(Vector2(o.x, o.y)) < r + edge_n[i] * r * 0.3:
						inside = true
						break
			if inside:
				mask[i] = 1
	_bite_straight(mask, nx, nz, 1, 0, int(mp["max_run"]), land)
	return mask

## Straight stretches of a border between two different values of `cls`, as dictionaries {horiz, line, start, len,
## first_is_target}: a stretch is a run of 4-way neighbour pairs along one row (horiz) or column that are all the same
## pair of values, `len` pairs long, `first` being the lower-index cell of each pair. With target >= 0 only pairs that
## hold that value, with min_len 0 every pair counts; only runs longer than min_len are returned.
static func _border_runs(cls: PackedByteArray, nx: int, nz: int, target: int, min_len: int, land := PackedByteArray()) -> Array:
	var out: Array = []
	for horiz in [true, false]:
		var lines := nz - 1 if horiz else nx - 1
		var span := nx if horiz else nz
		for line in lines:
			var run := 0
			var pa := -1
			var pb := -1
			for k in span:
				var ia := line * nx + k if horiz else k * nx + line
				var ib := ia + nx if horiz else ia + 1
				var a := cls[ia]
				var b := cls[ib]
				var hit := a != b and (target < 0 or a == target or b == target)
				if hit and not land.is_empty() and (land[ia] == 0 or land[ib] == 0):
					hit = false   # the coast is not a biome border
				if hit and run > 0 and a == pa and b == pb:
					run += 1
				else:
					if run > min_len:
						out.append({"horiz": horiz, "line": line, "start": k - run, "len": run, "first_is_target": pa == target})
					run = 1 if hit else 0
					pa = a
					pb = b
			if run > min_len:
				out.append({"horiz": horiz, "line": line, "start": span - run, "len": run, "first_is_target": pa == target})
	return out

## Longest straight border between any two values of `cls` (the slab edge is not a border).
static func longest_border(cls: PackedByteArray, nx: int, nz: int, land := PackedByteArray()) -> int:
	var best := 0
	for r: Dictionary in _border_runs(cls, nx, nz, -1, 0, land):
		best = maxi(best, r["len"])
	return best

## Bites notches out of every border stretch of the `target` value longer than `max_run`: at the middle of the stretch the
## 3 border cells and the one behind the centre one change to `fallback`. Repeats until no stretch is too long.
static func _bite_straight(cls: PackedByteArray, nx: int, nz: int, target: int, fallback: int, max_run: int, land := PackedByteArray()) -> void:
	for round_i in 24:
		var runs := _border_runs(cls, nx, nz, target, max_run, land)
		if runs.is_empty():
			return
		for r: Dictionary in runs:
			var line: int = r["line"]
			var m: int = r["start"] + int(r["len"]) / 2
			var first: bool = r["first_is_target"]
			var back := -1 if first else 1   # towards the inside of the target side
			var row := line if first else line + 1
			for k in range(m - 1, m + 2):
				var ci := row * nx + k if r["horiz"] else k * nx + row
				if cls[ci] == target:
					cls[ci] = fallback
			var inner := row + back
			if inner >= 0 and inner < (nz if r["horiz"] else nx):
				var cj := inner * nx + m if r["horiz"] else m * nx + inner
				if cls[cj] == target:
					cls[cj] = fallback

## Prints the massif report: count, cells and peak of each, rock share, the longest straight border, and one row of
## heights through the main range, cell by cell.
static func _print_massifs(info: Dictionary, heights: PackedInt32Array, nx: int, nz: int, x0: int, z0: int, total: int,
		biomes: PackedByteArray, land: PackedByteArray) -> void:
	var comps: Array = info["comps"]
	var peaks: Array = info["peaks"]
	print("massifs: %d (main range = #%d), rock share %.1f%% of land (%d of %d cells)" % [comps.size(), int(info["main"]) + 1,
			100.0 * float(info["rock_cells"]) / total, info["rock_cells"], total])
	for k in comps.size():
		print("  massif %d%s: %d cells, peak level %d" % [k + 1, " (main)" if k == int(info["main"]) else "", comps[k].size(), peaks[k]])
	print("massif neighbour height step inside a massif: max %d levels; fit: main length x%.2f, small x%.2f, depth %d, %d thin fragments dropped" % [
			info["max_delta"], info["len_scale"], info["small_scale"], int(info["depth"]), info["dropped"]])
	print("longest straight biome border: %d cells (limit %d)" % [longest_border(biomes, nx, nz, land), Style.GRASSLAND["border_max_run"]])
	if int(info["main"]) >= 0:
		var cells: PackedInt32Array = comps[int(info["main"])]
		var sum_z := 0
		for i in cells:
			sum_z += i / nx
		var row := int(round(float(sum_z) / cells.size()))
		var parts := PackedStringArray()
		for ix in nx:
			parts.append(str(heights[row * nx + ix]))
		print("main range row z=%d, heights cell by cell from x=%d to x=%d: %s" % [z0 + row, x0, x0 + nx - 1, " ".join(parts)])

static func _noise(noise_seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n

## Marks cell `c` flat and lowers d_flat to the distance to it for every cell within `reach`.
static func _mark_flat(is_flat: PackedByteArray, d_flat: PackedFloat32Array, nx: int, nz: int, x0: int, z0: int,
		c: Vector2i, reach: int) -> void:
	var cx := c.x - x0
	var cz := c.y - z0
	if cx < 0 or cz < 0 or cx >= nx or cz >= nz:
		return
	is_flat[cz * nx + cx] = 1
	for iz in range(maxi(0, cz - reach), mini(nz - 1, cz + reach) + 1):
		for ix in range(maxi(0, cx - reach), mini(nx - 1, cx + reach) + 1):
			var d := Vector2(ix - cx, iz - cz).length()
			var i := iz * nx + ix
			if d < d_flat[i]:
				d_flat[i] = d

## Lowers the higher of two neighbouring cells until every 4-way pair differs by at most 1 level (ridge cells are
## never lowered; flat cells sit at level 1 already and are only ever lowered by the river). Non-land cells are ignored.
static func _relax(heights: PackedInt32Array, is_ridge: PackedByteArray, land: PackedByteArray, nx: int, nz: int) -> void:
	var changed := true
	while changed:
		changed = false
		for iz in nz:
			for ix in nx:
				var i := iz * nx + ix
				if is_ridge[i] == 1 or land[i] == 0:
					continue
				for dir in DIRS:
					var jx: int = ix + dir.x
					var jz: int = iz + dir.z
					if jx < 0 or jz < 0 or jx >= nx or jz >= nz or land[jz * nx + jx] == 0:
						continue
					var nb := heights[jz * nx + jx]
					if heights[i] > nb + 1:
						heights[i] = nb + 1
						changed = true

## Number of 4-way connected groups among the cells (Vector2i keys) of `cells`.
static func count_groups(cells: Dictionary) -> int:
	var seen := {}
	var groups := 0
	for c: Vector2i in cells:
		if seen.has(c):
			continue
		groups += 1
		var stack: Array[Vector2i] = [c]
		seen[c] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			for dir in DIRS:
				var nb := Vector2i(cur.x + dir.x, cur.y + dir.z)
				if cells.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
	return groups

## true when (ix, iz) is inside the slab and holds river water.
static func _wet_at(water: PackedByteArray, nx: int, nz: int, ix: int, iz: int) -> bool:
	return ix >= 0 and iz >= 0 and ix < nx and iz < nz and water[iz * nx + ix] == 1

## Carves the river into `heights`, `biomes` (water reads as meadow) and `water` (1 = river cell). The centre line is
## an A* path over grid indices from the ridge foot (the west-most ridge cell of a row, one cell further west) to the
## north or south slab edge, costing: 1 per step, extra on corridors and rock, extra for distance from a wandering
## line around the straight guide from source to mouth, and never through a cell within RIVER_ROOM_CLEAR of a room
## footprint or on the ridge. The lower half of the path gets a second cell beside it. Each path step takes the level
## (lowest ground beside it) - 1, never higher than the step before. Returns {cells: Array[Vector2i] (layout cells),
## max_dev, level_first, level_last}; cells is empty when no route exists.
static func _carve_river(layout: Layout.OverworldLayout, nx: int, nz: int, x0: int, z0: int, heights: PackedInt32Array,
		biomes: PackedByteArray, is_ridge: PackedByteArray, water: PackedByteArray, noise: FastNoiseLite,
		rng: RandomNumberGenerator, land: PackedByteArray, coast: Dictionary) -> Dictionary:
	var out := {"cells": [] as Array[Vector2i], "max_dev": 0.0, "level_first": 0, "level_last": 0}
	var total := nx * nz
	var east_ix: PackedInt32Array = coast["east_ix"]
	var box: Rect2i = coast["box"]

	# Blocked: near a room footprint, ridge, or not land. Corridor cells are open but costly.
	var blocked := PackedByteArray()
	blocked.resize(total)
	for id in layout.rooms:
		var fp: Rect2i = layout.rooms[id]
		for iz in range(maxi(0, fp.position.y - RIVER_ROOM_CLEAR - z0), mini(nz - 1, fp.end.y - 1 + RIVER_ROOM_CLEAR - z0) + 1):
			for ix in range(maxi(0, fp.position.x - RIVER_ROOM_CLEAR - x0), mini(nx - 1, fp.end.x - 1 + RIVER_ROOM_CLEAR - x0) + 1):
				blocked[iz * nx + ix] = 1
	var corridor := PackedByteArray()
	corridor.resize(total)
	for road in layout.roads:
		for c: Vector2i in road["cells"]:
			var cx := c.x - x0
			var cz := c.y - z0
			if cx >= 0 and cz >= 0 and cx < nx and cz < nz:
				corridor[cz * nx + cx] = 1
	for i in total:
		if is_ridge[i] == 1 or land[i] == 0:
			blocked[i] = 1

	# Source: rows from the middle of the layout outwards; the cell just west of the main range's foot in that row (the
	# range runs to the east shoreline). Without a main range, 3 cells in from the east shoreline of the row.
	var zc := clampi(roundi(layout.bounds.get_center().y) - z0 + rng.randi_range(-3, 3), 2, nz - 3)
	var sx := -1
	var sz := -1
	for pass_i in 2:
		for k in nz:
			var iz := zc + ((k + 1) / 2 if k % 2 == 1 else -(k / 2))
			if iz < 2 or iz > nz - 3:
				continue
			var ex := east_ix[iz]
			if ex < 0:
				continue
			var cand := -1
			if pass_i == 0:
				# From the east shoreline: if that cell is massif, walk west to the first cell that is not.
				if is_ridge[iz * nx + ex] == 1:
					var ix := ex
					while ix >= 0 and is_ridge[iz * nx + ix] == 1:
						ix -= 1
					cand = ix
			else:
				cand = ex - 3
			if cand >= 2 and blocked[iz * nx + cand] == 0:
				sx = cand
				sz = iz
				break
		if sx >= 0:
			break
	if sx < 0:
		push_warning("OverworldTerrain: no river source found")
		return out

	# Mouth: the shoreline cell nearest to the point where the old river would have left the slab: the north or south
	# edge row of the land, RIVER_REACH of the land's width west of the source. Nearest first; the next one is tried when
	# a route is blocked.
	var north := rng.randf() < 0.5
	var mz := box.position.y if north else box.end.y - 1
	var mx := clampi(sx - int(box.size.x * RIVER_REACH), 2, nx - 3)
	var shore: Array = []   # [squared distance to the mouth point, grid index]
	for i in total:
		if land[i] == 0 or blocked[i] == 1:
			continue
		var ix := i % nx
		var iz := i / nx
		var coastal := false
		for dir in DIRS:
			var jx: int = ix + dir.x
			var jz: int = iz + dir.z
			if jx < 0 or jz < 0 or jx >= nx or jz >= nz or land[jz * nx + jx] == 0:
				coastal = true
				break
		if coastal:
			shore.append([(ix - mx) * (ix - mx) + (iz - mz) * (iz - mz), i])
	shore.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))

	var path: Array[Vector2i] = []
	var gdir := Vector2.ZERO
	for k in mini(shore.size(), RIVER_MOUTH_TRIES):
		var target: int = shore[k][1]
		var to_mouth := Vector2(target % nx - sx, target / nx - sz)
		if to_mouth.length() < 1.0:
			continue
		path = _river_path(nx, nz, sx, sz, target, to_mouth.normalized(), noise, blocked, corridor, biomes)
		if not path.is_empty():
			gdir = to_mouth.normalized()
			break
	if path.is_empty():
		push_warning("OverworldTerrain: no river route found")
		return out

	# Cells per step: the centre line, plus one beside it in the lower half (always the same side if it is free).
	var side := 1 if rng.randf() < 0.5 else -1
	var half := path.size() / 2
	var step_cells: Array = []   # per step: Array[int] of grid indices
	var marked := {}
	for k in path.size():
		var p := path[k]
		var cells_k: Array[int] = [p.y * nx + p.x]
		marked[cells_k[0]] = true
		if RIVER_WIDTH_LOWER > RIVER_WIDTH_SOURCE and k >= half:
			var d := path[mini(k + 1, path.size() - 1)] - path[maxi(k - 1, 0)]
			var across := Vector2i(0, 1) if absi(d.x) >= absi(d.y) else Vector2i(1, 0)
			for sgn in [side, -side]:
				var q: Vector2i = p + across * sgn
				if q.x < 1 or q.x > nx - 2 or q.y < 0 or q.y >= nz:
					continue
				var qi := q.y * nx + q.x
				if blocked[qi] == 1 or marked.has(qi):
					continue
				cells_k.append(qi)
				marked[qi] = true
				break
		step_cells.append(cells_k)

	# Levels from the ground as it was before carving: lowest ground beside the step, minus 1, never above upstream.
	var levels: Array[int] = []
	var prev := 1 << 20
	for cells_k: Array in step_cells:
		var low := 1 << 20
		for i: int in cells_k:
			low = mini(low, heights[i])
			var ix := i % nx
			var iz := i / nx
			for dir in DIRS:
				var jx: int = ix + dir.x
				var jz: int = iz + dir.z
				if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
					continue
				var j := jz * nx + jx
				if not marked.has(j) and land[j] == 1:
					low = mini(low, heights[j])
		prev = mini(prev, maxi(low - 1, 0))
		levels.append(prev)

	var cells_out: Array[Vector2i] = []
	for k in step_cells.size():
		for i: int in step_cells[k]:
			heights[i] = levels[k]
			water[i] = 1
			biomes[i] = Style.MEADOW
			cells_out.append(Vector2i(x0 + i % nx, z0 + i / nx))
	var max_dev := 0.0
	for p in path:
		var rel2 := Vector2(p.x - sx, p.y - sz)
		max_dev = maxf(max_dev, absf(rel2.x * gdir.y - rel2.y * gdir.x))
	out["cells"] = cells_out
	out["max_dev"] = max_dev
	out["level_first"] = levels[0]
	out["level_last"] = levels[levels.size() - 1]
	return out

## A* over grid indices from `start` (sx, sz) to the cell `target`, 4-way, never through a blocked cell or the outermost
## columns. Costs: 1 per step, extra on corridors and rock, extra for distance from a wandering line around the straight
## guide `gdir` from the start. Returns the cells from start to target (grid coordinates), empty when no route exists.
static func _river_path(nx: int, nz: int, sx: int, sz: int, target: int, gdir: Vector2, noise: FastNoiseLite,
		blocked: PackedByteArray, corridor: PackedByteArray, biomes: PackedByteArray) -> Array[Vector2i]:
	var total := nx * nz
	var tgx := target % nx
	var tgz := target / nx
	var g := PackedFloat32Array()
	g.resize(total)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(total)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(total)
	var start := sz * nx + sx
	var open := PackedInt32Array([start])
	var fs := PackedFloat32Array([0.0])
	g[start] = 0.0
	var found := -1
	while not open.is_empty():
		var m := 0
		for k in fs.size():
			if fs[k] < fs[m]:
				m = k
		var cur := open[m]
		open[m] = open[open.size() - 1]
		fs[m] = fs[fs.size() - 1]
		open.resize(open.size() - 1)
		fs.resize(fs.size() - 1)
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		if cur == target:
			found = cur
			break
		var ux := cur % nx
		var uz := cur / nx
		for dir in DIRS:
			var jx: int = ux + dir.x
			var jz: int = uz + dir.z
			if jx < 1 or jx > nx - 2 or jz < 0 or jz >= nz:
				continue
			var j := jz * nx + jx
			if (blocked[j] == 1 and j != target) or closed[j] == 1:
				continue
			var rel := Vector2(jx - sx, jz - sz)
			var want := clampf(noise.get_noise_2d(RIVER_NOISE_OFFSET, rel.dot(gdir)) * 3.0, -1.0, 1.0) * RIVER_MEANDER
			var step_cost := 1.0 + RIVER_MEANDER_WEIGHT * absf(rel.x * gdir.y - rel.y * gdir.x - want)
			if corridor[j] == 1:
				step_cost += RIVER_CORRIDOR_COST
			if biomes[j] == Style.ROCK:
				step_cost += RIVER_ROCK_COST
			var ng := g[cur] + step_cost
			if ng < g[j]:
				g[j] = ng
				came[j] = cur
				open.append(j)
				fs.append(ng + absi(jx - tgx) + absi(jz - tgz))
	var path: Array[Vector2i] = []
	if found < 0:
		return path
	var at := found
	while at != -1:
		path.append(Vector2i(at % nx, at / nx))
		at = came[at]
	path.reverse()
	return path

## --- land mask -------------------------------------------------------------------------------------

## Builds the land mask (see the header). `is_flat` marks every room footprint and corridor cell. Returns {land
## (PackedByteArray, 1 = land), count, box (Rect2i of grid indices around the land), east_ix (per row: grid x of the
## east-most land cell, -1 for an empty row), components, min_coast (exact distance from a room / corridor cell centre to the
## nearest non-land cell centre), necks (4-way groups of cells peeled as 1-wide), neck_cells, specks (pieces dropped), speck_cells,
## holes (cells filled), border_land (land cells on the grid border; the grid is sized so this is 0)}.
static func _build_land(layout: Layout.OverworldLayout, nx: int, nz: int, x0: int, z0: int, is_flat: PackedByteArray,
		seed: int) -> Dictionary:
	var total := nx * nz
	# d: distance to the nearest room footprint or corridor cell, a two-pass chamfer transform over the grid (1 per side
	# step, SQRT2 per diagonal step), so the radius reads as a round disc and not a diamond.
	var d := PackedFloat32Array()
	d.resize(total)
	for i in total:
		d[i] = 0.0 if is_flat[i] == 1 else INF
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			var best := d[i]
			if ix > 0:
				best = minf(best, d[i - 1] + 1.0)
			if iz > 0:
				best = minf(best, d[i - nx] + 1.0)
				if ix > 0:
					best = minf(best, d[i - nx - 1] + SQRT2)
				if ix < nx - 1:
					best = minf(best, d[i - nx + 1] + SQRT2)
			d[i] = best
	for iz in range(nz - 1, -1, -1):
		for ix in range(nx - 1, -1, -1):
			var i := iz * nx + ix
			var best := d[i]
			if ix < nx - 1:
				best = minf(best, d[i + 1] + 1.0)
			if iz < nz - 1:
				best = minf(best, d[i + nx] + 1.0)
				if ix < nx - 1:
					best = minf(best, d[i + nx + 1] + SQRT2)
				if ix > 0:
					best = minf(best, d[i + nx - 1] + SQRT2)
			d[i] = best

	# Land if d < R0 + n * A. Cells nearer than COAST_FORCE_D are land whatever the noise says.
	var cn := _noise(seed ^ Style.NOISE_SALT, Style.COAST_NOISE_FREQ, Style.COAST_OCTAVES)
	var mid_x := layout.bounds.get_center().x
	var east_x := layout.bounds.end.x
	var land := PackedByteArray()
	land.resize(total)
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			var wx := float(x0 + ix)
			var n := clampf(cn.get_noise_2d(wx + Style.COAST_NOISE_OFFSET, float(z0 + iz)), -1.0, 1.0)
			var radius := Style.COAST_R0 + n * Style.COAST_A + Style.COAST_EAST_BONUS * smoothstep(mid_x, east_x, wx)
			if d[i] < radius or d[i] < Style.COAST_FORCE_D:
				land[i] = 1

	var anchor := -1
	for i in total:
		if is_flat[i] == 1:
			anchor = i
			break
	var holes := _fill_holes(land, nx, nz)
	var thin := {}          # grid index -> true: cells peeled as part of a 1-wide neck or spur
	var specks := 0
	var speck_cells := 0
	for round_i in LAND_MAX_ROUNDS:
		var changed := false
		var dropped := _keep_piece(land, nx, nz, anchor)
		specks += dropped.x
		speck_cells += dropped.y
		changed = changed or dropped.y > 0
		# Peel cells that are one cell thick (land neither left nor right, or neither above nor below). Cells close to a
		# room or corridor are never peeled. Repeats, so a spur is eaten from its tip to its root.
		while true:
			var kill := PackedInt32Array()
			for iz in nz:
				for ix in nx:
					var i := iz * nx + ix
					if land[i] == 0 or d[i] < Style.COAST_FORCE_D:
						continue
					var west := ix > 0 and land[i - 1] == 1
					var east := ix < nx - 1 and land[i + 1] == 1
					var north := iz > 0 and land[i - nx] == 1
					var south := iz < nz - 1 and land[i + nx] == 1
					if (not west and not east) or (not north and not south):
						kill.append(i)
			if kill.is_empty():
				break
			for i in kill:
				land[i] = 0
				thin[i] = true
			changed = true
		dropped = _keep_piece(land, nx, nz, anchor)
		specks += dropped.x
		speck_cells += dropped.y
		changed = changed or dropped.y > 0
		var filled := _fill_holes(land, nx, nz)
		holes += filled
		changed = changed or filled > 0
		if not changed:
			break

	var neck_cells := {}   # Vector2i (grid x, z) -> true
	for i: int in thin:
		neck_cells[Vector2i(i % nx, i / nx)] = true

	var count := 0
	var border_land := 0
	var east_ix := PackedInt32Array()
	east_ix.resize(nz)
	east_ix.fill(-1)
	var lo := Vector2i(nx, nz)
	var hi := Vector2i(-1, -1)
	for iz in nz:
		for ix in nx:
			if land[iz * nx + ix] == 0:
				continue
			count += 1
			east_ix[iz] = ix
			lo = Vector2i(mini(lo.x, ix), mini(lo.y, iz))
			hi = Vector2i(maxi(hi.x, ix), maxi(hi.y, iz))
			if ix == 0 or iz == 0 or ix == nx - 1 or iz == nz - 1:
				border_land += 1
	if border_land > 0:
		push_warning("OverworldTerrain: the land mask touches the grid border")
	var box := Rect2i(lo, hi - lo + Vector2i.ONE) if count > 0 else Rect2i(0, 0, 1, 1)

	# Exact distance, room / corridor cell centre to the nearest non-land cell centre (only non-land cells beside land can
	# be the nearest one).
	var shore: Array[Vector2i] = []
	for iz in nz:
		for ix in nx:
			if land[iz * nx + ix] == 1:
				continue
			for dir in DIRS:
				var jx: int = ix + dir.x
				var jz: int = iz + dir.z
				if jx >= 0 and jz >= 0 and jx < nx and jz < nz and land[jz * nx + jx] == 1:
					shore.append(Vector2i(ix, iz))
					break
	var min_sq := INF
	for i in total:
		if is_flat[i] == 0:
			continue
		var p := Vector2i(i % nx, i / nx)
		for q in shore:
			min_sq = minf(min_sq, float((p - q).length_squared()))

	return {"land": land, "count": count, "box": box, "east_ix": east_ix, "components": _land_components(land, nx, nz),
			"min_coast": sqrt(min_sq) if min_sq != INF else INF, "necks": count_groups(neck_cells), "neck_cells": neck_cells.size(),
			"specks": specks, "speck_cells": speck_cells, "holes": holes, "border_land": border_land}

## Turns every non-land cell the sea cannot reach into land: flood fill (4-way) from the non-land cells on the grid border
## through non-land cells; what is left is a hole. Returns the number of cells filled.
static func _fill_holes(land: PackedByteArray, nx: int, nz: int) -> int:
	var sea := PackedByteArray()
	sea.resize(nx * nz)
	var stack := PackedInt32Array()
	for iz in nz:
		for ix in nx:
			if (ix == 0 or iz == 0 or ix == nx - 1 or iz == nz - 1) and land[iz * nx + ix] == 0:
				sea[iz * nx + ix] = 1
				stack.append(iz * nx + ix)
	while not stack.is_empty():
		var cur := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var cx := cur % nx
		var cz := cur / nx
		for dir in DIRS:
			var jx: int = cx + dir.x
			var jz: int = cz + dir.z
			if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
				continue
			var j := jz * nx + jx
			if land[j] == 0 and sea[j] == 0:
				sea[j] = 1
				stack.append(j)
	var filled := 0
	for i in nx * nz:
		if land[i] == 0 and sea[i] == 0:
			land[i] = 1
			filled += 1
	return filled

## Keeps only the 4-way connected land piece that holds cell `anchor`; every other land piece is cleared. Returns
## Vector2i(pieces cleared, cells cleared).
static func _keep_piece(land: PackedByteArray, nx: int, nz: int, anchor: int) -> Vector2i:
	var keep := PackedByteArray()
	keep.resize(nx * nz)
	if anchor >= 0 and land[anchor] == 1:
		keep[anchor] = 1
		var stack := PackedInt32Array([anchor])
		while not stack.is_empty():
			var cur := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var cx := cur % nx
			var cz := cur / nx
			for dir in DIRS:
				var jx: int = cx + dir.x
				var jz: int = cz + dir.z
				if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
					continue
				var j := jz * nx + jx
				if land[j] == 1 and keep[j] == 0:
					keep[j] = 1
					stack.append(j)
	var pieces := 0
	var cells := 0
	for start in nx * nz:
		if land[start] == 0 or keep[start] == 1:
			continue
		pieces += 1
		land[start] = 0
		cells += 1
		var stack := PackedInt32Array([start])
		while not stack.is_empty():
			var cur := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var cx := cur % nx
			var cz := cur / nx
			for dir in DIRS:
				var jx: int = cx + dir.x
				var jz: int = cz + dir.z
				if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
					continue
				var j := jz * nx + jx
				if land[j] == 1 and keep[j] == 0:
					land[j] = 0
					cells += 1
					stack.append(j)
	return Vector2i(pieces, cells)

## Number of 4-way connected land pieces.
static func _land_components(land: PackedByteArray, nx: int, nz: int) -> int:
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var pieces := 0
	for start in nx * nz:
		if land[start] == 0 or seen[start] == 1:
			continue
		pieces += 1
		seen[start] = 1
		var stack := PackedInt32Array([start])
		while not stack.is_empty():
			var cur := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var cx := cur % nx
			var cz := cur / nx
			for dir in DIRS:
				var jx: int = cx + dir.x
				var jz: int = cz + dir.z
				if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
					continue
				var j := jz * nx + jx
				if land[j] == 1 and seen[j] == 0:
					seen[j] = 1
					stack.append(j)
	return pieces

## Names the regions of `t` (see the header): reads t.biome_at() on a REGION_COARSE x REGION_COARSE grid (the biome
## most of a block's cells have), flood-fills equal biomes, names the areas of at least REGION_MIN_CELLS cells
## (biggest first, so the names a biome has go to its biggest areas), fills t.region_ids / t.region_names and prints
## every region with its size. Changes no terrain.
static func _name_regions(t: Terrain, region_seed: int) -> void:
	var cnx := (t.nx + REGION_COARSE - 1) / REGION_COARSE
	var cnz := (t.nz + REGION_COARSE - 1) / REGION_COARSE
	var coarse := PackedByteArray()
	coarse.resize(cnx * cnz)
	var block_land := PackedInt32Array()   # land cells per coarse block
	block_land.resize(cnx * cnz)
	for cz in cnz:
		for cx in cnx:
			var votes: Array[int] = [0, 0, 0]
			var n_land := 0
			for dz in REGION_COARSE:
				for dx in REGION_COARSE:
					var fx := cx * REGION_COARSE + dx
					var fz := cz * REGION_COARSE + dz
					if fx < t.nx and fz < t.nz and t.land[fz * t.nx + fx] == 1:
						votes[t.biomes[fz * t.nx + fx]] += 1
						n_land += 1
			var best := 0
			for b in 3:
				if votes[b] > votes[best]:
					best = b
			coarse[cz * cnx + cx] = best if n_land > 0 else Style.NONE
			block_land[cz * cnx + cx] = n_land
	# Connected areas of equal biome.
	var area := PackedInt32Array()
	area.resize(cnx * cnz)
	area.fill(-1)
	var areas: Array[Dictionary] = []   # {biome, blocks: PackedInt32Array, cells: int}
	for start in cnx * cnz:
		if area[start] != -1 or coarse[start] == Style.NONE:
			continue   # no land in this block
		var id := areas.size()
		var blocks := PackedInt32Array([start])
		area[start] = id
		var head := 0
		var cells := 0
		while head < blocks.size():
			var i := blocks[head]
			head += 1
			var cx := i % cnx
			var cz := i / cnx
			cells += block_land[i]
			for dir in DIRS:
				var jx: int = cx + dir.x
				var jz: int = cz + dir.z
				if jx < 0 or jz < 0 or jx >= cnx or jz >= cnz:
					continue
				var j := jz * cnx + jx
				if area[j] == -1 and coarse[j] == coarse[start]:
					area[j] = id
					blocks.append(j)
		areas.append({"biome": coarse[start], "blocks": blocks, "cells": cells})
	var order: Array[int] = []
	for id in areas.size():
		if int(areas[id]["cells"]) >= REGION_MIN_CELLS:
			order.append(id)
	order.sort_custom(func(a: int, b: int) -> bool:
		return areas[a]["cells"] > areas[b]["cells"] or (areas[a]["cells"] == areas[b]["cells"] and a < b))

	# Names: each biome's list shuffled once, handed out to its areas biggest first.
	var rng := RandomNumberGenerator.new()
	rng.seed = region_seed
	var pools: Array = []
	for src: Array[String] in [REGION_NAMES_MEADOW, REGION_NAMES_FOREST, REGION_NAMES_ROCK]:
		var list: Array[String] = src.duplicate()
		for k in range(list.size() - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var tmp := list[k]
			list[k] = list[j]
			list[j] = tmp
		pools.append(list)
	var used: Array[int] = [0, 0, 0]
	t.region_ids.resize(t.nx * t.nz)
	t.region_ids.fill(-1)
	t.region_names.clear()
	for id in order:
		var biome: int = areas[id]["biome"]
		var list: Array[String] = pools[biome]
		var region_name := list[used[biome] % list.size()]
		used[biome] += 1
		var r := t.region_names.size()
		t.region_names.append(region_name)
		for blk: int in areas[id]["blocks"]:
			for dz in REGION_COARSE:
				for dx in REGION_COARSE:
					var fx := (blk % cnx) * REGION_COARSE + dx
					var fz := (blk / cnx) * REGION_COARSE + dz
					if fx < t.nx and fz < t.nz and t.land[fz * t.nx + fx] == 1:
						t.region_ids[fz * t.nx + fx] = r
		print("region: %s (%s), %d cells" % [region_name, Style.BIOME_NAMES[biome], areas[id]["cells"]])
	print("regions: %d named, %d areas under %d cells unnamed" % [order.size(), areas.size() - order.size(), REGION_MIN_CELLS])

## `col` with its brightness scaled by `f` (alpha kept).
static func _lit(col: Color, f: float) -> Color:
	return Color(col.r * f, col.g * f, col.b * f, col.a)

## Grows one forest region from cell `start`: always the cheapest frontier cell next, cost = distance from the
## start plus edge noise, over meadow cells at least forest_clear from every room and corridor cell. Marks the
## cells forest and returns their indices (fewer than `target` if the room runs out).
static func _grow_forest(biomes: PackedByteArray, d_flat: PackedFloat32Array, noise: FastNoiseLite, nx: int, nz: int,
		x0: int, z0: int, start: int, target: int, s: Dictionary) -> PackedInt32Array:
	var got := PackedInt32Array()
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var clear: float = s["forest_clear"]
	var amp: float = s["forest_edge_noise"]
	var freq_scale: float = float(s["forest_noise_freq"]) / float(s["hill_freq"])
	var origin := Vector2(x0 + start % nx, z0 + start / nx)
	var front := PackedInt32Array([start])
	var cost := PackedFloat32Array([0.0])
	seen[start] = 1
	while got.size() < target and not front.is_empty():
		var m := 0
		for k in front.size():
			if cost[k] < cost[m]:
				m = k
		var i := front[m]
		front[m] = front[front.size() - 1]
		cost[m] = cost[cost.size() - 1]
		front.resize(front.size() - 1)
		cost.resize(cost.size() - 1)
		biomes[i] = Style.FOREST
		got.append(i)
		var ix := i % nx
		var iz := i / nx
		for dir in DIRS:
			var jx: int = ix + dir.x
			var jz: int = iz + dir.z
			if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
				continue
			var j := jz * nx + jx
			if seen[j] == 1 or biomes[j] != Style.MEADOW or d_flat[j] < clear:
				continue
			seen[j] = 1
			var p := Vector2(x0 + jx, z0 + jz)
			front.append(j)
			cost.append(p.distance_to(origin) + noise.get_noise_2d(p.x * freq_scale + 700.0, p.y * freq_scale) * amp)
	return got

## One vertical wall cell from `a` to `b` (x/z used, y ignored): lip band from `top` to `mid`, soil from `mid` to `bottom`.
static func _wall(st: SurfaceTool, a: Vector3, b: Vector3, top: float, mid: float, bottom: float,
		outward: Vector3, lip_col: Color, soil_col: Color) -> void:
	_quad(st, Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), Vector3(a.x, mid, a.z), Vector3(b.x, mid, b.z), outward, lip_col)
	if mid > bottom:
		_quad(st, Vector3(a.x, mid, a.z), Vector3(b.x, mid, b.z), Vector3(a.x, bottom, a.z), Vector3(b.x, bottom, b.z), outward, soil_col)

## Quad a, b / c, d (rows) facing `outward`, wound clockwise seen from outside (Godot's front face).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
	_tri(st, a, b, c, outward, col)
	_tri(st, b, d, c, outward, col)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		st.set_color(col)
		st.set_normal(outward)
		st.add_vertex(p)
