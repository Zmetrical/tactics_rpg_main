extends RefCounted
## Roads and decoration on the block terrain (overworld_terrain.gd): each road is a strip one cell wide and
## ROAD_HEIGHT high, built from merged box meshes along its corridor cells (one MeshInstance3D per road, surface 0
## = top with its own material so the view can recolour it, surface 1 = sides); props are voxel-style
## meshes from MapModels (data/run/map_models.gd), one MultiMeshInstance3D per kind: dense pines in forest,
## sparse trees in meadow, spires on massif summits and upper slopes (rock at or above Style.SPIRE_MIN_LEVEL), in
## clumps and never alone. Placed per cell by a seeded rng, random
## yaw in 90 degree steps, never within 1 cell of a corridor or a room.
## Landmarks: 3-4 big models (stones on a meadow hilltop, an arch on a forest edge, a tower on the ridge foot, a skull on
## rock near the boss end), one cell each, picked by score (see _pick_landmarks), in the child "Landmarks".
## Micro props: 6-10 boulders and flower patches on meadow or forest, node "MicroProps" (see _micro_props).
## Where the river crosses a corridor (the terrain's meta "bridge_cells") the road strip is replaced by a plank
## bridge at normal road height: one MeshInstance3D per crossing in the child "Bridges". Props never stand on water.
## Coordinates match overworld_terrain.gd; the returned node's transform is identity.

const Layout = preload("res://scripts/run/overworld_layout.gd")
const Style = preload("res://data/run/overworld_style.gd")
const MapModels = preload("res://data/run/map_models.gd")
const Stage3D = preload("res://scripts/battle/stage_3d.gd")

const SEED_SALT := 0xF0125

## Props (these belong in overworld_style.gd by the project rule; that file was not part of this step).
const PINE_DENSITY := 0.6      # chance per forest cell
const TREE_DENSITY := 0.04     # chance per meadow cell
const PROP_JITTER := 0.15      # +- offset of a prop inside its cell
const PROP_KINDS := ["pine", "tree", "spire"]

## Landmarks (these belong in overworld_style.gd by the project rule; that file is not part of this step).
const LANDMARK_SALT := 0x1A4D
const LANDMARK_KINDS := ["stones", "arch", "tower", "skull"]
const LANDMARK_MIN := 3
const LANDMARK_MAX := 4
const LANDMARK_CLEAR := 4.0      # at least this far from every room footprint cell, corridor cell and water cell
const LANDMARK_SPACING := 9.0    # at least this far from every other landmark
const LANDMARK_JITTER := 0.3     # random tie-break added to a score
## Micro props (these belong in overworld_style.gd by the project rule; that file is not part of this step).
const MICRO_SALT := 0x31C0
const MICRO_KINDS := ["boulder", "flowers"]
const MICRO_NAMES := {"boulder": "Boulders", "flowers": "Flowers"}
const MICRO_MIN := 6
const MICRO_MAX := 10
const MICRO_SPACING := 3.0       # at least this far from each other
const MICRO_JITTER := 0.15

const LANDMARK_D4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

## Road strips: one cell wide, this high, light stone top and darker side (flat unshaded colours).
const ROAD_HEIGHT := 0.2
const ROAD_TOP := Color("#c8c3b4")
const ROAD_SIDE := Color("#8a8678")

## Plank bridges (these belong in overworld_style.gd by the project rule; that file is not part of this step).
const PLANK_TOP := Color("#9a6b3c")
const PLANK_SIDE := Color("#5e4023")
const PLANKS_PER_CELL := 4
const PLANK_LENGTH := 0.2      # along the road; the gaps between planks share the rest of the cell evenly

