extends RefCounted
## Spatial layout on top of a RunMap: rooms on a flat grid, 1-cell corridors. Pure logic, no
## randomness: the same RunMap always gives the same MapLayout. The RunMap is read-only here.
## Grid: x = layer axis, z = column axis. Cells are Vector2i(x, z).

const RunMap = preload("res://scripts/run/run_map.gd")
const RunTuning = preload("res://scripts/run/run_tuning.gd")

## Index = direction; d ^ 1 is the opposite.
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Room id of the starting platform. Not a RunMap node: it has no node, no edges, only corridors out.
const START_ID := -1

class Room extends RefCounted:
	var origin := Vector2i.ZERO
	var size := Vector2i.ZERO
	## "" = a RunMap node room, "start" = the starting platform.
	var kind := ""

	func rect() -> Rect2i:
		return Rect2i(origin, size)

	@warning_ignore("integer_division")
	func center_cell() -> Vector2i:
		return origin + size / 2

class MapLayout extends RefCounted:
	## node_id -> Room
	var rooms := {}
	## [{from_id, to_id, cells: Array[Vector2i]}]; cells run door to door, (x, z).
	var corridors: Array = []
	## [from_id, to_id] pairs no road was found for (a push_warning is raised, no road is drawn). Should stay empty.
	var failed: Array = []
	## Grid bounds (x, z) over rooms and corridors, end-exclusive.
	func bounds() -> Rect2i:
		var r := Rect2i()
		var first := true
		for id in rooms:
			var rr: Rect2i = (rooms[id] as Room).rect()
			r = rr if first else r.merge(rr)
			first = false
		for c in corridors:
			for cell in c["cells"]:
				var cr := Rect2i(cell.x, cell.y, 1, 1)
				r = cr if first else r.merge(cr)
				first = false
		return r

