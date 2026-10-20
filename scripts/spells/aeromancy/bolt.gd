extends "res://scripts/spells/spell_behavior.gd"
## Aeromancy / Electric. Directional Lock: fires along a compass line, pierces every unit,
## stops at the first wall or the edge of the map.
##   Base: full damage to everything on the line.
##   Tier 2: the LAST unit pierced takes 33% more.
##   Tier 3: as Tier 2, plus two 3-tile side arcs running parallel to the bolt, centred on the last unit.

func aim_steps(ctx: SpellContext) -> Array:
	return [AimStep.make(AimStep.Kind.DIRECTION, "Pick a direction", ctx.spell.range_tiles)]

func resolve(ctx: SpellContext, plan: SpellPlan) -> SpellResult:
	var res := SpellResult.new()
	var dir := plan.dir_input(0)
	if dir == Vector2i.ZERO:
		return res
	var tier := clampi(ctx.tier, 1, 3)
	var last: Unit = null
	for c in Geo.ray(ctx.grid, ctx.caster.cell, dir, ctx.spell.range_tiles):
		res.add_cell(c, "main")
		var u := ctx.unit_at(c)
		if u != null and u != ctx.caster:
			res.add_hit(u, 1.0, "pierce")
			last = u
	if last == null:
		return res
	if tier >= 2:
		for h in res.hits:
			if h["unit"] == last:
				h["scale"] = 1.0 + Tuning.BOLT_LAST_UNIT_BONUS
				h["tag"] = "pierce_last"
	if tier >= 3:
		var side := Geo.rotate_dir(dir, 2)
		var half := Tuning.BOLT_PARALLEL_LENGTH / 2
		for sign in [1, -1]:
			for j in range(-half, half + 1):
				var c: Vector2i = last.cell + side * sign * Tuning.BOLT_PARALLEL_OFFSET + dir * j
				if not Geo.is_open(ctx.grid, c):
					continue
				res.add_cell(c, "echo")
				var u := ctx.unit_at(c)
				if u != null and u != ctx.caster and not res.has_hit(u):
					res.add_hit(u, Tuning.ECHO_FRACTION, "arc")
	return res