## Ground height at Vector2(x, z): the top of the block under that point (river water: its own lower level, but a
## bridge cell reads as the road's ground level, so tokens cross on the planks). Reads the terrain's
## meta, so pass the node OverworldTerrain.build returned. Pass the result as terrain_height_fn.
static func height_fn_from_terrain(terrain: Node3D) -> Callable:
	if not terrain.has_meta("levels"):
		push_warning("OverworldDecor: terrain has no block levels, heights read as 0")
		return Callable()
	var sampler := _Sampler.new()
	if "biomes" in terrain:
		sampler.biomes = terrain.biomes
	if "water" in terrain:
		sampler.water = terrain.water
	if "ridge" in terrain:
		sampler.ridge = terrain.ridge
	if "land" in terrain:
		sampler.land = terrain.land
	if terrain.has_meta("bridge_cells"):
		sampler.bridge = terrain.get_meta("bridge_cells")
		sampler.crossings = int(terrain.get_meta("river_crossings"))
		sampler.ground_level = int(terrain.get_meta("slab_level"))
	sampler.levels = terrain.get_meta("levels")
	sampler.x0 = int(terrain.get_meta("x0"))
	sampler.z0 = int(terrain.get_meta("z0"))
	sampler.nx = int(terrain.get_meta("nx"))
	sampler.nz = int(terrain.get_meta("nz"))
	# A Callable does not keep a RefCounted alive: the terrain node holds the sampler so the Callable stays valid.
	terrain.set_meta("height_sampler", sampler)
	return Callable(sampler, "sample")

class _Sampler extends RefCounted:
	var levels := PackedInt32Array()
	var biomes := PackedByteArray()   # Style.MEADOW / FOREST / ROCK per cell, same layout as levels
	var water := PackedByteArray()    # 1 = river cell, same layout as levels (empty: no river)
	var ridge := PackedByteArray()    # 1 = ridge cell, same layout as levels
	var land := PackedByteArray()    # 1 = land (has a block), same layout as levels (empty: every cell counts as land)
	var bridge := {}                  # Vector2i -> true: corridor cells under water
	var crossings := 0
	var ground_level := 1             # level of the road ground, where bridges stand
	var x0 := 0
	var z0 := 0
	var nx := 1
	var nz := 1

	func sample(p: Vector2) -> float:
		var ix := clampi(roundi(p.x) - x0, 0, nx - 1)
		var iz := clampi(roundi(p.y) - z0, 0, nz - 1)
		var lv := levels[iz * nx + ix]
		if bridge.has(Vector2i(x0 + ix, z0 + iz)):
			lv = ground_level
		return -1.0 if lv < 0 else lv * Stage3D.STEP

	## true when grid index `i` is land (no land array: every cell is).
	func is_land_i(i: int) -> bool:
		return land.size() != nx * nz or land[i] == 1

	## true when the cell is inside the grid and land.
	func is_land(cell: Vector2i) -> bool:
		var ix := cell.x - x0
		var iz := cell.y - z0
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
			return false
		return is_land_i(iz * nx + ix)

	func is_water(cell: Vector2i) -> bool:
		var ix := cell.x - x0
		var iz := cell.y - z0
		if water.size() != nx * nz or ix < 0 or iz < 0 or ix >= nx or iz >= nz:
			return false
		return water[iz * nx + ix] == 1

## Node3D "OverworldDecor" with child "Roads" (one MeshInstance3D "road_<from>_<to>" per road, each with its
## own top material so the view can recolor it), "Bridges" (one MeshInstance3D per river crossing) and MultiMeshInstance3Ds "Pines", "Trees" and "Spires".
## `terrain_height_fn` takes a Vector2(x, z) and returns the ground height (see height_fn_from_terrain).
@warning_ignore("shadowed_global_identifier")
static func build(layout: Layout.OverworldLayout, terrain_height_fn: Callable, seed: int, style: Dictionary = {}) -> Node3D:
	var s: Dictionary = style if not style.is_empty() else Style.GRASSLAND
	var base := seed ^ SEED_SALT
	var root := Node3D.new()
	root.name = "OverworldDecor"

	# Roads.
	var roads := Node3D.new()
	roads.name = "Roads"
	root.add_child(roads)
	var taken := {}   # cell -> true: a cell shared by two roads is drawn by the first one only
	for road in layout.roads:
		roads.add_child(_road_mesh(road, layout, terrain_height_fn, taken))

	root.add_child(_bridges(layout, terrain_height_fn))

	var picks := _pick_landmarks(layout, terrain_height_fn, seed)
	root.add_child(_landmark_nodes(picks, terrain_height_fn, seed))

	var occupied := {}   # Vector2i -> true: cells holding a pine, tree or spire
	for mmi in _props(layout, terrain_height_fn, seed, picks, occupied):
		root.add_child(mmi)
	root.add_child(_micro_props(layout, terrain_height_fn, seed, picks, occupied))
	return root

