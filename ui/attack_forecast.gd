extends RefCounted
## Fire Emblem-style forecast numbers for one attacker -> defender pair. Pure maths, no state.
## Mirrors Rules.resolve_attack / resolve_save (d20 + mod + PROF vs AC / DC; nat 20 always hits
## and crits, nat 1 always misses; advantage = best of two d20s, disadvantage = worst of two).
## Rules has no probability API and may not be edited, so the formulas are repeated here.

const Ability = preload("res://scripts/battle/ability.gd")
const Rules = preload("res://scripts/battle/rules.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const Tuning = preload("res://scripts/battle/combat_tuning.gd")

## Phase 2: ATTACK rolls no longer use d20 vs AC. Hit % = Rules.hit_chance (accuracy + DEX), then
## Rules.chance_with_mode for Advantage / Disadvantage. SAVE rolls are unchanged.
const NOT_APPLICABLE := -1

## Row for TargetPreviewPanel. hit / crit are percentages, or NOT_APPLICABLE.
static func build(attacker: Unit, defender: Unit, ability: Ability, mode: int) -> Dictionary:
	var dice := _parse_dice(ability.damage_dice)
	var bonus := ability.damage_bonus + Rules.scaling_bonus(attacker, ability)
	var dmg_min := maxi(dice.x + bonus, 0)
	var dmg_max := maxi(dice.x * dice.y + bonus, 0)
	var dmg_avg := maxi(roundi(dice.x * (dice.y + 1) / 2.0) + bonus, 0)

	var hit := 100
	var crit := NOT_APPLICABLE
	var chance_label := "Hit"
	var note := "Damage %d-%d" % [dmg_min, dmg_max]
	match ability.roll:
		Ability.Roll.ATTACK:
			var chance := Rules.hit_chance(attacker, ability)
			hit = Rules.chance_with_mode(chance, mode)
			crit = Rules.chance_with_mode(mini(chance, Tuning.CRIT_ROLL), mode)
		Ability.Roll.SAVE:
			var save_bonus := defender.mod(ability.save_stat) + defender.prof
			var dc := Rules.spell_dc(attacker, ability)
			hit = _percent(Rules.Mode.NORMAL, func(d20: int) -> bool: return d20 + save_bonus < dc)
			chance_label = "Fail"
			note += "  (half on a passed save)"
	return {
		"attacker": attacker,
		"defender": defender,
		"weapon": ability.display_name,
		"mode_name": Rules.mode_name(mode) if mode != Rules.Mode.NORMAL else "",
		"chance_label": chance_label,
		"hit": hit,
		"crit": crit,
		"dmg": dmg_avg,
		"note": note,
	}

## Chance (0-100) that `succeeds(d20)` holds for the kept die under the given roll mode.
static func _percent(mode: int, succeeds: Callable) -> int:
	var good := 0
	var total := 0
	for face in range(1, 21):
		var weight := 1
		if mode == Rules.Mode.ADV:
			weight = 2 * face - 1
		elif mode == Rules.Mode.DIS:
			weight = 41 - 2 * face
		total += weight
		if succeeds.call(face):
			good += weight
	return roundi(100.0 * good / total)

## "2d6" -> Vector2i(2, 6). "" -> (0, 0).
static func _parse_dice(dice: String) -> Vector2i:
	if dice == "":
		return Vector2i.ZERO
	var parts := dice.to_lower().split("d")
	return Vector2i(parts[0].to_int(), parts[1].to_int())
