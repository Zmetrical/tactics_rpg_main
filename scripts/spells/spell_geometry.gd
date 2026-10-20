extends RefCounted
## Pure grid maths for spells. Static, no scene, no Battle: everything here is unit-testable.

const Grid = preload("res://scripts/battle/grid.gd")
const Tuning = preload("res://scripts/spells/spell_tuning.gd")

## Clockwise on screen (y grows downward): E, SE, S, SW, W, NW, N, NE.
const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]
## Sentinel for "no cell / no input yet".
const NONE := Vector2i(-9999, -9999)

## Nearest compass direction for an offset. ZERO when the offset is ZERO.
static func snap_dir(delta: Vector2i, diagonal: bool = Tuning.ALLOW_DIAGONAL_AIM) -> Vector2i:
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	var step := PI / 4.0
	if not diagonal:
		step = PI / 2.0
	var angle := roundi(atan2(float(delta.y), float(delta.x)) / step)
	var idx := posmod(angle * int(round(step / (PI / 4.0))), 8)
	return DIRS8[idx]

## Rotate by `steps` eighths of a turn, clockwise. 2 = 90 degrees, 4 = 180.
static func rotate_dir(dir: Vector2i, steps: int) -> Vector2i:
	var i := DIRS8.find(dir)
	if i < 0:
		return Vector2i.ZERO
	return DIRS8[posmod(i + steps, 8)]

static func is_open(grid: Grid, cell: Vector2i) -> bool:
	return grid.is_open(cell)

## Cells walked from `origin` along `dir`, stopping BEFORE the first missing or wall tile.
## The origin itself is not included. Units never stop it: callers decide what to do with them.
static func ray(grid: Grid, origin: Vector2i, dir: Vector2i, length: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if dir == Vector2i.ZERO:
		return out
	var cur := origin
	for _i in length:
		cur += dir
		if not is_open(grid, cur):
			break
		out.append(cur)
	return out

## Grid line from a to b: excludes a, includes b.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx - dy
	var cur := a
	while cur != b:
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			cur.x += sx
		if e2 < dx:
			err += dx
			cur.y += sy
		out.append(cur)
	return out

## Line of Effect: every tile strictly between a and b must be open. The end tiles are not tested.
static func clear_path(grid: Grid, a: Vector2i, b: Vector2i) -> bool:
	var cells := line(a, b)
	for i in range(cells.size() - 1):
		if not is_open(grid, cells[i]):
			return false
	return true

## True when `path` is a legal hand-drawn path: starts next to `origin`, every step is a
## 4-neighbour move, no tile repeats, every tile is open.
static func is_valid_path(grid: Grid, origin: Vector2i, path: Array) -> bool:
	var seen: Dictionary = {origin: true}
	var prev := origin
	for c: Vector2i in path:
		if seen.has(c) or not is_open(grid, c) or absi(c.x - prev.x) + absi(c.y - prev.y) != 1:
			return false
		seen[c] = true
		prev = c
	return true

## Offsets of a plus sign: for arm 1 the 4 neighbours. `from_arm` skips the inner part, so
## cross_offsets(2, 2) is just the 4 tiles at distance 2.
static func cross_offsets(arm: int, from_arm: int = 1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in range(from_arm, arm + 1):
		for dir: Vector2i in Grid.DIRS:
			out.append(dir * d)
	return out

static func corner_offsets() -> Array[Vector2i]:
	return [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