# --- roads -------------------------------------------------------------------------------

## One MeshInstance3D per road: the corridor cells (door to door) merged into straight runs, one box per run.
## Cells inside the two end rooms' footprints are left to the room slabs, cells already drawn by an earlier
## road and river cells are skipped (a bridge spans those). A run also ends where the ground height changes, so every box stands on
## the ground. Surface 0 is the top (own material), surface 1 the sides.
static func _road_mesh(road: Dictionary, layout: Layout.OverworldLayout, height_fn: Callable, taken: Dictionary) -> MeshInstance3D:
	var from_rect: Rect2i = layout.rooms.get(road["from_id"], Rect2i())
	var to_rect: Rect2i = layout.rooms.get(road["to_id"], Rect2i())
	var cells: Array[Vector2i] = []
	var ys: Array[float] = []
	for cell: Vector2i in road["cells"]:
		if from_rect.has_point(cell) or to_rect.has_point(cell) or taken.has(cell):
			continue
		if _water_at(height_fn, cell):
			continue   # river: the bridge (see _bridges) carries the road across
		var y: float = (height_fn.call(Vector2(cell)) if height_fn.is_valid() else 0.0)
		if y < 0.0:
			continue
		taken[cell] = true
		cells.append(cell)
		ys.append(y)
	var b := new_boxes()
	var any := false
	var i := 0
	while i < cells.size():
		var j := i
		if i + 1 < cells.size() and (cells[i + 1] - cells[i]).abs() in [Vector2i(1, 0), Vector2i(0, 1)]:
			var dir := cells[i + 1] - cells[i]
			while j + 1 < cells.size() and cells[j + 1] - cells[j] == dir and is_equal_approx(ys[j + 1], ys[i]):
				j += 1
		var lo := Vector3(minf(cells[i].x, cells[j].x) - 0.5, ys[i], minf(cells[i].y, cells[j].y) - 0.5)
		var hi := Vector3(maxf(cells[i].x, cells[j].x) + 0.5, ys[i] + ROAD_HEIGHT, maxf(cells[i].y, cells[j].y) + 0.5)
		add_box(b, lo, hi)
		any = true
		i = j + 1
	var mi := MeshInstance3D.new()
	mi.name = "road_%d_%d" % [road["from_id"], road["to_id"]]
	mi.mesh = commit_boxes(b, _flat_material(ROAD_TOP), _flat_material(ROAD_SIDE)) if any else ArrayMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# --- bridges -----------------------------------------------------------------------------

static func _water_at(height_fn: Callable, cell: Vector2i) -> bool:
	var sm := height_fn.get_object() as _Sampler if height_fn.is_valid() else null
	return sm != null and sm.is_water(cell)

## Node3D "Bridges": one MeshInstance3D "bridge_<n>" per river crossing (4-way connected group of corridor cells
## under water). Each cell carries PLANKS_PER_CELL planks across the road, deck top at the road strip's top
## (ground level + ROAD_HEIGHT), so the road reads as unbroken. Prints the crossing and bridge counts.
static func _bridges(layout: Layout.OverworldLayout, height_fn: Callable) -> Node3D:
	var node := Node3D.new()
	node.name = "Bridges"
	var sm := height_fn.get_object() as _Sampler if height_fn.is_valid() else null
	if sm == null or sm.bridge.is_empty():
		print("river: crossings %d, bridges 0" % (sm.crossings if sm != null else 0))
		return node
	# Road direction at each bridge cell (neighbours along the road; the larger axis wins at a corner).
	var along := {}   # Vector2i -> true when the road runs along X at that cell
	for road in layout.roads:
		var cells: Array = road["cells"]
		for i in cells.size():
			var c: Vector2i = cells[i]
			if not sm.bridge.has(c) or along.has(c):
				continue
			var a: Vector2i = cells[maxi(i - 1, 0)]
			var b: Vector2i = cells[mini(i + 1, cells.size() - 1)]
			var d := b - a
			along[c] = absi(d.x) >= absi(d.y)
	# Group the bridge cells.
	var seen := {}
	var base := float(sm.ground_level) * Stage3D.STEP
	var count := 0
	var off_land := 0   # bridge cells on non-land cells that were skipped (a bridge is only ever built over land cells)
	for start: Vector2i in sm.bridge:
		if seen.has(start):
			continue
		var group: Array[Vector2i] = []
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			group.append(cur)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = cur + d
				if sm.bridge.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		var b := new_boxes()
		var gap := (1.0 - PLANKS_PER_CELL * PLANK_LENGTH) / (PLANKS_PER_CELL + 1)
		var any_land := false
		for c in group:
			if not sm.is_land(c):
				off_land += 1
				continue   # never a plank over the background
			any_land = true
			var x_run: bool = along.get(c, true)
			for k in PLANKS_PER_CELL:
				var t0 := -0.5 + gap + k * (PLANK_LENGTH + gap)
				var lo := Vector3(c.x - 0.5, base, c.y - 0.5)
				var hi := Vector3(c.x + 0.5, base + ROAD_HEIGHT, c.y + 0.5)
				if x_run:
					lo.x = c.x + t0
					hi.x = c.x + t0 + PLANK_LENGTH
				else:
					lo.z = c.y + t0
					hi.z = c.y + t0 + PLANK_LENGTH
				add_box(b, lo, hi)
		if not any_land:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "bridge_%d" % count
		mi.mesh = commit_boxes(b, _flat_material(PLANK_TOP), _flat_material(PLANK_SIDE))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
		count += 1
	print("river: crossings %d, bridges %d" % [sm.crossings, count])
	print("bridge cells on non-land cells: %d" % off_land)
	return node

