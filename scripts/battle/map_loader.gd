extends RefCounted
## Loads a predefined map scene and converts it to a MapResult. No rendering; runs headless.
##
## Map scenes live at res://scenes/maps/<biome>/<size>/<name>.tscn and contain:
##   Tiles         GridMap  cell (x, 0, z) -> Vector2i(x, z). Item 0-3 = tile of that height, 4 = wall.
##                          An absent cell is a hole. Cell centering is off, so tiles sit on integers.
##   PlayerStarts  Node3D   Marker3D children; x / z give the cell.
##   EnemyStarts   Node3D   Marker3D children; x / z give the cell.
##
## Randomness (all from the passed RNG): which scene in the folder, how many enemies, and which
## enemy markers are used. Enemy TYPES are never random: the biome's ordered roster decides.

const BiomeData = preload("res://scripts/battle/biome_data.gd")

const MAPS_ROOT := "res://scenes/maps"
const WALL_ITEM := 4

class MapResult:
	var valid := false
	var width := 0
	var height := 0
	## Legend: '0'-'3' height, '#' wall, '.' hole, 'P' / 'E' start tiles.
	var rows: Array[String] = []
	var player_cells: Array[Vector2i] = []
	## Row-major (y, then x): the same order battle_view scans 'E' tiles.
	var enemy_cells: Array[Vector2i] = []
	## Parallel to enemy_cells. UnitData resources.
	var enemy_units: Array[Resource] = []
	## P/E cell -> tile height to paint.
	var start_heights: Dictionary = {}
	## Decoration placed in the map scene (FBX instances, etc.): [{scene: PackedScene, xform: Transform3D}].
	## Anything under the scene root that isn't Tiles / PlayerStarts / EnemyStarts counts as a prop.
	var props: Array[Dictionary] = []
	## Grid rules from GridProp nodes: [{id, name, cells, blocks_movement, blocks_projectiles, targetable}].
	## battle_view feeds these to Grid.add_prop. Plain data only: the map scene is freed after loading.
	var grid_props: Array[Dictionary] = []
	var scene_path := ""
	var size_name := ""

## Sorted scene paths for one biome + size folder. Empty when the folder is missing or empty.
static func list_maps(biome_name: String, size_name: String) -> Array[String]:
	var dir := "%s/%s/%s" % [MAPS_ROOT, biome_name, size_name]
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		# Exported builds list scenes as <name>.tscn.remap.
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tscn"):
			out.append("%s/%s" % [dir, file])
	out.sort()
	return out

## Picks one scene in the biome + size folder and converts it.
static func load_map(biome_name: String, size_name: String, biome: BiomeData, rng: RandomNumberGenerator, player_count: int) -> MapResult:
	var paths := list_maps(biome_name, size_name)
	if paths.is_empty():
		push_error("map_loader: no map scenes in %s/%s/%s" % [MAPS_ROOT, biome_name, size_name])
		var empty := MapResult.new()
		empty.size_name = size_name
		return empty
	var path: String = paths[rng.randi_range(0, paths.size() - 1)]
	var r := build(path, biome, rng, player_count)
	r.size_name = size_name
	return r

