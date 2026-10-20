extends RefCounted
## Grid layout of a RunMap for the overworld: rooms on whole cells, 1-cell-wide corridors with right-angle
## turns. Pure logic, no nodes. The same (RunMap, seed) always gives the same OverworldLayout; the RunMap
## is read-only here. Cells are Vector2i(x, z): x = layer axis, z = column axis. A cell's centre in world
## units is Vector2(x, z) (block centres lie on whole numbers).

const RunMap = preload("res://scripts/run/run_map.gd")
const RunTuning = preload("res://scripts/run/run_tuning.gd")

## Id of the start pseudo-room (same as MapLayout.START_ID).
const START_ID := -1

## Index = direction; d ^ 1 is the opposite.
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Door candidates kept per room end (best first); pairs are tried by combined rank.
const _DOOR_TRIES := 8
## Reachable door pairs routed per edge; the cheapest path wins. Stops early on a path within _GOOD_SLACK of
## the straight Manhattan distance between its two exit cells.
const _PAIR_TRIES := 6
const _GOOD_SLACK := 3.0

class OverworldLayout extends RefCounted:
	## node_id -> Vector2: centre of the room's footprint (x = layer axis, y = column axis). Includes the
	## start pseudo-room, id -1. Half-way between cells for rooms with an even side.
	var node_pos := {}
	## node_id -> Rect2i: the room's footprint in whole cells.
	var rooms := {}
	## [{from_id: int, to_id: int, cells: Array[Vector2i], points: PackedVector2Array}]. `cells` run from the
	## from room's door cell to the to room's door cell, each step one orthogonal cell. `points` is the same
	## path as Vector2(cell) (for the view and decor, which read points).
	var roads: Array = []
	## Vector2i(from_id, to_id) of every edge no corridor was found for (a push_warning was raised, nothing is drawn).
	var failed: Array[Vector2i] = []
	## Rect2 over every room cell centre and every corridor cell centre.
	var bounds := Rect2()
	## Layer and column spacing added to the RunTuning values for this layout (0 unless routing had to retry).
	var spacing_extra := 0.0

@warning_ignore("shadowed_global_identifier")
static func build(map: RunMap, seed: int) -> OverworldLayout:
	var out: OverworldLayout = null
	for attempt in RunTuning.SPACING_RETRIES + 1:
		out = _build_once(map, seed, attempt * RunTuning.SPACING_RETRY_STEP)
		if out.failed.is_empty():
			break
		for e in out.failed:
			push_warning("OverworldLayout: no corridor for edge %d -> %d (spacing +%s)%s" % [e.x, e.y,
					str(out.spacing_extra), "; raising layer and column spacing" if attempt < RunTuning.SPACING_RETRIES else "; giving up, edge not drawn"])
	if "--print-road" in OS.get_cmdline_user_args() and not out.roads.is_empty():
		print(road_debug(out.roads[0]))
	return out

## One line: the road's ids and its straight runs as (x,z)->(x,z), e.g. "road 2 -> 5, 14 cells, 3 runs: ...".
static func road_debug(road: Dictionary) -> String:
	var cells: Array[Vector2i] = road["cells"]
	var runs: Array[String] = []
	var run_start := 0
	var i := 1
	while i <= cells.size():
		var turn := i == cells.size() or (i >= 2 and cells[i] - cells[i - 1] != cells[i - 1] - cells[i - 2])
		if turn:
			if i - 1 > run_start:
				runs.append("(%d,%d)->(%d,%d)" % [cells[run_start].x, cells[run_start].y, cells[i - 1].x, cells[i - 1].y])
			run_start = i - 1
		i += 1
	return "road %d -> %d, %d cells, %d runs: %s" % [road["from_id"], road["to_id"], cells.size(), runs.size(), " ".join(runs)]

# --- one layout attempt ------------------------------------------------------------------

