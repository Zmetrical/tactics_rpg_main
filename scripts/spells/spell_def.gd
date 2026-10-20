extends "res://scripts/battle/ability.gd"
## A spell is an Ability (so cost, slots, range, dice and the HUD all keep working) plus a school,
## tiers and a behaviour that knows how to aim and resolve it. Tooltip wording is `effect_text` (on Ability)
## plus `tier_text`; shared rules live in keywords.gd.

const SpellBehavior = preload("res://scripts/spells/spell_behavior.gd")
const SpellRegistry = preload("res://scripts/spells/spell_registry.gd")
const Keywords = preload("res://scripts/spells/keywords.gd")

## Key into SpellRegistry.
@export var spell_id: StringName = &""
@export var school: String = ""
@export var subschool: String = ""
@export var max_tier: int = 3
## Index 0 = Base, 1 = Tier 2, 2 = Tier 3. One short line each. [Keyword] and {token} work here too.
## What the spell does at every tier is `effect_text` (declared on Ability).
@export var tier_text: Array[String] = []

func behavior() -> SpellBehavior:
	return SpellRegistry.behavior_for(spell_id)

## The spell in the project's design format.
func format_entry() -> String:
	var lines: Array[String] = ["Category: %s  Subcat: %s" % [school, subschool], "%s (cast time %d ticks)" % [display_name, charge_ticks()]]
	if aim_text != "":
		lines.append("- %s" % Keywords.fill(aim_text))
	lines.append("- %s" % Keywords.fill(effect_text, {"dmg": "%s magic damage" % damage_dice}).replace("\n", " "))
	var names := ["Base", "Tier 2", "Tier 3"]
	for i in tier_text.size():
		lines.append("%s: %s" % [names[i], Keywords.fill(tier_text[i])])
	return "\n".join(lines)
