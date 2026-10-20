extends RefCounted
## The aiming session for one spell cast. battle_view drives it with hover / click / skip / back;
## it never touches Battle state. When is_complete() is true, hand plan to Battle.use_ability.
##
## The preview is the spell's own resolve() run on the plan-so-far plus whatever the cursor is
## showing, so what you see is exactly what will happen.

const AimStep = preload("res://scripts/spells/aim_step.gd")
const Geo = preload("res://scripts/spells/spell_geometry.gd")
const Grid = preload("res://scripts/battle/grid.gd")
const SpellBehavior = preload("res://scripts/spells/spell_behavior.gd")
const SpellContext = preload("res://scripts/spells/spell_context.gd")
const SpellPlan = preload("res://scripts/spells/spell_plan.gd")
const SpellResult = preload("res://scripts/spells/spell_result.gd")

var ctx: SpellContext
var behavior: SpellBehavior
var steps: Array = []
var plan: SpellPlan = SpellPlan.new()
## The path being drawn for the current PATH / FORK step: absolute cells.
var draft: Array[Vector2i] = []
var hover_cell: Vector2i = Geo.NONE
## Why the last click was refused ("" if it was accepted).
var last_error := ""
## Applied to the first step when it is a lockable TILE (the view's lock-on toggle).
var lock_unit := false

func _init(p_ctx: SpellContext) -> void:
	ctx = p_ctx
	behavior = ctx.spell.behavior()
	steps = behavior.aim_steps(ctx)
	plan.tier = ctx.tier
	# Spells that start with a direction or a path have no aimed cell: anchor them on the caster.
	if not steps.is_empty() and steps[0].kind != AimStep.Kind.UNIT and steps[0].kind != AimStep.Kind.TILE:
		plan.cell = ctx.caster.cell

func step_index() -> int:
	return plan.inputs.size()

func is_complete() -> bool:
	return plan.is_complete(steps.size())

func current_step() -> AimStep:
	return steps[step_index()] if not is_complete() else null

## One line for the HUD.
func prompt() -> String:
	var s := current_step()
	if s == null:
		return "Ready"
	var text := "Step %d/%d: %s" % [step_index() + 1, steps.size(), s.label]
	if s.optional:
		text += "  (Enter skips)"
	return text

func hover(cell: Vector2i) -> void:
	hover_cell = cell

## Returns true when the click was accepted. `last_error` explains a refusal.
func click(cell: Vector2i) -> bool:
	last_error = ""
	var s := current_step()
	if s == null:
		return false
	var i := step_index()
	match s.kind:
		AimStep.Kind.UNIT, AimStep.Kind.TILE:
			var err := behavior.validate_step(ctx, plan, i, cell)
			if err != "":
				last_error = err
				return false
			plan.cell = cell
			plan.lock_unit = s.kind == AimStep.Kind.UNIT or (s.lockable and lock_unit)
			if plan.lock_unit and ctx.unit_at(cell) == null:
				plan.lock_unit = false
				last_error = "No unit there to lock onto"
				return false
			plan.push(cell)
		AimStep.Kind.DIRECTION, AimStep.Kind.PIVOT:
			var dir := Geo.snap_dir(cell - _origin(i), not s.cardinal)
			var err2 := behavior.validate_step(ctx, plan, i, dir)
			if err2 != "":
				last_error = err2
				return false
			plan.push(dir)
		AimStep.Kind.PATH, AimStep.Kind.FORK:
			return _click_path(s, i, cell)
	return true

func _click_path(s: AimStep, i: int, cell: Vector2i) -> bool:
	var origin := _origin(i)
	if origin == Geo.NONE:
		last_error = "Nothing to fork from"
		return false
	if not draft.is_empty() and cell == draft.back():
		return _commit_path(s, i, origin)  # clicking the last tile confirms
	var route := route_to(cell)
	if route.is_empty():
		last_error = "No route to that tile" if draft.size() < s.reach else "Path is at its %d-tile limit" % s.reach
		return false
	draft.append_array(route)
	if draft.size() >= s.reach or behavior.path_ends_at(ctx, plan, i, draft.back()):
		return _commit_path(s, i, origin)
	return true