static func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.disable_receive_shadows = true
	return mat

# --- boxes (also used by run_map_view.gd for the room slabs) -----------------------------------

## Two SurfaceTools [tops, sides] to fill with add_box and turn into a mesh with commit_boxes.
static func new_boxes() -> Array[SurfaceTool]:
	var tops := SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	return [tops, sides]

## Adds the axis-aligned box lo..hi: its top to surface 0, its four sides to surface 1 (the bottom is never seen).
static func add_box(b: Array[SurfaceTool], lo: Vector3, hi: Vector3) -> void:
	var top: SurfaceTool = b[0]
	var side: SurfaceTool = b[1]
	_quad(top, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3.UP)
	_quad(side, Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3.FORWARD)
	_quad(side, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3.BACK)
	_quad(side, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3.LEFT)
	_quad(side, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3.RIGHT)

## Surface 0 = tops with top_mat, surface 1 = sides with side_mat. Call only after at least one add_box.
static func commit_boxes(b: Array[SurfaceTool], top_mat: Material, side_mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	b[0].commit(mesh)
	b[1].commit(mesh)
	mesh.surface_set_material(0, top_mat)
	mesh.surface_set_material(1, side_mat)
	return mesh

## A quad a, b, c, d (a b / c d rows) facing `outward`.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_tri(st, a, b, c, outward, Color.WHITE)
	_tri(st, b, d, c, outward, Color.WHITE)

# --- landmarks ---------------------------------------------------------------------------

## Picks 3-4 landmarks: [{kind, cell: Vector2i, biome: int}], printed one per line. The kinds are tried in a seeded
## order and every kind is used at most once; a kind with no qualifying cell is skipped for the next one, so there
## are fewer than LANDMARK_MIN only when too few cells qualify. A cell qualifies when it is at least
## LANDMARK_CLEAR from every room footprint cell, corridor cell and water cell, at least LANDMARK_SPACING from the
## landmarks already placed, and not on the slab's outer ring; the best score of the kind wins (see _landmark_score).
@warning_ignore("shadowed_global_identifier")
static func _pick_landmarks(layout: Layout.OverworldLayout, height_fn: Callable, seed: int) -> Array[Dictionary]:
	var picks: Array[Dictionary] = []
	var sm := height_fn.get_object() as _Sampler if height_fn.is_valid() else null
	if sm == null or sm.biomes.size() != sm.nx * sm.nz or sm.ridge.size() != sm.nx * sm.nz or sm.water.size() != sm.nx * sm.nz:
		push_warning("OverworldDecor: no terrain lookups, no landmarks")
		return picks
	var nx := sm.nx
	var nz := sm.nz
	# Cells too close to a room, corridor or water.
	var near := PackedByteArray()
	near.resize(nx * nz)
	for id in layout.rooms:
		var fp: Rect2i = layout.rooms[id]
		for x in range(fp.position.x, fp.end.x):
			for z in range(fp.position.y, fp.end.y):
				_mark_near(near, sm, Vector2i(x, z))
	for road in layout.roads:
		for c: Vector2i in road["cells"]:
			_mark_near(near, sm, c)
	for i in nx * nz:
		if sm.water.size() == nx * nz and sm.water[i] == 1:
			_mark_near(near, sm, Vector2i(sm.x0 + i % nx, sm.z0 + i / nx))
	# The boss end: the room furthest along X.
	var boss := Vector2(-INF, 0.0)
	for id in layout.node_pos:
		var pos: Vector2 = layout.node_pos[id]
		if pos.x > boss.x:
			boss = pos

	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ SEED_SALT ^ LANDMARK_SALT
	var want := rng.randi_range(LANDMARK_MIN, LANDMARK_MAX)
	var order: Array = LANDMARK_KINDS.duplicate()
	for k in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = order[k]
		order[k] = order[j]
		order[j] = tmp
	for kind: String in order:
		if picks.size() >= want:
			break
		var best := -INF
		var best_i := -1
		for iz in range(1, nz - 1):
			for ix in range(1, nx - 1):
				var i := iz * nx + ix
				if near[i] == 1 or not sm.is_land_i(i):
					continue
				var cell := Vector2i(sm.x0 + ix, sm.z0 + iz)
				var far := true
				for p in picks:
					if Vector2(cell).distance_to(Vector2(p["cell"])) < LANDMARK_SPACING:
						far = false
						break
				if not far:
					continue
				var sc := _landmark_score(kind, sm, ix, iz, boss)
				if sc == -INF:
					continue
				sc += rng.randf() * LANDMARK_JITTER
				if sc > best:
					best = sc
					best_i = i
		if best_i < 0:
			continue
		picks.append({"kind": kind, "cell": Vector2i(sm.x0 + best_i % nx, sm.z0 + best_i / nx), "biome": sm.biomes[best_i]})
	var lm_off := 0
	for p in picks:
		if not sm.is_land(p["cell"]):
			lm_off += 1
	print("landmarks on non-land cells: %d" % lm_off)
	for p in picks:
		var c: Vector2i = p["cell"]
		print("landmark: %s, biome %s, cell (%d, %d)" % [p["kind"], Style.BIOME_NAMES[p["biome"]], c.x, c.y])
	if picks.is_empty():
		print("landmarks: none qualify")
	return picks

## Marks every cell closer than LANDMARK_CLEAR to `cell` in `near` (grid layout of the sampler).
static func _mark_near(near: PackedByteArray, sm: _Sampler, cell: Vector2i) -> void:
	var r := int(ceilf(LANDMARK_CLEAR))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dz).length() >= LANDMARK_CLEAR:
				continue
			var ix := cell.x + dx - sm.x0
			var iz := cell.y + dz - sm.z0
			if ix >= 0 and iz >= 0 and ix < sm.nx and iz < sm.nz:
				near[iz * sm.nx + ix] = 1