@warning_ignore("integer_division")
static func _build_once(map: RunMap, seed: int, extra: float) -> OverworldLayout:
	var out := OverworldLayout.new()
	out.spacing_extra = extra
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ RunTuning.OVERWORLD_SEED_SALT

	# Rooms: layer -> X, column -> Z, plus whole-cell jitter; centre cell snapped, footprint around it.
	var layer_sp := RunTuning.LAYER_SPACING + extra
	var col_sp := RunTuning.COL_SPACING + extra
	var jit: int = RunTuning.JITTER
	var placed: Array[Rect2i] = []
	for n in map.nodes:
		var size: Vector2i = RunTuning.ROOM_SIZES[n.type]
		var cx := roundi(n.layer * layer_sp) + rng.randi_range(-jit, jit)
		var cz := roundi(n.col * col_sp) + rng.randi_range(-jit, jit)
		var rect := Rect2i(Vector2i(cx - size.x / 2, cz - size.y / 2), size)
		var guard := 0
		while guard < 500 and _hits(rect, placed):
			rect.position.y += 1
			guard += 1
		placed.append(rect)
		out.rooms[n.id] = rect
	_add_start_room(out, map)
	for id in out.rooms:
		var r: Rect2i = out.rooms[id]
		out.node_pos[id] = Vector2(r.position) + Vector2(r.size - Vector2i.ONE) * 0.5

	# Edges: one road per RunMap edge plus start -> each layer-0 room. Shortest Manhattan distance first,
	# ties by (from_id, to_id), so one RunMap always routes in the same order.
	var edges: Array = []   # [from_id, to_id, distance]
	for n in map.nodes:
		for nid in n.next_ids:
			edges.append([n.id, nid, _edge_len(out, n.id, nid)])
	for id in map.layers[0]:
		edges.append([START_ID, id, _edge_len(out, START_ID, id)])
	edges.sort_custom(func(a: Array, b: Array) -> bool:
		if a[2] != b[2]:
			return a[2] < b[2]
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])

	var grid := _Grid.new(out.rooms)
	var doors := {}   # room id -> Array[Vector3i(x, z, side)] of doors already used
	for e in edges:
		var road := _route_edge(out, grid, doors, e[0], e[1])
		if road.is_empty():
			out.failed.append(Vector2i(e[0], e[1]))
		else:
			out.roads.append(road)

	# Bounds over room cell centres and corridor cells.
	var first := true
	var b := Rect2()
	for id in out.rooms:
		var r: Rect2i = out.rooms[id]
		var rr := Rect2(Vector2(r.position), Vector2(r.size - Vector2i.ONE))
		b = rr if first else b.merge(rr)
		first = false
	for road in out.roads:
		for p: Vector2 in road["points"]:
			b = b.expand(p)
	out.bounds = b
	return out

## The starting platform: START_GAP empty cells before the layer-0 rooms on X, centred on their average Z.
@warning_ignore("integer_division")
static func _add_start_room(out: OverworldLayout, map: RunMap) -> void:
	var ids: Array[int] = map.layers[0]
	var min_x := 1 << 30
	var sum_cz := 0.0
	for id in ids:
		var r: Rect2i = out.rooms[id]
		min_x = mini(min_x, r.position.x)
		sum_cz += r.position.y + r.size.y * 0.5
	var size: Vector2i = RunTuning.START_SIZE
	out.rooms[START_ID] = Rect2i(Vector2i(min_x - RunTuning.START_GAP - size.x,
			roundi(sum_cz / ids.size() - size.y * 0.5)), size)

static func _hits(r: Rect2i, placed: Array[Rect2i]) -> bool:
	var grown := r.grow(RunTuning.ROOM_MARGIN)
	for p in placed:
		if grown.intersects(p):
			return true
	return false

