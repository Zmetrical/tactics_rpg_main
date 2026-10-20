@tool
class_name MapPreview
extends Node3D
## Editor-only live overlay for a map scene. Two colors only:
##
##   blue   unoccupied: a walkable tile with nothing on it
##   red    occupied: a player start, an enemy start, a blocking GridProp or a wall
##
## Player / enemy starts are told apart by their label (P1, E1...). A start marker that
## MapLoader would reject (on a hole, a wall, a blocking prop, or sharing a cell) is labeled
## with "!" and listed in the node's configuration warnings.
##
## Usage: add this node as a direct child of the map scene root (next to Tiles, PlayerStarts,
## EnemyStarts). Paint tiles, move markers, move / rotate GridProps: the overlay updates by itself.
## It draws only inside the editor. MapLoader ignores it (no scene file, not a GridProp), and the
## overlay meshes are internal children that are never saved into the map scene.
##
## Mirrors scripts/battle/map_loader.gd; keep the two in step if the map format changes.

const STEP := 0.5        # Stage3D.STEP: world units per height level
const WALL_LEVEL := 2    # Stage3D.WALL_LEVEL
const WALL_ITEM := 4     # map_loader.WALL_ITEM
const LIFT := 0.03       # overlay sits this far above the tile top
const HALF := 0.45       # quad half-size; the gap shows the cell grid

const C_FREE := Color(0.2, 0.55, 1.0, 0.4)
const C_OCCUPIED := Color(1.0, 0.2, 0.2, 0.55)

enum State { FREE, PLAYER, ENEMY, PROP, WALL, HOLE, BAD }

@export var show_free_tiles := true:
	set(v):
		show_free_tiles = v
		_last_hash = 0
@export var show_labels := true:
	set(v):
		show_labels = v
		_last_hash = 0

## Read-only counts, refreshed live. Not saved into the scene.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) var summary := ""

var _mesh_node: MeshInstance3D
var _labels: Array[Label3D] = []
var _last_hash := 0
var _accum := 0.0
var _problems := PackedStringArray()

func _ready() -> void:
	set_process(Engine.is_editor_hint())
	_last_hash = 0

func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.15:
		return
	_accum = 0.0
	_refresh()

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	var p := get_parent()
	if p == null or p.get_node_or_null("Tiles") == null:
		w.append("Add MapPreview as a child of the map root (it needs the sibling nodes Tiles, PlayerStarts, EnemyStarts).")
	w.append_array(_problems)
	return w

# --- Gather ------------------------------------------------------------------

