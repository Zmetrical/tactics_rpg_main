extends RefCounted
## Shared wording for abilities, used by the command menu and the inspect panel.

const Ability = preload("res://scripts/battle/ability.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const Keywords = preload("res://scripts/spells/keywords.gd")
const Rules = preload("res://scripts/battle/rules.gd")
const Tuning = preload("res://scripts/battle/combat_tuning.gd")
const Discipline = preload("res://scripts/skills/discipline.gd")

## Middle dot between the school and the subschool, and between range and cost.
const DOT := "\u00b7"

## 1.5 -> "1.5", 3.0 -> "3".
static func ap_str(v: float) -> String:
	return String.num(v, 1).trim_suffix(".0")

## 1 -> "1 turn", 2 -> "2 turns".
static func turns_str(n: int) -> String:
	return "%d turn%s" % [n, "" if n == 1 else "s"]

## "Scales with STR (B)." plus the bonus it gives this unit right now when `u` is known.
static func scaling_line(u: Unit, a: Ability) -> String:
	if a.scaling_grade == Ability.Grade.NONE:
		return ""
	var line := "Scales with %s (%s)" % [String(Ability.Stat.keys()[a.stat]), Tuning.grade_letter(a.scaling_grade)]
	if u != null:
		line += ": %+d damage" % Rules.scaling_bonus(u, a)
	return line + "."

## "Requires 2 Rogue." or "Requires 2 Cinder, 1 Torrent." for a learnable skill, with the unit's own ranks when `u` is
## known: "(you: 2, 0)". "" for anything else.
static func requirement_line(u: Unit, a: Ability) -> String:
	if not a.has_method("all_requirements"):
		return ""
	var reqs: Dictionary = a.call("all_requirements")
	var need: Array[String] = []
	var have: Array[String] = []
	for d: StringName in reqs.keys():
		need.append("%d %s" % [int(reqs[d]), Discipline.display_name(d)])
		if u != null:
			have.append(str(u.discipline_rank(d)))
	var line := "Requires " + ", ".join(need)
	if u != null:
		line += " (you: %s)" % ", ".join(have)
	return line + "."

## "Cooldown: 2 turns." Empty for abilities without one.
static func cooldown_line(_u: Unit, a: Ability) -> String:
	if a.cooldown_turns <= 0:
		return ""
	return "Cooldown: %s." % turns_str(a.cooldown_turns)

## "1.5 AP", or "1.5 / 3 / 5 AP" for a spell with tiers.
static func cost_name(a: Ability) -> String:
	var max_tier: Variant = a.get("max_tier")
	if max_tier != null and int(max_tier) > 1:
		var parts: Array[String] = []
		for t in range(1, int(max_tier) + 1):
			parts.append(ap_str(a.ap_cost_for_tier(t)))
		return " / ".join(parts) + " AP"
	return "%s AP" % ap_str(a.ap_cost)

## "Spell L2" or "Weapon". Spells no longer spend slots; this only labels them.
static func resource_text(u: Unit, a: Ability) -> String:
	var affordable := "ready"
	if not u.is_available(a):
		affordable = "not memorized"
	elif u.on_cooldown(a):
		affordable = "cooldown %s" % turns_str(u.cooldown_left(a))
	elif not u.can_use(a):
		affordable = "needs %s AP (has %s)" % [ap_str(a.ap_cost), ap_str(u.ap)]
	return ("Spell L%d, " % a.slot_level if a.slot_level > 0 else "") + affordable

## "Range 6" or "Range 6 | Radius 2".
static func shape_text(a: Ability) -> String:
	var s := "Range %d" % a.range_tiles
	if a.area_radius > 0:
		s += " | Radius %d" % a.area_radius
	return s

## "" for instant abilities, otherwise "Charge: 4 ticks".
static func charge_text(a: Ability) -> String:
	if not a.is_charged():
		return ""
	return "Charge: %d ticks" % a.charge_ticks()

## One line, for the inspect panel.
static func summary(u: Unit, a: Ability) -> String:
	var parts: Array[String] = [a.display_name, "[%s]" % cost_name(a), resource_text(u, a), shape_text(a)]
	var charge := charge_text(a)
	if charge != "":
		parts.append(charge)
	return "  ".join(parts)

## Multi-line text for the action bar's description box.
static func detail(u: Unit, a: Ability) -> String:
	var lines: Array[String] = [
		"%s   [%s]" % [a.display_name, cost_name(a)],
		"%s | %s" % [resource_text(u, a), shape_text(a)],
	]
	var charge := charge_text(a)
	if charge != "":
		lines.append(charge)
	var stat_name := String(Ability.Stat.keys()[a.stat])
	match a.roll:
		Ability.Roll.ATTACK:
			lines.append("Attack roll (%s)" % stat_name)
		Ability.Roll.SAVE:
			lines.append("Target saves with %s (DC from %s)" % [String(Ability.Stat.keys()[a.save_stat]), stat_name])
		Ability.Roll.AUTO:
			lines.append("Auto-hit")
	if a.damage_dice != "":
		var dmg := "Damage: %s" % a.damage_dice
		if a.damage_bonus != 0:
			dmg += " %+d" % a.damage_bonus
		var magical := a.damage_type == Ability.DamageType.MAGICAL
		dmg += " %s" % ("magical" if magical else "physical")
		lines.append(dmg)
		lines.append("Hits Magic Barrier, builds Fracture" if magical else "Hits Physical Armor, builds Armor Shred")
	return "\n".join(lines)

## Highest tier this ability offers (1 for weapons and untiered abilities).
static func tier_count(a: Ability) -> int:
	var max_tier: Variant = a.get("max_tier")
	return int(max_tier) if max_tier != null and int(max_tier) > 1 else 1

## Short text for the action bar: the name, then one line of numbers, then one line of effect.
## "Chain Arc" / "1 AP | Range 6 | 5 ticks" / "DEX save | 2d6 magical".
static func brief(a: Ability) -> String:
	var facts: Array[String] = [cost_name(a), "Range %d" % a.range_tiles]
	if a.area_radius > 0:
		facts.append("Radius %d" % a.area_radius)
	if a.is_charged():
		facts.append("%d ticks" % a.charge_ticks())
	var effect: Array[String] = []
	match a.roll:
		Ability.Roll.ATTACK:
			effect.append("Attack roll")
		Ability.Roll.SAVE:
			effect.append("%s save" % String(Ability.Stat.keys()[a.save_stat]))
		Ability.Roll.AUTO:
			effect.append("Auto-hit")
	if a.damage_dice != "":
		var dmg := a.damage_dice
		if a.damage_bonus != 0:
			dmg += " %+d" % a.damage_bonus
		effect.append("%s %s" % [dmg, "magical" if a.damage_type == Ability.DamageType.MAGICAL else "physical"])
	return "%s\n%s\n%s" % [a.display_name, " | ".join(facts), " | ".join(effect)]

## Weapon actions vs spell actions on the action bar. Magical damage or a spell slot = spell.
static func is_spell(a: Ability) -> bool:
	return a.damage_type == Ability.DamageType.MAGICAL or a.slot_level > 0

## "2d6 magic damage", "1d8+3 physical damage".
static func damage_text(a: Ability) -> String:
	if a.damage_dice == "":
		return "damage"
	var dmg := a.damage_dice
	if a.damage_bonus != 0:
		dmg += "%+d" % a.damage_bonus
	return "%s %s damage" % [dmg, "magic" if a.damage_type == Ability.DamageType.MAGICAL else "physical"]

## How an ability is aimed when it has no `aim_text` of its own.
static func _default_aim(a: Ability) -> String:
	return "Target: a tile." if a.area_radius > 0 else "Target: one unit."

## What an ability does when it has no `effect_text` of its own. {dmg} is filled in by body_groups().
static func _default_effect(a: Ability) -> String:
	if a.area_radius > 0:
		return "Deals {dmg} to every unit within radius %d of the target tile." % a.area_radius
	return "Deals {dmg} to the target."

## The bullets that sit ABOVE the tiers, as groups (the card draws a divider before each group):
##   1. timing and aim   "Charge: 5 ticks."  "Target: one enemy with a clear line."   ("Charge: instant." for an uncharged spell)
##   2. effect           "Deals 2d6 magic damage to the target."   (an `effect_text` with "\n" in it is several bullets)
## Everything is written from the ability's numbers so it cannot drift from them. [Keyword]s are glossary
## entries (keywords.gd); the tooltip shows each one as its own card.
static func body_groups(a: Ability) -> Array[Array]:
	var extra := {"dmg": damage_text(a)}
	var timing: Array[String] = []
	if a.is_charged():
		timing.append("Charge: %d ticks." % a.charge_ticks())
	elif is_spell(a):
		timing.append("Charge: instant.")
	timing.append(Keywords.fill(a.aim_text if a.aim_text != "" else _default_aim(a), extra))
	var effect: Array[String] = []
	for line in (a.effect_text if a.effect_text != "" else _default_effect(a)).split("\n", false):
		effect.append(Keywords.fill(line, extra))
	var groups: Array[Array] = [timing, effect]
	return groups

## The bullets that always sit at the BOTTOM, below the tiers:
##   "DEX save (DC INT)."  "Builds Fracture."   (or "Attack roll (STR)."  "Builds Armor Shred.")
static func rule_lines(a: Ability) -> Array[String]:
	var rules: Array[String] = []
	var stat_name := String(Ability.Stat.keys()[a.stat])
	match a.roll:
		Ability.Roll.ATTACK:
			rules.append("Attack roll (%s)." % stat_name)
		Ability.Roll.SAVE:
			rules.append("%s save (DC %s)." % [String(Ability.Stat.keys()[a.save_stat]), stat_name])
		Ability.Roll.AUTO:
			rules.append("Auto-hit.")
	if a.damage_dice != "":
		rules.append("Builds Fracture." if a.damage_type == Ability.DamageType.MAGICAL else "Builds Armor Shred.")
	return rules

## Every bullet except the tiers, as one paragraph (used for keyword lookup and tests).
static func body_text(a: Ability) -> String:
	var parts: Array[String] = []
	for group in body_groups(a):
		for line in group:
			parts.append(String(line))
	parts.append_array(rule_lines(a))
	return " ".join(parts)

## One short line per tier (Base first), tokens filled in. Empty for weapons and untiered abilities.
static func tier_lines(a: Ability) -> Array[String]:
	var out: Array[String] = []
	var tier_text: Variant = a.get("tier_text")
	if tier_text != null:
		for t in (tier_text as Array):
			out.append(Keywords.fill(String(t)) if String(t) != "" else "")
	return out

## Everything the hotbar tooltip shows for one ability, as plain data (ui/hud/tooltip_card.gd draws it).
## Only what is unique to this ability goes on the card. Rules shared with other abilities are [Keyword]s,
## listed in "keywords" and drawn as their own cards beside it.
##   title    name              subtitle  school, or WEAPON ATTACK / SPELL
##   stats    RANGE 6 . 1.5 / 3 / 5 AP     blocks  groups of bullets above the tiers   rules  bullets below the tiers
##   tiers    one line per tier            keywords  glossary names used above
static func tooltip(u: Unit, a: Ability, _can_act: bool = true) -> Dictionary:
	var school: Variant = a.get("school")
	var sub_school: Variant = a.get("subschool")
	var subtitle := "SPELL" if is_spell(a) else "WEAPON ATTACK"
	if school != null and String(school) != "":
		subtitle = String(school).to_upper()
		if sub_school != null and String(sub_school) != "":
			subtitle += " %s %s" % [DOT, String(sub_school).to_upper()]

	var body := body_text(a)
	var tiers := tier_lines(a)
	var footer: Array[String] = []
	if u != null and u.on_cooldown(a):
		footer.append("On cooldown: ready in %s" % turns_str(u.cooldown_left(a)))
	elif u != null and not u.can_use(a):
		footer.append("Not enough AP (have %s)" % ap_str(u.ap))
	var rules := rule_lines(a)
	for extra in [requirement_line(u, a), scaling_line(u, a), cooldown_line(u, a)]:
		if extra != "":
			rules.append(extra)

	return {
		"title": a.display_name,
		"subtitle": subtitle,
		"stats": "RANGE %d %s %s" % [a.range_tiles, DOT, cost_name(a).to_upper()],
		"rank": "",
		"body": body,
		"blocks": body_groups(a),
		"tiers": tiers,
		"rules": rules,
		"keywords": Keywords.in_text(body + " " + " ".join(tiers)),
		"sections": [],
		"footer": footer,
	}
