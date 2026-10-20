extends RefCounted

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var heights: Dictionary = {}  # Vector2i -> int
var walls: Dictionary = {}    # Vector2i -> true
## Prop layers (see grid_prop.gd). Each maps cell -> prop id, so one prop can be removed later.
var blocked: Dictionary = {}       # nobody can stand on or walk through it
var solid: Dictionary = {}         # stops projectiles (line of effect)
var untargetable: Dictionary = {}  # cannot be aimed at

func set_tile(cell: Vector2i, height: int, wall: bool = false) -> void:
	heights[cell] = height
	if wall:
		walls[cell] = true

func has_tile(cell: Vector2i) -> bool:
	return heights.has(cell)

func height_at(cell: Vector2i) -> int:
	return int(heights.get(cell, 0))

func is_walkable(cell: Vector2i) -> bool:
	return heights.has(cell) and not walls.has(cell) and not blocked.has(cell)

## Open for projectiles: bolts, arcs and drawn paths travel through these (spell_geometry.is_open).
func is_open(cell: Vector2i) -> bool:
	return heights.has(cell) and not walls.has(cell) and not solid.has(cell)

## A tile the range / area highlights should paint. Props that block walking still count.
func is_aim_tile(cell: Vector2i) -> bool:
	return heights.has(cell) and not walls.has(cell) and not untargetable.has(cell)

## May a tile / charged / area spell be centred here? (Walls stay aimable, as before.)
func can_aim_at(cell: Vector2i) -> bool:
	return heights.has(cell) and not untargetable.has(cell)

func add_prop(id: int, cells: Array, blocks_move: bool, blocks_shots: bool, targetable: bool) -> void:
	for c: Vector2i in cells:
		if blocks_move:
			blocked[c] = id
		if blocks_shots:
			solid[c] = id
		if not targetable:
			untargetable[c] = id

func remove_prop(id: int) -> void:
	for layer: Dictionary in [blocked, solid, untargetable]:
		for c: Vector2i in layer.keys():
			if layer[c] == id:
				layer.erase(c)

static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

## BFS. Every tile costs 1. A step needs |height diff| <= jump.
## `blocked` holds cells occupied by units. Returns {"dist": cell->cost, "prev": cell->cell}.
func reach(start: Vector2i, move_pool: int, jump: int, blocked: Dictionary) -> Dictionary:
	var dist: Dictionary = {start: 0}
	var prev: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = dist[cur]
		if d >= move_pool:
			continue
		for dir: Vector2i in DIRS:
			var nxt: Vector2i = cur + dir
			if dist.has(nxt) or not is_walkable(nxt) or blocked.has(nxt):
				continue
			if absi(height_at(nxt) - height_at(cur)) > jump:
				continue
			dist[nxt] = d + 1
			prev[nxt] = cur
			queue.append(nxt)
	return {"dist": dist, "prev": prev}

func path_to(prev: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cur: Vector2i = goal
	while cur != start:
		path.push_front(cur)
		cur = prev[cur]
	return path
