extends RefCounted
## Aeromancy / Electric: the four sample spells. Pure data; the rules live in the behaviours.
## Cast speed uses Ability.charge_speed, same as Burning Burst: ticks = ceil(100 / charge_speed).
## Chain Arc 20 = 5 ticks, Thunder 12 = 9, Bolt 25 = 4, Surge 20 = 5.
## Damage numbers are first-pass placeholders: tune dice here, shape and tier rules in spell_tuning.gd.

const SpellDef = preload("res://scripts/spells/spell_def.gd")
const Ability = preload("res://scripts/battle/ability.gd")

static func all() -> Array[SpellDef]:
	return [chain_arc(), thunder(), bolt(), surge()]

static func by_id(id: StringName) -> SpellDef:
	for s in all():
		if s.spell_id == id:
			return s
	return null

static func _base(id: StringName, p_name: String, p_charge_speed: int, slot: int, range_tiles: int, dice: String) -> SpellDef:
	var s := SpellDef.new()
	s.spell_id = id
	s.display_name = p_name
	s.school = "Aeromancy"
	s.subschool = "Electric"
	s.charge_speed = p_charge_speed
	s.slot_level = slot
	s.range_tiles = range_tiles
	s.damage_dice = dice
	s.roll = Ability.Roll.SAVE
	s.stat = Ability.Stat.INT
	s.save_stat = Ability.Stat.DEX
	s.damage_type = Ability.DamageType.MAGICAL
	return s

static func chain_arc() -> SpellDef:
	var s := _base(&"chain_arc", "Chain Arc", 20, 1, 6, "2d6")
	s.aim_text = "Target: one enemy with a clear line."
	s.effect_text = "Deals {dmg} to the target."
	s.tier_text = [
		"No [Bounce].",
		"Adds one [Bounce], in a direction you choose.",
		"Adds a second [Bounce] opposite the first. They rotate together.",
	]
	return s

static func thunder() -> SpellDef:
	var s := _base(&"thunder", "Thunder", 12, 3, 6, "3d6")
	s.area_radius = 1  # the base cross; also what the combat director reads to stage a burst
	s.aim_text = "Target: a tile, or a unit to follow."
	s.effect_text = "Deals {dmg} to every unit in the [Spread].\nTiles added by tiers take {echo} of the roll."
	s.tier_text = [
		"Plus shape: 5 tiles.",
		"Each arm 1 tile longer: 9 tiles.",
		"Each arm 2 tiles longer, corners filled: 17 tiles.",
	]
	return s

static func bolt() -> SpellDef:
	var s := _base(&"bolt", "Bolt", 25, 2, 8, "2d8")
	s.aim_text = "Target: a direction (1 of 8)."
	s.effect_text = "Deals {dmg} to every unit it [Pierce]s."
	s.tier_text = [
		"Every unit takes full damage.",
		"The last unit hit takes {last} more damage.",
		"Adds two {side}-tile lines beside the last unit, one on each side, dealing {echo} of the roll.",
	]
	return s

static func surge() -> SpellDef:
	var s := _base(&"surge", "Surge", 20, 2, 8, "2d8")
	s.aim_text = "Target: a path of up to {path} tiles, drawn one tile at a time."
	s.effect_text = "Deals {dmg} to the first unit on the path, allies included."
	s.tier_text = [
		"One path, one victim.",
		"Adds a {f1len}-tile fork from the unit hit, dealing {f1pct} of the roll to the first new unit on it.",
		"Adds a {f2len}-tile fork from the fork's victim, dealing {f2pct} of the roll to the first new unit on it.",
	]
	return s