@warning_ignore("integer_division")
static func _center_cell(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2

static func _edge_len(out: OverworldLayout, from_id: int, to_id: int) -> int:
	var d := _center_cell(out.rooms[from_id]) - _center_cell(out.rooms[to_id])
	return absi(d.x) + absi(d.y)

# --- corridors ---------------------------------------------------------------------------

## Routes one edge door to door. {} = no route. Reachable door pairs are tried by combined rank (closest doors
## first), up to _PAIR_TRIES of them, and the cheapest path is kept, so a taken door never forces a wrap-around
## when another door gives a direct road. A pair whose exit cells are not connected is skipped without A*. The
## search box is the two rooms plus CORRIDOR_SEARCH_PAD; when it finds nothing the whole grid is searched.
static func _route_edge(out: OverworldLayout, grid: _Grid, doors: Dictionary, from_id: int, to_id: int) -> Dictionary:
	var ra: Rect2i = out.rooms[from_id]
	var rb: Rect2i = out.rooms[to_id]
	var cand_a := _door_candidates(grid, ra, rb, doors.get(from_id, []), from_id)
	var cand_b := _door_candidates(grid, rb, ra, doors.get(to_id, []), to_id)
	var local := ra.merge(rb).grow(RunTuning.CORRIDOR_SEARCH_PAD).intersection(grid.box)
	var boxes: Array[Rect2i] = [local]
	if local != grid.box:
		boxes.append(grid.box)
	# Pass 0: corridors never share a cell. Pass 1 (only when pass 0 finds nothing, e.g. an earlier road wrapped
	# round a room and sealed it in): a cell of another corridor may be crossed at +CORRIDOR_CROSS_COST.
	for pass_i in 2:
		grid.allow_cross = pass_i == 1
		var road := _route_in_boxes(out, grid, doors, from_id, to_id, boxes, cand_a, cand_b)
		if not road.is_empty():
			if pass_i == 1:
				push_warning("OverworldLayout: edge %d -> %d crosses another corridor (no free route)" % [from_id, to_id])
			grid.allow_cross = false
			return road
	grid.allow_cross = false
	return {}

static func _route_in_boxes(out: OverworldLayout, grid: _Grid, doors: Dictionary, from_id: int, to_id: int,
		boxes: Array[Rect2i], cand_a: Array[Dictionary], cand_b: Array[Dictionary]) -> Dictionary:
	for box in boxes:
		var comp := grid.components(box)
		var best_cost := INF
		var best_path: Array[Vector2i] = []
		var best_da := {}
		var best_db := {}
		var tried := 0
		var done := false
		for s in range(0, 2 * _DOOR_TRIES - 1):
			if done:
				break
			for i in _DOOR_TRIES:
				var j := s - i
				if j < 0 or j >= _DOOR_TRIES or i >= cand_a.size() or j >= cand_b.size():
					continue
				var da: Dictionary = cand_a[i]
				var db: Dictionary = cand_b[j]
				var out_a: Vector2i = da["exit"] + DIRS[da["side"]]
				var out_b: Vector2i = db["exit"] + DIRS[db["side"]]
				if not box.has_point(out_a) or not box.has_point(out_b):
					continue
				if comp[grid.box_index(box, out_a)] != comp[grid.box_index(box, out_b)]:
					continue
				var path := _astar(grid, box, da["exit"], da["side"], db["exit"], from_id, to_id)
				if path.is_empty():
					continue
				tried += 1
				if grid.last_cost < best_cost:
					best_cost = grid.last_cost
					best_path = path
					best_da = da
					best_db = db
				var ideal := absi(da["exit"].x - db["exit"].x) + absi(da["exit"].y - db["exit"].y)
				if best_cost <= ideal + _GOOD_SLACK or tried >= _PAIR_TRIES:
					done = true
					break
		if best_path.is_empty():
			continue
		var cells: Array[Vector2i] = [best_da["cell"]]
		cells.append_array(best_path)
		cells.append(best_db["cell"])
		grid.add_corridor(best_path)
		var ta: Array = doors.get(from_id, [])
		ta.append(Vector3i(best_da["cell"].x, best_da["cell"].y, best_da["side"]))
		doors[from_id] = ta
		var tb: Array = doors.get(to_id, [])
		tb.append(Vector3i(best_db["cell"].x, best_db["cell"].y, best_db["side"]))
		doors[to_id] = tb
		var pts := PackedVector2Array()
		for c in cells:
			pts.append(Vector2(c))
		return {"from_id": from_id, "to_id": to_id, "cells": cells, "points": pts}
	return {}

## Footprint edge cells of `room` that can be a door toward `other`: [{cell, side, exit}], closest first.
## The exit is the cell just outside the footprint in direction DIRS[side]; the road runs from exit to exit.
## Doors are (cell, side): a corner cell of a small room can serve two sides, but a (cell, side) is used once, and
## a cell that is not a door yet always ranks before one that is. The exit must be a free cell of the room's own border and
## the cell beyond it must be open, so every road runs straight out of its door for two cells before it may turn.
static func _door_candidates(grid: _Grid, room: Rect2i, other: Rect2i, taken: Array, room_id: int) -> Array[Dictionary]:
	var o := room.position
	var e := room.position + room.size - Vector2i.ONE
	var target := _center_cell(other)
	var list: Array[Dictionary] = []
	for side in 4:
		var cells: Array[Vector2i] = []
		match side:
			0:
				for z in range(o.y, e.y + 1):
					cells.append(Vector2i(e.x, z))
			1:
				for z in range(o.y, e.y + 1):
					cells.append(Vector2i(o.x, z))
			2:
				for x in range(o.x, e.x + 1):
					cells.append(Vector2i(x, e.y))
			_:
				for x in range(o.x, e.x + 1):
					cells.append(Vector2i(x, o.y))
		for c in cells:
			if taken.has(Vector3i(c.x, c.y, side)):
				continue
			var ex := c + DIRS[side]
			if not grid.exit_ok(ex, room_id) or not grid.open(ex + DIRS[side]):
				continue
			var d := absi(ex.x - target.x) + absi(ex.y - target.y)
			var reused := 0
			for k: Vector3i in taken:
				if k.x == c.x and k.y == c.y:
					reused = 1
			list.append({"cell": c, "side": side, "exit": ex, "dist": d, "reused": reused})
	# Stable sort: Array.sort_custom is not stable, so break ties by the insertion index.
	for i in list.size():
		list[i]["i"] = i
	list.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		if p["reused"] != q["reused"]:
			return p["reused"] < q["reused"]
		if p["dist"] != q["dist"]:
			return p["dist"] < q["dist"]
		return p["i"] < q["i"])
	return list.slice(0, _DOOR_TRIES)