## Score of grid cell (ix, iz) for a landmark `kind`, or -INF when it cannot hold that kind. The cell is never on
## the slab's outer ring. Slope = the largest level difference to the 4 neighbours; every kind prefers gentle slopes.
## - stones: meadow, above the base level, no higher cell within 2 (a hilltop); higher is better.
## - arch: forest with meadow beside it (a forest edge); best with 3 of its 8 neighbours meadow (a straight edge).
## - tower: rock with a non-rock neighbour (a rock edge); a ridge cell counts as ridge foot (+4), lower is better.
## - skull: rock; the closer to the boss room the better.
static func _landmark_score(kind: String, sm: _Sampler, ix: int, iz: int, boss: Vector2) -> float:
	var nx := sm.nx
	var i := iz * nx + ix
	var lv := sm.levels[i]
	var biome := sm.biomes[i]
	var slope := 0
	for d in LANDMARK_D4:
		slope = maxi(slope, absi(lv - sm.levels[(iz + d.y) * nx + ix + d.x]))
	match kind:
		"stones":
			if biome != Style.MEADOW or lv <= sm.ground_level:
				return -INF
			var lower := 0
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var jx := ix + dx
					var jz := iz + dz
					if jx < 0 or jz < 0 or jx >= nx or jz >= sm.nz:
						continue
					var other := sm.levels[jz * nx + jx]
					if other > lv:
						return -INF
					if other < lv:
						lower += 1
			return lv * 3.0 + lower * 0.1 - slope * 2.0
		"arch":
			if biome != Style.FOREST:
				return -INF
			var meadow := 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var j := (iz + dz) * nx + ix + dx
					if (dx != 0 or dz != 0) and sm.biomes[j] == Style.MEADOW and sm.water[j] == 0:
						meadow += 1
			if meadow == 0:
				return -INF
			return 5.0 - absf(meadow - 3.0) - slope * 2.0
		"tower":
			if biome != Style.ROCK:
				return -INF
			var edge := false
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if sm.biomes[(iz + dz) * nx + ix + dx] != Style.ROCK:
						edge = true
			if not edge:
				return -INF
			return (4.0 if sm.ridge[i] == 1 else 0.0) - lv * 0.5 - slope * 1.5
		"skull":
			if biome != Style.ROCK:
				return -INF
			return -Vector2(sm.x0 + ix, sm.z0 + iz).distance_to(boss) * 0.3 - slope * 1.5 - lv * 0.2
	return -INF

