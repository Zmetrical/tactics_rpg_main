@tool
class_name GridProp
extends Node3D
## Authoring node: says which grid cells an imported model (FBX, etc.) occupies, and how.
##
## Usage (map scene, directly under the scene root, like any other prop):
##   1. Add a GridProp node. Its position is the prop's ORIGIN CELL: keep x / z on whole numbers.
##   2. Drop the FBX in as a child of the GridProp and move / scale it until it looks right.
##      (Or attach this script to the FBX instance itself; both work.)
##   3. Press "Auto-fit footprint", then add / remove cells by hand in `footprint`.
##      Coloured quads in the editor show the occupied cells.
##   4. Rotate the GridProp in 90 degree steps on Y; the footprint rotates with it.
##
## Offsets are in the prop's own space: x = columns, y = rows (grid y is world z). (0, 0) is the
## origin cell. A 2x1 table with its origin on the left cell is [(0, 0), (1, 0)].
##
## MapLoader reads this node through duck typing (world_cells() / prop_rules()), not through the
## class name, so the battle scene never depends on the editor's global class cache.

## What the prop does to the battle once it is placed.
enum Kind {
	SOLID,  ## Building, tree, wall: blocks walking AND projectiles (bolts, arcs, drawn paths).
	SEMI,   ## Table, crate, fence: blocks walking, projectiles fly over it.
	DECOR,  ## Grass, path stones, flags: purely visual. The footprint is ignored.
}

@export var kind: Kind = Kind.SOLID:
	set(v):
		kind = v
		_refresh_gizmo()

## Occupied cells, as offsets from the origin cell, before rotation.
@export var footprint: Array[Vector2i] = [Vector2i.ZERO]:
	set(v):
		footprint = v
		_refresh_gizmo()

## When false, spells and attacks cannot be aimed at these cells (a cliff face, a big building you
## do not want to be a fireball target). Spread spells that only need "a tile exists" still hit them
## if the blast reaches them from a neighbouring cell.
@export var targetable := true

@export_group("Auto-fit")
## A cell joins the footprint when the model covers at least this fraction of it.
@export_range(0.05, 1.0, 0.05) var fit_threshold := 0.3
@export_tool_button("Auto-fit footprint") var fit_action = auto_fit

const FIT_STEP := 0.1  # auto-fit sample spacing, in world units

func _ready() -> void:
	set_notify_transform(Engine.is_editor_hint())
	_refresh_gizmo()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		update_configuration_warnings()

# --- What the battle reads ---------------------------------------------------

func blocks_movement() -> bool:
	return kind != Kind.DECOR

func blocks_projectiles() -> bool:
	return kind == Kind.SOLID

## Every grid cell the prop covers: origin cell + footprint rotated by the node's yaw.
## Works while the node is outside the scene tree (MapLoader instantiates map scenes headless).
func world_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin := Vector2i(roundi(position.x), roundi(position.z))
	var basis := transform.basis.orthonormalized()
	for off: Vector2i in footprint:
		var v := basis * Vector3(off.x, 0.0, off.y)
		var c := origin + Vector2i(roundi(v.x), roundi(v.z))
		if not out.has(c):
			out.append(c)
	return out

## One plain-data record for MapLoader / Grid. Nothing in it points back at the node.
func prop_rules() -> Dictionary:
	return {
		"name": String(name),
		"cells": world_cells() if kind != Kind.DECOR else ([] as Array[Vector2i]),
		"blocks_movement": blocks_movement(),
		"blocks_projectiles": blocks_projectiles(),
		"targetable": targetable,
	}

# --- Auto-fit ------------------------------------------------------------------

