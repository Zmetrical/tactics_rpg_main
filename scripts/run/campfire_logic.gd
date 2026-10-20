extends RefCounted
## Campfire rule: heal every living party unit. Pure logic, no nodes.

const RunTuning = preload("res://scripts/run/run_tuning.gd")

## Heals each living member (hp > 0) by CAMPFIRE_HEAL of max HP, capped at max HP.
## Returns [{name, before, after, max}] in party order.
static func rest(party: Array) -> Array:
	var out: Array = []
	for m in party:
		var max_hp: int = m.unit_data.max_hp
		var before: int = m.current_hp
		if before > 0:
			m.current_hp = mini(max_hp, before + ceili(max_hp * RunTuning.CAMPFIRE_HEAL))
		out.append({"name": m.unit_data.display_name, "before": before, "after": m.current_hp, "max": max_hp})
	return out
