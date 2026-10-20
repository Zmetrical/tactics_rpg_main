extends RefCounted
## Builds the hover tooltip for a stat header as plain data. TooltipCard.build() (ui/hud/tooltip_card.gd) draws it.
## Keys: the five ability mods (STR DEX CON INT WIS) and the sheet stats (AC PROF SPD MOVE JUMP CT).
##
## The numbers come from the unit, so each line says what the stat does for THIS unit right now. Pass no unit
## to get the rules alone, with no live values. Rates and caps come from combat_tuning.gd, so retuning the
## game updates the text on its own.

const Ability = preload("res://scripts/battle/ability.gd")
const Tuning = preload("res://scripts/battle/combat_tuning.gd")
const Unit = preload("res://scripts/battle/unit.gd")

const STATS := {
	"STR": Ability.Stat.STR, "DEX": Ability.Stat.DEX, "CON": Ability.Stat.CON,
	"INT": Ability.Stat.INT, "WIS": Ability.Stat.WIS,
}
const NAMES := {
	"STR": "Strength", "DEX": "Dexterity", "CON": "Constitution", "INT": "Intelligence", "WIS": "Wisdom",
	"AC": "Armor Class", "PROF": "Proficiency", "SPD": "Speed", "MOVE": "Movement", "JUMP": "Jump",
	"CT": "Charge Time",
}

## `key` is a header from ABILITY_HEADERS / STAT_HEADERS in equipment_window.gd. Returns {} for an unknown key.
static func tip(key: String, unit: Unit = null) -> Dictionary:
	if not NAMES.has(key):
		return {}
	var out := {"title": String(NAMES[key]), "subtitle": key}
	if STATS.has(key):
		_ability(out, key, unit)
	else:
		_sheet(out, key, unit)
	return out

# --- The five ability mods --------------------------------------------------

static func _ability(out: Dictionary, key: String, unit: Unit) -> void:
	var stat: int = STATS[key]
	var live := unit != null
	var m := unit.mod(stat) if live else 0
	if live:
		out["stats"] = "Mod %+d" % m
	var effect: Array = []
	var rules: Array = ["Only a positive mod counts for these bonuses. A negative mod counts as 0."]
	match stat:
		Ability.Stat.STR:
			effect.append("Shred: your physical hits feed Armor Shred %s more impact." % _rate(
					unit.shred_bonus() if live else 0.0, Tuning.SHRED_PER_STR, 0.0, live))
		Ability.Stat.DEX:
			var accuracy := m * Tuning.ACCURACY_PER_DEX
			effect.append("Accuracy: %s to hit." % (
					"%+d%% (%d%% per point)" % [accuracy, Tuning.ACCURACY_PER_DEX] if live
					else "+%d%% per point" % Tuning.ACCURACY_PER_DEX))
			effect.append("Pierce: %s of your physical damage skips Physical Armor." % _rate(
					unit.pierce_fraction(Ability.DamageType.PHYSICAL) if live else 0.0,
					Tuning.PIERCE_PER_DEX, Tuning.PEN_MAX, live))
			rules = ["Pierce ignores a negative mod. Accuracy does not, so a negative DEX lowers your hit chance."]
		Ability.Stat.CON:
			effect.append("Fracture: each Fracture stack needs %s more magical impact." % _rate(
					unit.fracture_threshold_bonus() if live else 0.0,
					Tuning.FRACTURE_THRESHOLD_PER_CON, Tuning.FRACTURE_THRESHOLD_BONUS_MAX, live))
		Ability.Stat.INT:
			effect.append("Magic Pen: %s of your magical damage skips Magic Barrier." % _rate(
					unit.pierce_fraction(Ability.DamageType.MAGICAL) if live else 0.0,
					Tuning.MAGIC_PEN_PER_INT, Tuning.PEN_MAX, live))
		Ability.Stat.WIS:
			effect.append("Resolve: you take %s less impact, so Armor Shred and Fracture stacks build slower." % _rate(
					unit.resolve() if live else 0.0, Tuning.RESOLVE_PER_WIS, Tuning.RESOLVE_MAX, live))

	var shared: Array = [
		"Abilities scaled by %s add flat damage: mod x grade multiplier, rounded down." % [out["subtitle"]],
		"Saves against %s effects: d20 + mod + PROF." % [out["subtitle"]],
	]
	if live:
		shared.append("Casting with %s: save DC %d." % [out["subtitle"], 8 + unit.prof + m])
	out["blocks"] = [effect, shared]
	out["rules"] = rules

# --- AC / PROF / SPD / MOVE / JUMP / CT -------------------------------------

static func _sheet(out: Dictionary, key: String, unit: Unit) -> void:
	var live := unit != null
	var lines: Array = []
	match key:
		"AC":
			if live:
				out["stats"] = str(unit.ac)
			lines = [
				"The unit's armor rating.",
				"A strike's hit chance is the ability's accuracy plus DEX. AC is not part of it.",
			]
		"PROF":
			if live:
				out["stats"] = "+%d" % unit.prof
			lines = [
				"Added to every saving throw: d20 + mod + PROF.",
				"Raises the save DC of this unit's spells: 8 + PROF + the casting stat's mod.",
			]
		"SPD":
			if live:
				out["stats"] = str(unit.spd)
			lines = [
				"Added to Charge Time on every tick, so a faster unit acts more often.",
				"When two units are ready together, the higher CT goes first, then the higher SPD.",
			]
		"MOVE":
			if live:
				out["stats"] = "%d tiles" % unit.move_range
			lines = [
				"Tiles this unit can walk each turn.",
				"Every tile costs 1, whatever the terrain.",
			]
		"JUMP":
			if live:
				out["stats"] = "%d level%s" % [unit.jump, "" if unit.jump == 1 else "s"]
			lines = [
				"The tallest climb or drop a single step can make.",
				"A step between tiles whose heights differ by more than this is blocked.",
			]
		"CT":
			if live:
				out["stats"] = "%d / 100" % unit.ct
			lines = [
				"Charge Time. It rises by SPD every tick.",
				"At 100 or more the unit can act. Taking a turn spends 100.",
			]
	out["blocks"] = [lines]

# --- Helpers ----------------------------------------------------------------

## "+20% (10% per point)" for a live unit, "+10% per point" for the bare rule. " MAX" marks a capped bonus.
static func _rate(value: float, per_point: float, cap: float, live: bool) -> String:
	if not live:
		return "+%s per point" % _pct(per_point)
	var capped := cap > 0.0 and value >= cap - Tuning.THRESHOLD_EPSILON
	return "+%s (%s per point)%s" % [_pct(value), _pct(per_point), " MAX" if capped else ""]

static func _pct(fraction: float) -> String:
	return "%d%%" % roundi(fraction * 100.0)