## 2D A* over (cell, heading), 4-connected, no reversing. Step 1, a turn +CORRIDOR_TURN_COST, a cell next to
## another corridor +CORRIDOR_NEAR_COST, a cell next to another room's border (not one of its two ends)
## +CORRIDOR_ROOM_NEAR_COST, a cell of another corridor (only while the grid allows crossing) +CORRIDOR_CROSS_COST.
## Never enters a footprint, a room's border (except the start and goal exit
## cells) or a corridor cell.
## Returns the cells from `start` to `goal` (both included), or [] when there is no route.
@warning_ignore("integer_division")
static func _astar(grid: _Grid, box: Rect2i, start: Vector2i, start_dir: int, goal: Vector2i, a_id: int, b_id: int) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if not box.has_point(start) or not box.has_point(goal):
		return none
	var w := box.size.x
	var turn := RunTuning.CORRIDOR_TURN_COST
	var near_cost := RunTuning.CORRIDOR_NEAR_COST
	var hug_cost := RunTuning.CORRIDOR_ROOM_NEAR_COST
	var cross_cost := RunTuning.CORRIDOR_CROSS_COST
	var states := box.size.x * box.size.y * 4
	var g := PackedFloat32Array()
	g.resize(states)
	g.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(states)
	var closed := PackedByteArray()
	closed.resize(states)
	var start_key := (((start.y - box.position.y) * w + (start.x - box.position.x)) << 2) | start_dir
	g[start_key] = 0.0
	parent[start_key] = -1
	var heap := _Heap.new()
	heap.push(float(absi(start.x - goal.x) + absi(start.y - goal.y)), start_key)
	var goal_key := -1
	while not heap.is_empty():
		var key := heap.pop()
		if closed[key] == 1:
			continue
		closed[key] = 1
		var pd := key & 3
		var idx := key >> 2
		var cx := idx % w + box.position.x
		var cz := idx / w + box.position.y
		if cx == goal.x and cz == goal.y:
			goal_key = key
			break
		var cur_g: float = g[key]
		for d in 4:
			if d == (pd ^ 1):
				continue
			var nc := Vector2i(cx + DIRS[d].x, cz + DIRS[d].y)
			if not box.has_point(nc) or not (nc == goal or grid.open(nc)):
				continue
			var cost := 1.0
			if d != pd:
				cost += turn
			if grid.is_near(nc):
				cost += near_cost
			if grid.is_used(nc):
				cost += cross_cost
			var hug := grid.hugged_room(nc)
			if hug != 0 and hug != a_id + 2 and hug != b_id + 2:
				cost += hug_cost
			var nkey := (((nc.y - box.position.y) * w + (nc.x - box.position.x)) << 2) | d
			var ng := cur_g + cost
			if closed[nkey] == 1 or g[nkey] <= ng:
				continue
			g[nkey] = ng
			parent[nkey] = key
			heap.push(ng + float(absi(nc.x - goal.x) + absi(nc.y - goal.y)), nkey)
	if goal_key < 0:
		return none
	grid.last_cost = g[goal_key]
	var cells: Array[Vector2i] = []
	var k: int = goal_key
	while k != -1:
		var i := k >> 2
		cells.append(Vector2i(i % w + box.position.x, i / w + box.position.y))
		k = parent[k]
	cells.reverse()
	return cells