func _refresh() -> void:
	var root := get_parent()
	if root == null:
		return
	var tiles := root.get_node_or_null("Tiles") as GridMap
	if tiles == null:
		return

	# Tiles -> level per cell (-1 = wall marker handled separately).
	var levels: Dictionary = {}  # Vector2i -> int level
	var walls: Dictionary = {}   # Vector2i -> true
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c: Vector3i in tiles.get_used_cells():
		if c.y != 0:
			continue
		var cell := Vector2i(c.x, c.z)
		var item := tiles.get_cell_item(c)
		if item == WALL_ITEM:
			walls[cell] = true
		elif item >= 0 and item < WALL_ITEM:
			levels[cell] = item
		else:
			continue
		lo = lo.min(cell)
		hi = hi.max(cell)

	# Blocking props -> cell -> prop name.
	var prop_cells: Dictionary = {}
	for child in root.get_children():
		if child.has_method(&"prop_rules") and child.has_method(&"world_cells"):
			var rec: Dictionary = child.call(&"prop_rules")
			if not rec.get("blocks_movement", false):
				continue
			for pc: Vector2i in rec["cells"]:
				prop_cells[pc] = String(rec["name"])

	var players := _marker_cells(root.get_node_or_null("PlayerStarts"))
	var enemies := _marker_cells(root.get_node_or_null("EnemyStarts"))

	# Classify.
	var state: Dictionary = {}   # Vector2i -> State
	var labels: Dictionary = {}  # Vector2i -> String
	var problems := PackedStringArray()
	var counts := {"free": 0, "player": 0, "enemy": 0, "prop": 0, "wall": 0, "hole": 0}

	var have_bounds := lo.x <= hi.x
	if have_bounds:
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				var cell := Vector2i(x, z)
				if walls.has(cell):
					state[cell] = State.WALL
					counts["wall"] += 1
				elif not levels.has(cell):
					state[cell] = State.HOLE
					counts["hole"] += 1
				elif prop_cells.has(cell):
					state[cell] = State.PROP
					counts["prop"] += 1
				else:
					state[cell] = State.FREE
					counts["free"] += 1

	var taken: Dictionary = {}
	for group: Array in [[players, State.PLAYER, "P"], [enemies, State.ENEMY, "E"]]:
		var list: Array = group[0]
		var kind: int = group[1]
		var prefix: String = group[2]
		for i in list.size():
			var m: Dictionary = list[i]
			var cell: Vector2i = m["cell"]
			var tag := "%s%d" % [prefix, i + 1]
			var why := ""
			if not levels.has(cell):
				why = "on a wall" if walls.has(cell) else "on a hole / outside the map"
			elif prop_cells.has(cell):
				why = "inside prop '%s'" % prop_cells[cell]
			elif taken.has(cell):
				why = "same cell as %s" % taken[cell]
			if why != "":
				problems.append("%s (%s) at %s: %s" % [m["name"], tag, str(cell), why])
				state[cell] = State.BAD
				labels[cell] = "%s !" % tag
			else:
				# Replace the FREE count with the start count.
				if state.get(cell, State.FREE) == State.FREE:
					counts["free"] -= 1
				state[cell] = kind
				labels[cell] = tag
				counts["player" if kind == State.PLAYER else "enemy"] += 1
			taken[cell] = tag

	var sig := [state, labels, levels, show_free_tiles, show_labels].hash()
	if sig == _last_hash:
		return
	_last_hash = sig

	summary = "unoccupied %d | occupied %d (players %d, enemies %d, props %d, walls %d)" % [
		counts["free"], counts["player"] + counts["enemy"] + counts["prop"] + counts["wall"],
		counts["player"], counts["enemy"], counts["prop"], counts["wall"]]
	if _problems != problems:
		_problems = problems
		update_configuration_warnings()
	_draw(state, labels, levels)

func _marker_cells(group: Node) -> Array:
	var out: Array = []
	if group == null:
		return out
	for child in group.get_children():
		var m := child as Marker3D
		if m != null:
			out.append({"cell": Vector2i(roundi(m.position.x), roundi(m.position.z)), "name": String(m.name)})
	return out

# --- Draw --------------------------------------------------------------------

func _draw(state: Dictionary, labels: Dictionary, levels: Dictionary) -> void:
	if _mesh_node == null:
		_mesh_node = MeshInstance3D.new()
		_mesh_node.name = "_PreviewMesh"
		_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh_node.material_override = mat
		add_child(_mesh_node, false, Node.INTERNAL_MODE_FRONT)

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for cell: Vector2i in state.keys():
		var s: int = state[cell]
		if s == State.FREE and not show_free_tiles:
			continue
		if s == State.HOLE:
			continue
		var y := _top_y(s, cell, levels) + LIFT
		var col := _color(s)
		var x := float(cell.x)
		var z := float(cell.y)
		var a := Vector3(x - HALF, y, z - HALF)
		var b := Vector3(x + HALF, y, z - HALF)
		var c := Vector3(x + HALF, y, z + HALF)
		var d := Vector3(x - HALF, y, z + HALF)
		verts.append_array([a, b, c, a, c, d])
		for _i in 6:
			colors.append(col)

	if verts.is_empty():
		_mesh_node.mesh = null
	else:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_mesh_node.mesh = mesh

	for l in _labels:
		l.queue_free()
	_labels.clear()
	if not show_labels:
		return
	for cell: Vector2i in labels.keys():
		var s: int = state[cell]
		var l := Label3D.new()
		l.name = "_PreviewLabel"
		l.text = String(labels[cell])
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0009
		l.font_size = 28
		l.outline_size = 12
		l.modulate = Color.WHITE
		l.position = Vector3(cell.x, _top_y(s, cell, levels) + 0.35, cell.y)
		add_child(l, false, Node.INTERNAL_MODE_FRONT)
		_labels.append(l)

func _top_y(s: int, cell: Vector2i, levels: Dictionary) -> float:
	if s == State.WALL:
		return WALL_LEVEL * STEP
	if levels.has(cell):
		return int(levels[cell]) * STEP
	return 0.0  # hole / off-grid marker

func _color(s: int) -> Color:
	return C_FREE if s == State.FREE else C_OCCUPIED
