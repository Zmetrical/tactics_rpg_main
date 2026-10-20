extends RefCounted
## Everything the player decided while aiming. Committed with the cast and resolved later, so a
## charged spell fires at what was aimed at, not at wherever the mouse is when the timer runs out.

const Geo = preload("res://scripts/spells/spell_geometry.gd")

## The aimed cell of a UNIT / TILE first step. Follows the unit while a locked cast charges.
var cell: Vector2i = Geo.NONE
## Lock onto the unit standing on `cell` (the cast follows it) instead of the tile.
var lock_unit := false
## Tier (1 = Base .. 3) the player chose for THIS cast. Tiers cost extra AP; nothing is learned.
var tier := 1
## One entry per aim step, in order: Vector2i (direction / pivot), Array[Vector2i] (path / fork),
## Vector2i (UNIT / TILE cell) or null (skipped).
var inputs: Array = []

func push(value: Variant) -> void:
	inputs.append(value)

func pop() -> Variant:
	return inputs.pop_back() if not inputs.is_empty() else null

func is_complete(step_count: int) -> bool:
	return inputs.size() >= step_count

func has_input(i: int) -> bool:
	return i < inputs.size() and inputs[i] != null

func dir_input(i: int) -> Vector2i:
	if has_input(i) and inputs[i] is Vector2i:
		return inputs[i]
	return Vector2i.ZERO

func path_input(i: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if has_input(i) and inputs[i] is Array:
		out.assign(inputs[i])
	return out

func duplicate_plan() -> RefCounted:
	var p: RefCounted = get_script().new()
	p.cell = cell
	p.lock_unit = lock_unit
	p.tier = tier
	p.inputs = inputs.duplicate(true)
	return p