## Node3D "Landmarks": one MeshInstance3D per pick, named after its kind, standing on the block's top with a
## random yaw in 90 degree steps.
@warning_ignore("shadowed_global_identifier")
static func _landmark_nodes(picks: Array[Dictionary], height_fn: Callable, seed: int) -> Node3D:
	var node := Node3D.new()
	node.name = "Landmarks"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ SEED_SALT ^ LANDMARK_SALT ^ 0x55
	for p in picks:
		var mesh := MapModels.make(p["kind"])
		var yaw := rng.randi_range(0, 3) * PI * 0.5
		if mesh == null:
			continue
		var cell: Vector2i = p["cell"]
		var mi := MeshInstance3D.new()
		mi.name = p["kind"]
		mi.mesh = mesh
		mi.position = Vector3(cell.x, float(height_fn.call(Vector2(cell))), cell.y)
		mi.rotation.y = yaw
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	return node

# --- micro props -------------------------------------------------------------------------

## Node3D "MicroProps" with a MultiMeshInstance3D "Boulders" and one "Flowers" (when used). MICRO_MIN..MICRO_MAX
## props, kinds alternating from a random start; flowers on meadow, boulders on meadow or forest. A cell qualifies
## when it is at least 2 cells from every corridor cell, room footprint cell, water cell and landmark, holds no
## pine / tree / spire (`occupied`), is not on the slab's outer ring and is MICRO_SPACING from the micro props
## already placed; fewer are placed when the cells run out. Prints the count.
@warning_ignore("shadowed_global_identifier")
static func _micro_props(layout: Layout.OverworldLayout, height_fn: Callable, seed: int, picks: Array[Dictionary],
		occupied: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "MicroProps"
	var sm := height_fn.get_object() as _Sampler if height_fn.is_valid() else null
	if sm == null or sm.biomes.size() != sm.nx * sm.nz or sm.water.size() != sm.nx * sm.nz:
		push_warning("OverworldDecor: no terrain lookups, no micro props")
		return node
	var flat := {}   # Vector2i -> true: every room footprint cell and corridor cell
	for id in layout.rooms:
		var fp: Rect2i = layout.rooms[id]
		for x in range(fp.position.x, fp.end.x):
			for z in range(fp.position.y, fp.end.y):
				flat[Vector2i(x, z)] = true
	for road in layout.roads:
		for c: Vector2i in road["cells"]:
			flat[c] = true
	var landmark_cells := {}
	for p in picks:
		landmark_cells[p["cell"]] = true
	var cands: Array[Vector2i] = []
	for iz in range(1, sm.nz - 1):
		for ix in range(1, sm.nx - 1):
			if not sm.is_land_i(iz * sm.nx + ix):
				continue
			var biome := sm.biomes[iz * sm.nx + ix]
			if biome != Style.MEADOW and biome != Style.FOREST:
				continue
			var cell := Vector2i(sm.x0 + ix, sm.z0 + iz)
			if occupied.has(cell) or _near(flat, cell, 1) or _near(landmark_cells, cell, 1):
				continue
			var wet := false
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					wet = wet or sm.is_water(Vector2i(cell.x + dx, cell.y + dz))
			if not wet:
				cands.append(cell)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ SEED_SALT ^ MICRO_SALT
	var want := rng.randi_range(MICRO_MIN, MICRO_MAX)
	var kind_at := rng.randi_range(0, 1)
	var places := {"boulder": [], "flowers": []}
	var yaws := {"boulder": [], "flowers": []}
	var chosen: Array[Vector2i] = []
	var k := 0
	while chosen.size() < want and not cands.is_empty():
		var kind: String = MICRO_KINDS[(kind_at + k) % MICRO_KINDS.size()]
		k += 1
		var pool: Array[Vector2i] = []
		for c in cands:
			if kind == "boulder" or sm.biomes[(c.y - sm.z0) * sm.nx + c.x - sm.x0] == Style.MEADOW:
				pool.append(c)
		if pool.is_empty():
			if k > 2 * MICRO_KINDS.size():
				break   # neither kind fits any cell left
			continue
		var cell := pool[rng.randi_range(0, pool.size() - 1)]
		var jx := rng.randf_range(-MICRO_JITTER, MICRO_JITTER)
		var jz := rng.randf_range(-MICRO_JITTER, MICRO_JITTER)
		var yaw := rng.randi_range(0, 3) * PI * 0.5
		chosen.append(cell)
		var keep: Array[Vector2i] = []
		for c in cands:
			if Vector2(c).distance_to(Vector2(cell)) >= MICRO_SPACING:
				keep.append(c)
		cands = keep
		places[kind].append(Vector3(cell.x + jx, float(height_fn.call(Vector2(cell))), cell.y + jz))
		yaws[kind].append(yaw)

	var counts := PackedStringArray()
	for kind: String in MICRO_KINDS:
		var list: Array = places[kind]
		counts.append("%s %d" % [kind, list.size()])
		var mesh := MapModels.make(kind)
		if mesh == null or list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaws[kind][i]), list[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = MICRO_NAMES[kind]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	print("micro props: %d (%s)" % [chosen.size(), ", ".join(counts)])
	var micro_off := 0
	for c in chosen:
		if not sm.is_land(c):
			micro_off += 1
	print("micro props on non-land cells: %d" % micro_off)
	return node

# --- props -------------------------------------------------------------------------------

## One MultiMeshInstance3D per kind in PROP_KINDS ("Pines", "Trees", "Spires"). Cells are visited in order and
## each rolls its biome's density: pine on forest, tree on meadow (not next to another tree), spire on
## rock at summit and upper-slope level (Style.SPIRE_*): density follows a clump noise, a spire is never next to another
## one, and a spire with no other spire within Style.SPIRE_LONE_RADIUS cells is dropped. A cell within 1 cell (8 neighbours) of a corridor cell or
## room footprint, on river water, within 1 cell of a landmark, or on the slab's outer ring, stays empty. Needs the height fn of height_fn_from_terrain
## (it carries the biomes); without it there are no props. Prints the instance count per kind.
@warning_ignore("shadowed_global_identifier")
static func _props(layout: Layout.OverworldLayout, height_fn: Callable, seed: int, picks: Array[Dictionary] = [],
		occupied: Dictionary = {}) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	var sm := height_fn.get_object() as _Sampler if height_fn.is_valid() else null
	if sm == null or sm.biomes.size() != sm.nx * sm.nz:
		push_warning("OverworldDecor: no terrain biomes, no props")
		return out
	var flat := {}   # Vector2i -> true: every room footprint cell and corridor cell
	for id in layout.rooms:
		var fp: Rect2i = layout.rooms[id]
		for x in range(fp.position.x, fp.end.x):
			for z in range(fp.position.y, fp.end.y):
				flat[Vector2i(x, z)] = true
	for road in layout.roads:
		for c: Vector2i in road["cells"]:
			flat[c] = true
	var spire_noise := FastNoiseLite.new()
	spire_noise.seed = seed ^ Style.NOISE_SALT ^ 0x5B17E
	spire_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	spire_noise.frequency = Style.SPIRE_CLUMP_FREQ
	var spire_cells: Array[Vector2i] = []   # cells holding a spire, in the order of places["spire"]
	var landmark_cells := {}   # Vector2i -> true: a landmark's cell; props keep 1 cell away from it
	for p in picks:
		landmark_cells[p["cell"]] = true

	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ Style.NOISE_SALT
	var places := {"pine": [], "tree": [], "spire": []}   # kind -> [Vector3(x, y, z) + yaw in a parallel array]
	var yaws := {"pine": [], "tree": [], "spire": []}
	var taken := {}   # Vector2i -> true: cells holding a tree or spire (they keep one cell apart)
	for iz in range(1, sm.nz - 1):
		for ix in range(1, sm.nx - 1):
			var i := iz * sm.nx + ix
			if not sm.is_land_i(i):
				continue   # no block here: no prop
			var biome := sm.biomes[i]
			var kind := ""
			var chance := 0.0
			if biome == Style.FOREST:
				kind = "pine"
				chance = PINE_DENSITY
			elif biome == Style.MEADOW:
				kind = "tree"
				chance = TREE_DENSITY
			elif biome == Style.ROCK and sm.levels[i] >= Style.SPIRE_MIN_LEVEL:
				kind = "spire"
				var clump := smoothstep(Style.SPIRE_CLUMP_FROM, Style.SPIRE_CLUMP_TO,
						spire_noise.get_noise_2d(sm.x0 + ix, sm.z0 + iz) * 0.5 + 0.5)
				chance = Style.SPIRE_DENSITY * clump
			if kind == "":
				continue
			var cell := Vector2i(sm.x0 + ix, sm.z0 + iz)
			# The rng is drawn for every candidate cell, so a change elsewhere does not reshuffle the rest.
			var roll := rng.randf()
			var jx := rng.randf_range(-PROP_JITTER, PROP_JITTER)
			var jz := rng.randf_range(-PROP_JITTER, PROP_JITTER)
			var yaw := rng.randi_range(0, 3) * PI * 0.5
			if roll >= chance or _near(flat, cell, 1) or sm.is_water(cell) or _near(landmark_cells, cell, 1):
				continue
			if kind != "pine" and _near(taken, cell, 1):
				continue
			if kind != "pine":
				taken[cell] = true
			occupied[cell] = true
			places[kind].append(Vector3(cell.x + jx, sm.levels[i] * Stage3D.STEP, cell.y + jz))
			yaws[kind].append(yaw)
			if kind == "spire":
				spire_cells.append(cell)

	# Spires come in clusters: drop every spire with no other spire within SPIRE_LONE_RADIUS cells.
	var spire_set := {}
	for c in spire_cells:
		spire_set[c] = true
	var kept_places: Array = []
	var kept_yaws: Array = []
	for k in spire_cells.size():
		var c := spire_cells[k]
		var has_mate := false
		for dx in range(-Style.SPIRE_LONE_RADIUS, Style.SPIRE_LONE_RADIUS + 1):
			for dz in range(-Style.SPIRE_LONE_RADIUS, Style.SPIRE_LONE_RADIUS + 1):
				if (dx != 0 or dz != 0) and spire_set.has(Vector2i(c.x + dx, c.y + dz)):
					has_mate = true
		if has_mate:
			kept_places.append(places["spire"][k])
			kept_yaws.append(yaws["spire"][k])
		else:
			occupied.erase(c)
			taken.erase(c)
	places["spire"] = kept_places
	yaws["spire"] = kept_yaws

	var counts := PackedStringArray()
	for kind: String in PROP_KINDS:
		var mesh := MapModels.make(kind)
		var list: Array = places[kind]
		counts.append("%s %d" % [kind, list.size()])
		if mesh == null or list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, yaws[kind][k]), list[k]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = kind.capitalize() + "s"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(mmi)
	print("props: ", ", ".join(counts))
	var props_off := 0
	for kind: String in PROP_KINDS:
		for pos: Vector3 in places[kind]:
			if not sm.is_land(Vector2i(roundi(pos.x), roundi(pos.z))):
				props_off += 1
	print("props (pines, trees, spires) on non-land cells: %d" % props_off)
	return out

## true when `cell` or one of its 8 neighbours (out to `r` cells) is a key of `cells`.
static func _near(cells: Dictionary, cell: Vector2i, r: int) -> bool:
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if cells.has(Vector2i(cell.x + dx, cell.y + dz)):
				return true
	return false

## One flat triangle. `outward` is a direction the front face must look towards; the winding is
## flipped if needed (Godot front faces are clockwise).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)