## Converts one map scene. Returns valid = false (after push_error) on any authoring problem.
static func build(path: String, biome: BiomeData, rng: RandomNumberGenerator, player_count: int) -> MapResult:
	var r := MapResult.new()
	r.scene_path = path
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("map_loader: cannot load %s" % path)
		return r
	var root := packed.instantiate()
	var tiles := root.get_node_or_null("Tiles") as GridMap
	var p_group := root.get_node_or_null("PlayerStarts")
	var e_group := root.get_node_or_null("EnemyStarts")
	if tiles == null or p_group == null or e_group == null:
		push_error("map_loader: %s needs Tiles (GridMap), PlayerStarts and EnemyStarts" % path)
		root.free()
		return r

	# Tiles -> heights / walls.
	var heights: Dictionary = {}  # Vector2i -> int 0-3
	var walls: Dictionary = {}    # Vector2i -> true
	var width := 0
	var height := 0
	for c: Vector3i in tiles.get_used_cells():
		var cell := Vector2i(c.x, c.z)
		var item := tiles.get_cell_item(c)
		if c.y != 0 or c.x < 0 or c.z < 0 or item < 0 or item > WALL_ITEM:
			push_error("map_loader: %s has a bad tile at %s (item %d)" % [path, str(c), item])
			root.free()
			return r
		if item == WALL_ITEM:
			walls[cell] = true
		else:
			heights[cell] = item
		width = maxi(width, c.x + 1)
		height = maxi(height, c.z + 1)

	var p_cells := _marker_cells(p_group)
	var e_cells := _marker_cells(e_group)
	var props := _collect_props(root)
	var grid_props := _collect_grid_props(root)
	root.free()

	# Markers must stand on open tiles and not overlap.
	var seen: Dictionary = {}
	for cell in p_cells + e_cells:
		if not heights.has(cell) or seen.has(cell):
			push_error("map_loader: %s has a start marker at %s that is on a wall, a hole or another marker" % [path, str(cell)])
			return r
		seen[cell] = true
	# Props that block walking: nobody may start inside one, and two of them should not share a cell.
	var prop_blocked: Dictionary = {}  # Vector2i -> prop name
	for rec: Dictionary in grid_props:
		if not rec["blocks_movement"]:
			continue
		for c: Vector2i in rec["cells"]:
			if seen.has(c):
				push_error("map_loader: %s has a start marker at %s inside prop '%s'" % [path, str(c), rec["name"]])
				return r
			if prop_blocked.has(c):
				push_warning("map_loader: %s: props '%s' and '%s' overlap at %s" % [path, prop_blocked[c], rec["name"], str(c)])
			prop_blocked[c] = rec["name"]
	if p_cells.size() < player_count or player_count < 1:
		push_error("map_loader: %s has %d player markers, needs %d" % [path, p_cells.size(), player_count])
		return r

	# Enemies: N random in the biome's range, clamped; types are the roster prefix.
	var n := rng.randi_range(biome.enemy_count_min, maxi(biome.enemy_count_min, biome.enemy_count_max))
	n = mini(n, mini(biome.enemy_roster.size(), e_cells.size()))
	if n < 1:
		push_error("map_loader: %s gives no enemies (roster %d, markers %d)" % [path, biome.enemy_roster.size(), e_cells.size()])
		return r
	var pool: Array[Vector2i] = []
	pool.assign(e_cells)
	var placed: Array[Dictionary] = []
	for i in n:
		var j := rng.randi_range(0, pool.size() - 1)
		placed.append({"cell": pool[j], "unit": biome.enemy_roster[i]})
		pool.remove_at(j)
	placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector2i = a["cell"]
		var cb: Vector2i = b["cell"]
		return ca.y < cb.y or (ca.y == cb.y and ca.x < cb.x))

	for i in player_count:
		r.player_cells.append(p_cells[i])
	for p in placed:
		r.enemy_cells.append(p["cell"])
		r.enemy_units.append(p["unit"])
	for c in r.player_cells + r.enemy_cells:
		r.start_heights[c] = heights[c]

	r.props = props
	r.grid_props = grid_props
	r.width = width
	r.height = height
	r.rows = _rows(width, height, heights, walls, r)
	r.valid = true
	return r

## Instanced scenes (e.g. an imported .fbx) directly under the map root -> prop records, so the stage
## can re-create them. The map scene itself is freed after loading and never shown.
## A GridProp wrapper (scripts/battle/grid_prop.gd) contributes the scenes instanced inside it, each
## with the wrapper's transform folded in; if the wrapper is itself an instanced scene, that counts too.
static func _collect_props(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child in root.get_children():
		if child.name in [&"Tiles", &"PlayerStarts", &"EnemyStarts"]:
			continue
		var n3 := child as Node3D
		if n3 == null:
			continue
		if _is_grid_prop(n3):
			_add_prop_record(out, n3, n3.transform)
			for kid in n3.get_children():
				var s3 := kid as Node3D
				if s3 != null:
					_add_prop_record(out, s3, n3.transform * s3.transform)
		else:
			_add_prop_record(out, n3, n3.transform)
	return out

static func _add_prop_record(out: Array[Dictionary], node: Node3D, xform: Transform3D) -> void:
	if node.scene_file_path.is_empty():
		return
	var packed := load(node.scene_file_path) as PackedScene
	if packed != null:
		out.append({"scene": packed, "xform": xform})

## Duck-typed on purpose: the battle never depends on the editor's global class cache.
static func _is_grid_prop(n: Node) -> bool:
	return n.has_method(&"prop_rules") and n.has_method(&"world_cells")

## GridProp nodes under the map root -> plain-data grid rules, numbered in scene order.
static func _collect_grid_props(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child in root.get_children():
		if not _is_grid_prop(child):
			continue
		var rec: Dictionary = child.call(&"prop_rules")
		rec["id"] = out.size()
		out.append(rec)
	return out

## Marker3D children -> cells. Markers sit on integer x / z because tiles do.
static func _marker_cells(group: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for child in group.get_children():
		var m := child as Marker3D
		if m != null:
			out.append(Vector2i(roundi(m.position.x), roundi(m.position.z)))
	return out

static func _rows(width: int, height: int, heights: Dictionary, walls: Dictionary, r: MapResult) -> Array[String]:
	var p: Dictionary = {}
	for c in r.player_cells:
		p[c] = true
	var e: Dictionary = {}
	for c in r.enemy_cells:
		e[c] = true
	var rows: Array[String] = []
	for y in height:
		var line := ""
		for x in width:
			var cell := Vector2i(x, y)
			if walls.has(cell):
				line += "#"
			elif not heights.has(cell):
				line += "."
			elif p.has(cell):
				line += "P"
			elif e.has(cell):
				line += "E"
			else:
				line += str(int(heights[cell]))
		rows.append(line)
	return rows