## Blocked and costed cells for all edges of one layout: footprints, room borders, finished corridors.
@warning_ignore("integer_division")
class _Grid extends RefCounted:
	var box := Rect2i()
	## Cost of the path the last successful _astar returned.
	var last_cost := 0.0
	## True during the crossing pass: open() then accepts cells of finished corridors.
	var allow_cross := false
	var _w := 0
	var _fp := PackedByteArray()      # 1 = inside a footprint
	var _owner := PackedInt32Array()  # room id + 2 of the border (1 cell around a footprint) the cell is in, 0 = none
	var _used := PackedByteArray()    # 1 = cell of a finished corridor
	var _near := PackedByteArray()    # 1 = 4-adjacent to a cell of a finished corridor
	var _hug := PackedInt32Array()    # room id + 2 whose border this open cell touches (4-adjacent), 0 = none

	func _init(rooms: Dictionary) -> void:
		var first := true
		for id in rooms:
			var r: Rect2i = rooms[id]
			box = r if first else box.merge(r)
			first = false
		# Room: ring + search pad on every side so a road can go round the outside.
		box = box.grow(RunTuning.CORRIDOR_SEARCH_PAD + RunTuning.ROAD_ROOM_CLEARANCE)
		_w = box.size.x
		var n := box.size.x * box.size.y
		_fp.resize(n)
		_owner.resize(n)
		_used.resize(n)
		_near.resize(n)
		_hug.resize(n)
		for id in rooms:
			var r: Rect2i = rooms[id]
			var ring := r.grow(RunTuning.ROAD_ROOM_CLEARANCE)
			for x in range(ring.position.x, ring.end.x):
				for z in range(ring.position.y, ring.end.y):
					_owner[_i(Vector2i(x, z))] = id + 2
			for x in range(r.position.x, r.end.x):
				for z in range(r.position.y, r.end.y):
					_fp[_i(Vector2i(x, z))] = 1
		# Open cells right outside a border: the outward cells of the doors, and the lane roads would hug.
		for id in rooms:
			var ring: Rect2i = (rooms[id] as Rect2i).grow(RunTuning.ROAD_ROOM_CLEARANCE)
			for x in range(ring.position.x - 1, ring.end.x + 1):
				for z in range(ring.position.y - 1, ring.end.y + 1):
					var c := Vector2i(x, z)
					if box.has_point(c) and not ring.has_point(c) and _hug[_i(c)] == 0:
						_hug[_i(c)] = id + 2

	func _i(c: Vector2i) -> int:
		return (c.y - box.position.y) * _w + (c.x - box.position.x)

	## Free for any road: inside the grid, not in a footprint, not in a room's border, and not a corridor cell
	## unless `allow_cross` (no merging).
	func open(c: Vector2i) -> bool:
		if not box.has_point(c):
			return false
		var i := _i(c)
		return _fp[i] == 0 and (_used[i] == 0 or allow_cross) and _owner[i] == 0

	func is_used(c: Vector2i) -> bool:
		return _used[_i(c)] == 1

	## A cell of room `room_id`'s own border that no corridor uses yet: where a road may leave that room.
	func exit_ok(c: Vector2i, room_id: int) -> bool:
		if not box.has_point(c):
			return false
		var i := _i(c)
		return _fp[i] == 0 and _used[i] == 0 and _owner[i] == room_id + 2

	## Index of cell `c` in an array laid out over `b` (row by row along x).
	func box_index(b: Rect2i, c: Vector2i) -> int:
		return (c.y - b.position.y) * b.size.x + (c.x - b.position.x)

	## Label of the 4-connected region of open cells each cell of `b` is in (0 = not open).
	func components(b: Rect2i) -> PackedInt32Array:
		var w := b.size.x
		var comp := PackedInt32Array()
		comp.resize(w * b.size.y)
		var label := 0
		for i in comp.size():
			if comp[i] != 0:
				continue
			var c0 := Vector2i(i % w + b.position.x, i / w + b.position.y)
			if not open(c0):
				continue
			label += 1
			comp[i] = label
			var stack: Array[int] = [i]
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				var cc := Vector2i(cur % w + b.position.x, cur / w + b.position.y)
				for d in 4:
					var nc: Vector2i = cc + DIRS[d]
					if not b.has_point(nc):
						continue
					var ni := box_index(b, nc)
					if comp[ni] == 0 and open(nc):
						comp[ni] = label
						stack.append(ni)
		return comp

	## Room id + 2 of a room whose border this cell touches, 0 = none.
	func hugged_room(c: Vector2i) -> int:
		return _hug[_i(c)]

	func is_near(c: Vector2i) -> bool:
		return _near[_i(c)] == 1

	func add_corridor(cells: Array[Vector2i]) -> void:
		for c in cells:
			_used[_i(c)] = 1
		for c in cells:
			for d in 4:
				var nc: Vector2i = c + DIRS[d]
				if box.has_point(nc):
					_near[_i(nc)] = 1

## Min-heap of int keys by (priority, insertion order): equal priorities pop in push order.
class _Heap extends RefCounted:
	var _f: Array[float] = []
	var _s: Array[int] = []
	var _k: Array[int] = []
	var _seq := 0

	func is_empty() -> bool:
		return _k.is_empty()

	func _less(i: int, j: int) -> bool:
		return _f[i] < _f[j] or (_f[i] == _f[j] and _s[i] < _s[j])

	func _swap(i: int, j: int) -> void:
		var f := _f[i]
		_f[i] = _f[j]
		_f[j] = f
		var s := _s[i]
		_s[i] = _s[j]
		_s[j] = s
		var k := _k[i]
		_k[i] = _k[j]
		_k[j] = k

	func push(f: float, key: int) -> void:
		_f.append(f)
		_s.append(_seq)
		_k.append(key)
		_seq += 1
		var i := _k.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if not _less(i, p):
				break
			_swap(i, p)
			i = p

	func pop() -> int:
		var top := _k[0]
		var n := _k.size() - 1
		_swap(0, n)
		_f.pop_back()
		_s.pop_back()
		_k.pop_back()
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < n and _less(l, m):
				m = l
			if r < n and _less(r, m):
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top
