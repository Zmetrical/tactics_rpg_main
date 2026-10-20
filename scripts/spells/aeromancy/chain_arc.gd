extends "res://scripts/spells/spell_behavior.gd"
## Aeromancy / Electric. Single-target, Line of Effect.
##   Base: one locked projectile. No bounce.
##   Tier 2: Pivot Targeting. After the lock, the player rotates a 2-tile bounce arm around the target
##           (8 directions). It can strike up to two units for 33%.
##   Tier 3: Manual Fork. The bounce splits into two arms, mirrored 180 degrees apart; rotating one swings the other.
## A unit is never struck twice by one cast, so overlapping arms and the primary never stack.
## Line of Effect, not line of sight: the arc is a projectile. It travels the grid line from the caster
## and stops at the first physical collision, a wall OR another unit. You can only lock a target that
## nothing stands in front of. If something steps into the line before a charged cast resolves, that
## unit is what the projectile hits (and what the bounce pivots around); a wall means it fizzles.
## Bounce arms aim in 8 directions (Tuning.ARC_PIVOT_DIAGONAL).

func aim_steps(ctx: SpellContext) -> Array:
	var steps: Array = [AimStep.make(AimStep.Kind.UNIT, "Lock onto an enemy (needs a clear path)")]
	var tier := clampi(ctx.tier, 1, 3)
	if tier >= 2:
		var label := "Pivot the bounce, click to confirm" if tier == 2 else "Fork the bounce (the two arms mirror), click to confirm"
		steps.append(AimStep.make(AimStep.Kind.PIVOT, label, Tuning.ARC_BOUNCE_REACH, true, false, not Tuning.ARC_PIVOT_DIAGONAL))
	return steps

func step_origin(ctx: SpellContext, plan: SpellPlan, i: int) -> Vector2i:
	if i == 1:
		return plan.cell
	return ctx.caster.cell

func validate_step(ctx: SpellContext, plan: SpellPlan, i: int, input: Variant) -> String:
	var err := super.validate_step(ctx, plan, i, input)
	if err != "" or i != 0:
		return err
	var blocker := _first_collision(ctx, input)
	if blocker.get("wall", false):
		return "No clear path: a wall is in the way"
	var hit: Unit = blocker.get("unit")
	if hit != ctx.unit_at(input):
		return "No clear path: %s is in the way" % hit.unit_name
	return ""

## What the projectile hits first on its way to `target_cell`: {"unit": Unit} or {"wall": true}.
## Empty = the line is open but ends on an empty tile.
func _first_collision(ctx: SpellContext, target_cell: Vector2i) -> Dictionary:
	for c in Geo.line(ctx.caster.cell, target_cell):
		if not Geo.is_open(ctx.grid, c):
			return {"wall": true}
		var u := ctx.unit_at(c)
		if u != null and u != ctx.caster:
			return {"unit": u}
	return {}

func resolve(ctx: SpellContext, plan: SpellPlan) -> SpellResult:
	var res := SpellResult.new()
	# The projectile flies at the locked cell and stops at the first collision. Usually that is the
	# target; if a unit stepped into the line it takes the hit instead, and a wall fizzles the cast.
	var hit_info := _first_collision(ctx, plan.cell)
	var primary: Unit = hit_info.get("unit")
	if primary == null:
		return res
	for c in Geo.line(ctx.caster.cell, primary.cell):
		res.add_cell(c, "path")
	res.add_hit(primary, 1.0, "primary")
	res.add_cell(primary.cell, "main")

	var pivot := plan.dir_input(1)
	if pivot == Vector2i.ZERO:
		return res
	var struck: Array = [primary]
	var arms: int = Tuning.ARC_ARMS_BY_TIER[clampi(ctx.tier, 1, 3) - 1]
	if arms <= 0:
		return res
	var spread := 8 / arms
	for k in arms:
		var dir := Geo.rotate_dir(pivot, k * spread)
		var arm_hits := 0
		for c in Geo.ray(ctx.grid, primary.cell, dir, Tuning.ARC_BOUNCE_REACH):
			res.add_cell(c, "echo")
			var u := ctx.unit_at(c)
			if u == null or u == ctx.caster or struck.has(u) or arm_hits >= Tuning.ARC_BOUNCE_MAX_UNITS:
				continue
			struck.append(u)
			arm_hits += 1
			res.add_hit(u, Tuning.ECHO_FRACTION, "bounce")
	return res
