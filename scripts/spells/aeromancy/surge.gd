extends "res://scripts/spells/spell_behavior.gd"
## Aeromancy / Electric. Vector Pathing: the player draws the exact route, tile by tile (8 max).
## The surge hits the first unit on the route, allies included, so the route is the aim.
##   Base: one path, one victim.
##   Tier 2: Manual Fork. From that first victim the player draws a second path (6 tiles) that
##           hits the first NEW unit on it for 50% of the damage.
##   Tier 3: a second fork (4 tiles) leaves the fork's victim for 25%.
## Fork paths are stored relative to their anchor, so they still make sense if the anchor unit has
## moved by the time a charged cast resolves.

func aim_steps(ctx: SpellContext) -> Array:
	var steps: Array = [AimStep.make(AimStep.Kind.PATH, "Draw the path (click the last tile to confirm)", Tuning.SURGE_PATH_LENGTH)]
	var forks: int = Tuning.SURGE_FORKS_BY_TIER[clampi(ctx.tier, 1, 3) - 1]
	for f in forks:
		steps.append(AimStep.make(AimStep.Kind.FORK, "Draw fork %d from the struck unit" % (f + 1), Tuning.SURGE_FORK_LENGTHS[f], true))
	return steps

## A fork leaves the unit the previous segment struck. NONE if that segment struck nothing.
func step_origin(ctx: SpellContext, plan: SpellPlan, i: int) -> Vector2i:
	if i == 0:
		return ctx.caster.cell
	var res := resolve_until(ctx, plan, i)
	if res.hits.size() < i:
		return Geo.NONE
	return res.hits[i - 1]["unit"].cell

func path_ends_at(ctx: SpellContext, plan: SpellPlan, i: int, cell: Vector2i) -> bool:
	var u := ctx.unit_at(cell)
	if u == null or u == ctx.caster:
		return false
	return not resolve_until(ctx, plan, i).has_hit(u)

func resolve(ctx: SpellContext, plan: SpellPlan) -> SpellResult:
	return resolve_until(ctx, plan, plan.inputs.size())

## Plays segments 0 .. count-1 only (used to find a fork's anchor and the units to skip).
func resolve_until(ctx: SpellContext, plan: SpellPlan, count: int) -> SpellResult:
	var res := SpellResult.new()
	var origin := ctx.caster.cell
	for i in mini(count, plan.inputs.size()):
		var segment := plan.path_input(i)
		if segment.is_empty():
			break
		var cells: Array[Vector2i] = []
		for c in segment:
			cells.append(c if i == 0 else origin + c)
		if not Geo.is_valid_path(ctx.grid, origin, cells):
			break
		var victim: Unit = null
		for c in cells:
			res.add_cell(c, "path")
			var u := ctx.unit_at(c)
			if u != null and u != ctx.caster and not res.has_hit(u):
				victim = u
				break
		if victim == null:
			break
		var scale := 1.0 if i == 0 else Tuning.SURGE_FORK_SCALES[i - 1]
		res.add_hit(victim, scale, "primary" if i == 0 else "fork")
		origin = victim.cell
	return res
