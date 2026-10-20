extends "res://scripts/spells/spell_behavior.gd"
## Aeromancy / Electric. Unit- or tile-target, Spread (ignores cover, wraps around walls).
##   Base: a 5-tile plus sign, full damage.
##   Tier 2: a shockwave stretches the cross by 4 tiles. Shockwave tiles deal 33%.
##   Tier 3: the shockwave grows again: +4 tiles of length and the 4 corners (+8 over Tier 2).

func aim_steps(_ctx: SpellContext) -> Array:
	return [AimStep.make(AimStep.Kind.TILE, "Pick the centre of the strike", 0, false, true)]

func resolve(ctx: SpellContext, plan: SpellPlan) -> SpellResult:
	var res := SpellResult.new()
	var centre := plan.cell
	if not ctx.grid.can_aim_at(centre):
		return res
	var tier := clampi(ctx.tier, 1, 3)
	var core: Array[Vector2i] = [Vector2i.ZERO]
	core.append_array(Geo.cross_offsets(Tuning.THUNDER_CORE_ARM))
	var wave: Array[Vector2i] = []
	var wave_arm: int = Tuning.THUNDER_WAVE_ARM_BY_TIER[tier - 1]
	if wave_arm > 0:
		wave.append_array(Geo.cross_offsets(wave_arm, Tuning.THUNDER_CORE_ARM + 1))
	if Tuning.THUNDER_WAVE_CORNERS_BY_TIER[tier - 1]:
		wave.append_array(Geo.corner_offsets())
	_strike(ctx, res, centre, core, 1.0, "main")
	_strike(ctx, res, centre, wave, Tuning.ECHO_FRACTION, "echo")
	return res

## Spread ignores cover: a tile only has to exist. Allies are hit too; the caster is not.
func _strike(ctx: SpellContext, res: SpellResult, centre: Vector2i, offsets: Array[Vector2i], scale: float, tag: String) -> void:
	for off in offsets:
		var c := centre + off
		if not ctx.grid.has_tile(c):
			continue
		res.add_cell(c, tag)
		var u := ctx.unit_at(c)
		if u != null and u != ctx.caster:
			res.add_hit(u, scale, "primary" if tag == "main" else "shockwave")