static func build(map: RunMap) -> MapLayout:
	var layout := _place(map)
	_add_start_room(layout, map)
	var occ := {}    # Vector2i(x, z) -> Array[Vector2i(from_id, to_id)], road cells of finished corridors (never doors)
	var doors := {}  # room id -> Array[Vector3i], door cells already taken
	# One list: every RunMap edge plus one road from the Start room to each layer-0 room.
	# Shortest Manhattan distance first; ties by (from_id, to_id), so one RunMap gives one layout.
	var edges: Array = []   # [from_id, to_id, distance]
	for node in map.nodes:
		for nid in node.next_ids:
			edges.append([node.id, nid, _edge_len(layout, node.id, nid)])
	for id in map.layers[0]:
		edges.append([START_ID, id, _edge_len(layout, START_ID, id)])
	edges.sort_custom(func(a: Array, b: Array) -> bool:
		if a[2] != b[2]:
			return a[2] < b[2]
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	for e in edges:
		_route_edge(layout, e[0], e[1], occ, doors)
	return layout

static func _edge_len(layout: MapLayout, from_id: int, to_id: int) -> int:
	var d := (layout.rooms[from_id] as Room).center_cell() - (layout.rooms[to_id] as Room).center_cell()
	return absi(d.x) + absi(d.y)

static func _route_edge(layout: MapLayout, from_id: int, to_id: int, occ: Dictionary, doors: Dictionary) -> void:
	var c := _corridor(layout, from_id, to_id, occ, doors)
	if c.is_empty():
		push_warning("MapLayout: no road for edge %d -> %d (not drawn)" % [from_id, to_id])
		layout.failed.append([from_id, to_id])
	else:
		layout.corridors.append(c)

# --- rooms -------------------------------------------------------------------------------

@warning_ignore("integer_division")
static func _place(map: RunMap) -> MapLayout:
	var out := MapLayout.new()
	var placed: Array[Rect2i] = []
	var jc := RunTuning.ROOM_JITTER_CELLS
	for n in map.nodes:
		var room := Room.new()
		room.size = RunTuning.ROOM_SIZES[n.type]
		# pos_jitter.x is the column axis, .y the layer axis (same as the old view).
		var off_x := clampi(roundi(n.pos_jitter.y * RunTuning.LAYER_STEP), -jc, jc)
		var off_z := clampi(roundi(n.pos_jitter.x * RunTuning.COL_STEP), -jc, jc)
		var cx: int = n.layer * RunTuning.LAYER_STEP + off_x
		var cz: int = n.col * RunTuning.COL_STEP + off_z
		room.origin = Vector2i(cx - room.size.x / 2, cz - room.size.y / 2)
		# Nudge +z, one cell at a time, until clear of every earlier room plus margin.
		var guard := 0
		while guard < 500 and _hits(Rect2i(room.origin, room.size), placed):
			room.origin.y += 1
			guard += 1
		placed.append(room.rect())
		out.rooms[n.id] = room
	return out

## The starting platform: START_GAP empty cells before the layer-0 rooms on X, centered on their
## average Z. Created before any road so every road keeps clear of it.
static func _add_start_room(layout: MapLayout, map: RunMap) -> void:
	var ids: Array[int] = map.layers[0]
	var min_x := 1 << 30
	var sum_cz := 0.0
	for id in ids:
		var r: Room = layout.rooms[id]
		min_x = mini(min_x, r.origin.x)
		sum_cz += r.origin.y + r.size.y * 0.5
	var room := Room.new()
	room.kind = "start"
	room.size = RunTuning.START_SIZE
	room.origin = Vector2i(min_x - RunTuning.START_GAP - room.size.x,
			roundi(sum_cz / ids.size() - room.size.y * 0.5))
	layout.rooms[START_ID] = room

static func _hits(r: Rect2i, placed: Array[Rect2i]) -> bool:
	var grown := r.grow(RunTuning.ROOM_MARGIN)
	for p in placed:
		if grown.intersects(p):
			return true
	return false

# --- corridors ---------------------------------------------------------------------------

## Side indices (DIRS) of `room` to try, nearest-facing first.
static func _side_order(room: Room, other: Room) -> Array[int]:
	var d := other.center_cell() - room.center_cell()
	var order: Array[int] = []
	var xs := 0 if d.x > 0 else 1
	var zs := 2 if d.y > 0 else 3
	if absi(d.x) >= absi(d.y):
		order = [xs, zs, zs ^ 1, xs ^ 1]
	else:
		order = [zs, xs, xs ^ 1, zs ^ 1]
	return order

const NO_DOOR := Vector2i(-99999, -99999)

## Door on `side` of `room`: the free footprint-edge cell nearest the other room's centre. `taken` holds
## Vector3i(x, z, side) of doors already used. Strict mode: never a cell used as a door on any side and never
## 4-adjacent to one (roads keep a gap). Relaxed mode: only the same cell on the same side is refused, so a
## corner cell of a small room can serve two sides. NO_DOOR when the side has none.
static func _pick_door(room: Room, other: Room, side: int, taken: Array, strict: bool) -> Vector2i:
	var o := room.origin
	var e := room.origin + room.size - Vector2i.ONE
	var cand: Array[Vector2i] = []
	match side:
		0:
			for z in range(o.y, e.y + 1):
				cand.append(Vector2i(e.x, z))
		1:
			for z in range(o.y, e.y + 1):
				cand.append(Vector2i(o.x, z))
		2:
			for x in range(o.x, e.x + 1):
				cand.append(Vector2i(x, e.y))
		_:
			for x in range(o.x, e.x + 1):
				cand.append(Vector2i(x, o.y))
	var t := other.center_cell()
	var best := NO_DOOR
	var best_d := 1 << 30
	for c in cand:
		if taken.has(Vector3i(c.x, c.y, side)):
			continue
		if strict:
			var close := false
			for k: Vector3i in taken:
				if absi(k.x - c.x) + absi(k.y - c.y) <= 1:
					close = true
			if close:
				continue
		var d := absi(c.x - t.x) + absi(c.y - t.y)
		if d < best_d:
			best_d = d
			best = c
	return best

## Routes one edge. Order: (1) corridor clearance 1, gapped doors then plain doors; fallback a: clearance 0
## (roads may touch, never share a cell); fallback b: a cell of another road may be crossed at
## +ROAD_CROSS_COST. Room clearance never relaxes. Fallbacks a and b push_warning. {} = no road.
static func _corridor(layout: MapLayout, from_id: int, to_id: int, occ: Dictionary, doors: Dictionary) -> Dictionary:
	var gap := RunTuning.ROAD_CORRIDOR_CLEARANCE
	for strict in [true, false]:
		var c := _corridor_try(layout, from_id, to_id, occ, doors, gap, false, strict)
		if not c.is_empty():
			return c
	if gap > 0:
		var ca := _corridor_try(layout, from_id, to_id, occ, doors, 0, false, false)
		if not ca.is_empty():
			push_warning("MapLayout: edge %d -> %d routed with fallback a (roads touch, corridor clearance 0)" % [from_id, to_id])
			return ca
	var cb := _corridor_try(layout, from_id, to_id, occ, doors, 0, true, false)
	if not cb.is_empty():
		push_warning("MapLayout: edge %d -> %d routed with fallback b (crosses another road, +%s)" % [from_id, to_id, str(RunTuning.ROAD_CROSS_COST)])
		return cb
	return {}

static func _corridor_try(layout: MapLayout, from_id: int, to_id: int, occ: Dictionary, doors: Dictionary,
		corr_clear: int, allow_cross: bool, strict: bool) -> Dictionary:
	var a: Room = layout.rooms[from_id]
	var b: Room = layout.rooms[to_id]
	var sa := _side_order(a, b)
	var sb := _side_order(b, a)
	# Side pairs, best first: (0,0), (0,1), (1,0), ... by combined preference rank.
	var pairs: Array[Vector2i] = []
	for s in 7:
		for i in 4:
			var j := s - i
			if j >= 0 and j < 4:
				pairs.append(Vector2i(i, j))
	var others: Array[Rect2i] = []
	for id in layout.rooms:
		if id != from_id and id != to_id:
			others.append((layout.rooms[id] as Room).rect())
	var taken_a: Array = doors.get(from_id, [])
	var taken_b: Array = doors.get(to_id, [])
	# One grid (blocked cells + connected components) per try, shared by all door pairs.
	var grid := _build_grid(a, b, Vector2i(from_id, to_id), others, occ, corr_clear, allow_cross, strict)
	for p in pairs:
		var da := sa[p.x]
		var db := sb[p.y]
		var door_a := _pick_door(a, b, da, taken_a, strict)
		var door_b := _pick_door(b, a, db, taken_b, strict)
		if door_a == NO_DOOR or door_b == NO_DOOR:
			continue
		var path := _route(grid, door_a + DIRS[da], da, door_b + DIRS[db])
		if path.is_empty():
			continue
		var cells: Array[Vector2i] = [door_a]
		for cell in path:
			var owners: Array = occ.get(cell, [])
			owners.append(Vector2i(from_id, to_id))
			occ[cell] = owners
			cells.append(cell)
		cells.append(door_b)
		taken_a.append(Vector3i(door_a.x, door_a.y, da))
		taken_b.append(Vector3i(door_b.x, door_b.y, db))
		doors[from_id] = taken_a
		doors[to_id] = taken_b
		return {"from_id": from_id, "to_id": to_id, "cells": cells}
	return {}

const F_ROOM := 1   # inside an endpoint footprint, or within ROAD_ROOM_CLEARANCE of another room
const F_USED := 2   # a cell of an earlier road
const F_NEAR := 4   # 4-adjacent to a cell of an earlier road that shares no endpoint room with this edge

static func _passable(f: int, corr_clear: int, allow_cross: bool) -> bool:
	if f & F_ROOM:
		return false
	if f & F_USED:
		return allow_cross
	if corr_clear > 0 and (f & F_NEAR):
		return false
	return true

## Search grid for one edge: {box, w, flags, comp}. Hard-blocked: both endpoint footprints (entered only
## through the door), every other room grown by ROAD_ROOM_CLEARANCE, every cell of an earlier road (unless
## `allow_cross`), and with `corr_clear` > 0 every cell next to an earlier road that shares no endpoint room
## with this edge (`ids` = from_id, to_id). `comp` labels 4-connected passable regions (0 = impassable), so a
## door pair with no route is rejected without running A*. `strict` = false widens the search box.
@warning_ignore("integer_division")
static func _build_grid(a: Room, b: Room, ids: Vector2i, others: Array[Rect2i], occ: Dictionary,
		corr_clear: int, allow_cross: bool, strict: bool) -> Dictionary:
	var pad := RunTuning.CORRIDOR_SEARCH_PAD + (0 if strict else 8)
	var box := a.rect().merge(b.rect()).grow(pad)
	var w := box.size.x
	var h := box.size.y
	var flags := PackedByteArray()
	flags.resize(w * h)
	var rects: Array[Rect2i] = [a.rect(), b.rect()]
	for r in others:
		rects.append(r.grow(RunTuning.ROAD_ROOM_CLEARANCE))
	for r in rects:
		var ov := r.intersection(box)
		for x in range(ov.position.x, ov.end.x):
			for z in range(ov.position.y, ov.end.y):
				flags[(z - box.position.y) * w + (x - box.position.x)] |= F_ROOM
	# Cells one step outside the box can still make a cell inside it "near".
	var wide := box.grow(1)
	for cell: Vector2i in occ:
		if not wide.has_point(cell):
			continue
		var foreign := false
		for o: Vector2i in occ[cell]:
			if o.x != ids.x and o.x != ids.y and o.y != ids.x and o.y != ids.y:
				foreign = true
				break
		if box.has_point(cell):
			flags[(cell.y - box.position.y) * w + (cell.x - box.position.x)] |= F_USED
		if foreign:
			for d in 4:
				var nc: Vector2i = cell + DIRS[d]
				if box.has_point(nc):
					flags[(nc.y - box.position.y) * w + (nc.x - box.position.x)] |= F_NEAR
	# Connected components of passable cells (iterative flood fill).
	var comp := PackedInt32Array()
	comp.resize(w * h)
	var label := 0
	for i in w * h:
		if comp[i] != 0 or not _passable(flags[i], corr_clear, allow_cross):
			continue
		label += 1
		comp[i] = label
		var stack: Array[int] = [i]
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			var cx := cur % w
			var cz := cur / w
			if cx > 0 and comp[cur - 1] == 0 and _passable(flags[cur - 1], corr_clear, allow_cross):
				comp[cur - 1] = label
				stack.append(cur - 1)
			if cx < w - 1 and comp[cur + 1] == 0 and _passable(flags[cur + 1], corr_clear, allow_cross):
				comp[cur + 1] = label
				stack.append(cur + 1)
			if cz > 0 and comp[cur - w] == 0 and _passable(flags[cur - w], corr_clear, allow_cross):
				comp[cur - w] = label
				stack.append(cur - w)
			if cz < h - 1 and comp[cur + w] == 0 and _passable(flags[cur + w], corr_clear, allow_cross):
				comp[cur + w] = label
				stack.append(cur + w)
	return {"box": box, "w": w, "flags": flags, "comp": comp}

## A* over (cell, heading) on a grid from _build_grid. 4-connected, no reversing. Step 1, turn
## +CORRIDOR_TURN_COST, a cell of another road (allow_cross only) +ROAD_CROSS_COST. Returns the cells from
## `start` to `goal`, or [] when there is no route.
@warning_ignore("integer_division")
static func _route(grid: Dictionary, start: Vector2i, start_dir: int, goal: Vector2i) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	var box: Rect2i = grid["box"]
	var w: int = grid["w"]
	var flags: PackedByteArray = grid["flags"]
	var comp: PackedInt32Array = grid["comp"]
	if not box.has_point(start) or not box.has_point(goal):
		return none
	var start_idx := (start.y - box.position.y) * w + (start.x - box.position.x)
	var goal_idx := (goal.y - box.position.y) * w + (goal.x - box.position.x)
	if comp[start_idx] == 0 or comp[start_idx] != comp[goal_idx]:
		return none

	var turn := RunTuning.CORRIDOR_TURN_COST
	var cross := RunTuning.ROAD_CROSS_COST
	var states := box.size.x * box.size.y * 4
	var g := PackedFloat32Array()
	g.resize(states)
	g.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(states)
	var closed := PackedByteArray()
	closed.resize(states)
	var start_key := (start_idx << 2) | start_dir
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
			var nx := cx + DIRS[d].x
			var nz := cz + DIRS[d].y
			if nx < box.position.x or nz < box.position.y or nx >= box.end.x or nz >= box.end.y:
				continue
			var nidx := (nz - box.position.y) * w + (nx - box.position.x)
			if comp[nidx] == 0:
				continue
			var nf: int = flags[nidx]
			var cost := 1.0
			if d != pd:
				cost += turn
			if nf & F_USED:
				cost += cross
			var nkey := (nidx << 2) | d
			var ng := cur_g + cost
			if closed[nkey] == 1 or g[nkey] <= ng:
				continue
			g[nkey] = ng
			parent[nkey] = key
			heap.push(ng + float(absi(nx - goal.x) + absi(nz - goal.y)), nkey)
	if goal_key < 0:
		return none

	var cells: Array[Vector2i] = []
	var k: int = goal_key
	while k != -1:
		var idx := k >> 2
		cells.append(Vector2i(idx % w + box.position.x, idx / w + box.position.y))
		k = parent[k]
	cells.reverse()
	return cells

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