## Fills `footprint` from the model's actual triangles, not its bounding box, so stray helper
## geometry and thin guy-ropes do not inflate it. The triangles are flattened onto the ground plane
## and sampled every FIT_STEP units; a cell joins the footprint when the model covers at least
## `fit_threshold` of it. Vertical walls count too (their edges are sampled).
func auto_fit() -> void:
	var meshes := _mesh_instances(self)
	if meshes.is_empty():
		push_warning("GridProp '%s': no MeshInstance3D found to fit" % name)
		return
	var samples: Dictionary = {}  # Vector2i sample index -> true (deduped: overlapping faces count once)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for mi: MeshInstance3D in meshes:
		var t := _relative_transform(mi)
		var faces := mi.mesh.get_faces()
		var i := 0
		while i + 2 < faces.size():
			var a3 := t * faces[i]
			var b3 := t * faces[i + 1]
			var c3 := t * faces[i + 2]
			i += 3
			var a := Vector2(a3.x, a3.z)
			var b := Vector2(b3.x, b3.z)
			var c := Vector2(c3.x, c3.z)
			for v: Vector2 in [a, b, c]:
				lo = lo.min(v)
				hi = hi.max(v)
			_sample_edge(samples, a, b)
			_sample_edge(samples, b, c)
			_sample_edge(samples, c, a)
			_sample_triangle(samples, a, b, c)
	if samples.is_empty():
		push_warning("GridProp '%s': the meshes have no faces to fit" % name)
		return
	var per_cell := roundi(1.0 / FIT_STEP)
	var counts: Dictionary = {}  # Vector2i cell -> sample count
	for k: Vector2i in samples.keys():
		var cell := Vector2i(roundi((k.x + 0.5) * FIT_STEP), roundi((k.y + 0.5) * FIT_STEP))
		counts[cell] = int(counts.get(cell, 0)) + 1
	var out: Array[Vector2i] = []
	for cell: Vector2i in counts.keys():
		if float(counts[cell]) / float(per_cell * per_cell) >= fit_threshold:
			out.append(cell)
	out.sort_custom(func(l: Vector2i, r: Vector2i) -> bool: return l.y < r.y or (l.y == r.y and l.x < r.x))
	if out.is_empty():
		out.append(Vector2i.ZERO)
	footprint = out
	print("GridProp '%s': fitted %d cell(s); model spans %.2f x %.2f units" % [name, out.size(), hi.x - lo.x, hi.y - lo.y])
	if hi.x - lo.x > 12.0 or hi.y - lo.y > 12.0:
		push_warning("GridProp '%s': the model is over 12 cells wide. Check the FBX import scale." % name)
	if Engine.is_editor_hint():
		var ei: Object = Engine.get_singleton(&"EditorInterface")
		if ei != null:
			ei.call(&"mark_scene_as_unsaved")

func _mark_sample(samples: Dictionary, p: Vector2) -> void:
	samples[Vector2i(floori(p.x / FIT_STEP), floori(p.y / FIT_STEP))] = true

func _sample_edge(samples: Dictionary, a: Vector2, b: Vector2) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) / (FIT_STEP * 0.5)))
	for s in steps + 1:
		_mark_sample(samples, a.lerp(b, float(s) / float(steps)))

func _sample_triangle(samples: Dictionary, a: Vector2, b: Vector2, c: Vector2) -> void:
	var area := (b - a).cross(c - a)
	if absf(area) < 0.0001:
		return  # edge-on (a vertical wall): its edges were already sampled
	var lo := a.min(b).min(c)
	var hi := a.max(b).max(c)
	var x0 := floori(lo.x / FIT_STEP)
	var x1 := floori(hi.x / FIT_STEP)
	var y0 := floori(lo.y / FIT_STEP)
	var y1 := floori(hi.y / FIT_STEP)
	for sx in range(x0, x1 + 1):
		for sy in range(y0, y1 + 1):
			var p := Vector2((sx + 0.5) * FIT_STEP, (sy + 0.5) * FIT_STEP)
			var w0 := (b - a).cross(p - a)
			var w1 := (c - b).cross(p - b)
			var w2 := (a - c).cross(p - c)
			if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) or (w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0):
				samples[Vector2i(sx, sy)] = true

func _mesh_instances(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and not String(n.name).begins_with("_Footprint"):
		out.append(n)
	for child in n.get_children():
		out.append_array(_mesh_instances(child))
	return out

## Transform of `n` expressed in this node's local space.
func _relative_transform(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

# --- Editor feedback -----------------------------------------------------------

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if absf(position.x - roundf(position.x)) > 0.01 or absf(position.z - roundf(position.z)) > 0.01:
		w.append("Position x / z should be whole numbers: it is the origin cell. Move the model child instead.")
	var yaw := fposmod(rotation_degrees.y, 90.0)
	if yaw > 0.5 and yaw < 89.5:
		w.append("Rotate in 90 degree steps on Y, or the footprint will not line up with the grid.")
	if absf(rotation_degrees.x) > 0.5 or absf(rotation_degrees.z) > 0.5:
		w.append("Only a Y rotation is used for the footprint.")
	if kind != Kind.DECOR and footprint.is_empty():
		w.append("Footprint is empty: this prop blocks nothing.")
	if scene_file_path.is_empty() and _mesh_instances(self).is_empty():
		w.append("Add the model (FBX) as a child so there is something to see and to fit.")
	return w

## The footprint is drawn by the MapPreview node now; this only keeps the warnings current.
func _refresh_gizmo() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		update_configuration_warnings()