## The tiles a click on `cell` would add to the path being drawn: the cheapest 4-connected route from
## the end of the path (or the caster / fork anchor) to the cursor. It prefers straight lines, goes
## around units when it can, and stops at the tile limit or at the first unit the spell would hit.
## The hover preview draws exactly this, so the line follows the mouse.
func route_to(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := current_step()
	if s == null or (s.kind != AimStep.Kind.PATH and s.kind != AimStep.Kind.FORK):
		return out
	var i := step_index()
	var origin := _origin(i)
	if origin == Geo.NONE:
		return out
	var start: Vector2i = draft.back() if not draft.is_empty() else origin
	var remaining := s.reach - draft.size()
	if remaining <= 0 or cell == start:
		return out
	var taken: Dictionary = {origin: true}
	for c in draft:
		taken[c] = true
	for c in _cheapest_route(start, cell, taken):
		out.append(c)
		if out.size() >= remaining or behavior.path_ends_at(ctx, plan, i, c):
			break
	return out

const _TURN_COST := 0.1   # tie-break: straight lines beat staircases
const _UNIT_COST := 4.0   # walking through a unit costs more than a short detour

## Dijkstra over (tile, heading). Returns the tiles after `start` up to and including `goal`, or [].
func _cheapest_route(start: Vector2i, goal: Vector2i, taken: Dictionary) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not Geo.is_open(ctx.grid, goal) or taken.has(goal):
		return empty
	var begin := Vector3i(start.x, start.y, -1)
	var best: Dictionary = {begin: 0.0}
	var came: Dictionary = {}
	var open: Array = [[0.0, begin]]
	while not open.is_empty():
		var at := 0
		for k in open.size():
			if open[k][0] < open[at][0]:
				at = k
		var row: Array = open.pop_at(at)
		var cost: float = row[0]
		var state: Vector3i = row[1]
		if cost > float(best.get(state, INF)):
			continue
		var here := Vector2i(state.x, state.y)
		if here == goal:
			var path: Array[Vector2i] = []
			var cur := state
			while cur != begin:
				path.push_front(Vector2i(cur.x, cur.y))
				cur = came[cur]
			return path
		for d in Grid.DIRS.size():
			var next: Vector2i = here + Grid.DIRS[d]
			if taken.has(next) or not Geo.is_open(ctx.grid, next):
				continue
			var step := 1.0
			if state.z != -1 and state.z != d:
				step += _TURN_COST
			var occupant := ctx.unit_at(next)
			if next != goal and occupant != null and occupant != ctx.caster:
				step += _UNIT_COST
			var nstate := Vector3i(next.x, next.y, d)
			var ncost := cost + step
			if ncost < float(best.get(nstate, INF)):
				best[nstate] = ncost
				came[nstate] = state
				open.append([ncost, nstate])
	return empty

func _commit_path(s: AimStep, i: int, origin: Vector2i) -> bool:
	var stored: Array[Vector2i] = []
	for c in draft:
		stored.append(c if s.kind == AimStep.Kind.PATH else c - origin)
	var err := behavior.validate_step(ctx, plan, i, stored)
	if err != "":
		last_error = err
		return false
	if i == 0:
		plan.cell = ctx.caster.cell
	plan.push(stored)
	draft = []
	return true

## Skips the current optional step and every step after it.
func skip() -> bool:
	var s := current_step()
	if s == null or not s.optional:
		return false
	draft = []
	while not is_complete():
		plan.push(null)
	return true

## Undo one thing: the last drawn tile, else the last finished step. False = nothing left, the caller cancels targeting.
func back() -> bool:
	if not draft.is_empty():
		draft.pop_back()
		return true
	if plan.inputs.is_empty():
		return false
	plan.pop()
	return true

## What the spell would do with the plan so far plus the cursor.
func preview() -> SpellResult:
	var p: SpellPlan = plan.duplicate_plan()
	var s := current_step()
	if s != null and hover_cell != Geo.NONE:
		var i := step_index()
		match s.kind:
			AimStep.Kind.UNIT, AimStep.Kind.TILE:
				p.cell = hover_cell
				p.lock_unit = false
				p.push(hover_cell)
			AimStep.Kind.DIRECTION, AimStep.Kind.PIVOT:
				p.push(Geo.snap_dir(hover_cell - _origin(i), not s.cardinal))
			AimStep.Kind.PATH, AimStep.Kind.FORK:
				# Draws from the unit (or the end of the drawn path) to the mouse.
				var origin := _origin(i)
				var shown := draft.duplicate()
				shown.append_array(route_to(hover_cell))
				var stored: Array[Vector2i] = []
				for c in shown:
					stored.append(c if s.kind == AimStep.Kind.PATH else c - origin)
				p.push(stored)
	if p.cell == Geo.NONE:
		return SpellResult.new()
	return behavior.resolve(ctx, p)

func _origin(i: int) -> Vector2i:
	return behavior.step_origin(ctx, plan, i)
