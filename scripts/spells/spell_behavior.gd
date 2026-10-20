extends RefCounted
## Base class for one spell's rules. Subclasses override aim_steps() and resolve(); everything
## else has a sensible default. A behaviour holds NO state: it reads the context and the plan.
##
## To add a spell: write a behaviour, register it in spell_registry.gd, describe it in a
## SpellDef (see aeromancy/electric_spells.gd). Nothing else changes.

const AimStep = preload("res://scripts/spells/aim_step.gd")
const Geo = preload("res://scripts/spells/spell_geometry.gd")
const Grid = preload("res://scripts/battle/grid.gd")
const SpellContext = preload("res://scripts/spells/spell_context.gd")
const SpellPlan = preload("res://scripts/spells/spell_plan.gd")
const SpellResult = preload("res://scripts/spells/spell_result.gd")
const Tuning = preload("res://scripts/spells/spell_tuning.gd")
const Unit = preload("res://scripts/battle/unit.gd")

## What the player must decide, in order. May depend on the tier (ctx.tier).
func aim_steps(_ctx: SpellContext) -> Array:
	return []

## Where step `i` starts from: the caster, unless a spell anchors it elsewhere (a pivot or fork
## hangs off an earlier victim). Returns Geo.NONE when there is no valid anchor yet.
func step_origin(ctx: SpellContext, _plan: SpellPlan, _i: int) -> Vector2i:
	return ctx.caster.cell

## "" when `input` is legal for step `i`, otherwise a short reason for the log / prompt.
## `input` is a cell (UNIT / TILE), a direction (DIRECTION / PIVOT) or a path (PATH / FORK).
func validate_step(ctx: SpellContext, plan: SpellPlan, i: int, input: Variant) -> String:
	var step: AimStep = aim_steps(ctx)[i]
	match step.kind:
		AimStep.Kind.UNIT:
			var u := ctx.unit_at(input)
			if u == null or not ctx.is_hostile(u):
				return "Needs an enemy unit"
			if Grid.distance(ctx.caster.cell, input) > ctx.spell.range_tiles:
				return "Out of range"
		AimStep.Kind.TILE:
			if not ctx.grid.can_aim_at(input):
				return "No tile there"
			if Grid.distance(ctx.caster.cell, input) > ctx.spell.range_tiles:
				return "Out of range"
		AimStep.Kind.DIRECTION, AimStep.Kind.PIVOT:
			if input == Vector2i.ZERO:
				return "Pick a direction"
		AimStep.Kind.PATH:
			if not Geo.is_valid_path(ctx.grid, step_origin(ctx, plan, i), input) or input.size() > step.reach:
				return "Not a valid path"
		AimStep.Kind.FORK:
			var origin := step_origin(ctx, plan, i)
			var absolute: Array[Vector2i] = []
			for off: Vector2i in input:
				absolute.append(origin + off)
			if origin == Geo.NONE or not Geo.is_valid_path(ctx.grid, origin, absolute) or input.size() > step.reach:
				return "Not a valid path"
	return ""

## Re-checks a finished plan (the battle calls this before committing).
func validate_plan(ctx: SpellContext, plan: SpellPlan) -> String:
	var steps := aim_steps(ctx)
	for i in steps.size():
		if not plan.has_input(i):
			if not steps[i].optional:
				return "%s is not chosen" % steps[i].label
			continue
		var err := validate_step(ctx, plan, i, plan.cell if _uses_plan_cell(steps[i]) else plan.inputs[i])
		if err != "":
			return err
	return ""

## True when a PATH / FORK should stop growing at `cell` (the spell has found what it hits).
func path_ends_at(ctx: SpellContext, _plan: SpellPlan, _i: int, cell: Vector2i) -> bool:
	var u := ctx.unit_at(cell)
	return u != null and u != ctx.caster

## What the spell does with the plan as it stands. MUST tolerate a partial plan (fewer inputs than
## steps) and skipped steps, because the hover preview calls it mid-aim. Pure: never mutates anything.
func resolve(_ctx: SpellContext, _plan: SpellPlan) -> SpellResult:
	return SpellResult.new()

static func _uses_plan_cell(step: AimStep) -> bool:
	return step.kind == AimStep.Kind.UNIT or step.kind == AimStep.Kind.TILE
