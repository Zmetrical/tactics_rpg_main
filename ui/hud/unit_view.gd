extends RefCounted
## THE connection point between your unit data and the new HUD.
##
## Every HUD widget (unit panel, hover preview, target panel, action menu) renders plain
## Dictionaries and never sees a Unit. To feed the HUD from different data, change only this file.
## Field mapping, all read from scripts/battle/unit.gd:
##   hp / max_hp                      -> unit.hp / unit.max_hp
##   barrier / max_barrier (Magic Barrier) -> unit.magic_barrier / unit.max_magic_barrier
##   armor / max_armor                -> unit.physical_armor / unit.max_physical_armor
##   fracture (0-7, counters Magic Barrier) -> unit.fracture_stacks
##   shred (0-7, counters Armor)        -> unit.armor_shred_stacks
##   ap / move                        -> unit.ap, unit.movement (and max_ap, move_range)

const Ability = preload("res://scripts/battle/ability.gd")
const AbilityText = preload("res://ui/ability_text.gd")
const AttackForecast = preload("res://ui/attack_forecast.gd")
const SideTint = preload("res://ui/side_tint.gd")
const Tuning = preload("res://scripts/battle/combat_tuning.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const Rules = preload("res://scripts/battle/rules.gd")
const Equipment = preload("res://scripts/inventory/equipment.gd")
const Item = preload("res://scripts/inventory/item.gd")
const UnitSprites = preload("res://scripts/battle/unit_sprites.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")

## Everything the unit panel, hover preview and target panel draw.
static func build(u: Unit) -> Dictionary:
	var view := {
		"name": u.unit_name,
		"team": SideTint.side_name(u.side).to_upper(),
		"accent": SideTint.color_for(u.side),
		"letter": u.unit_name.substr(0, 1).to_upper(),
		"hp": u.hp, "max_hp": u.max_hp,
		"barrier": u.magic_barrier, "max_barrier": u.max_magic_barrier,
		"armor": u.physical_armor, "max_armor": u.max_physical_armor,
		"fracture": u.fracture_stacks,
		"shred": u.armor_shred_stacks,
		"max_stacks": Tuning.MAX_STACKS,
		"ap": u.ap, "max_ap": u.max_ap,
		"move": u.movement, "max_move": u.move_range,
		"skills_used": u.skill_slots_used(), "skills_max": u.skill_slots,
		"sprite_tex": null,
		"sprite_rect": Rect2(),
	}
	# Same lookup stage_3d.gd uses to pick the unit's sprite block.
	var file_name := u.data.resource_path.get_file().get_basename()
	var tex := UnitSprites.sheet_for(file_name)
	if tex != null:
		view["sprite_tex"] = tex
		view["sprite_rect"] = UnitSprites.frame_rect(file_name, UnitSprites.Row.FRONT, UnitSprites.IDLE_FRAME)
	return view

## Stand-in for an area / tile-locked cast aimed at a tile with no unit on it.
static func tile(cell: Vector2i, accent: Color) -> Dictionary:
	return {
		"name": "TILE %d,%d" % [cell.x, cell.y], "team": "AREA", "accent": accent, "letter": "+",
		"hp": 0, "max_hp": 0, "barrier": 0, "max_barrier": 0, "armor": 0, "max_armor": 0,
		"fracture": 0, "shred": 0, "max_stacks": Tuning.MAX_STACKS,
		"ap": 0.0, "max_ap": 0.0, "move": 0, "max_move": 0, "skills_used": 0, "skills_max": 0, "sprite_tex": null, "sprite_rect": Rect2(),
	}

## Action-menu rows, in the unit's own ability order. `id` is the index into unit.abilities
## (Ability has no id field, so the index is the action_id; see BattleUI.action_chosen).
static func actions(u: Unit, can_act: bool) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in u.abilities.size():
		var a: Ability = u.abilities[i]
		rows.append({
			"id": i,
			"name": a.display_name,
			"cost": "%s AP" % AbilityText.ap_str(a.ap_cost_for_tier(1)),
			"usable": can_act and u.can_use(a),
			"cooldown": u.cooldown_left(a),
			"spell": AbilityText.is_spell(a),
			"detail": AbilityText.brief(a),
		})
	return rows

## Short text for a slot that has no icon: "MH" for an empty Main Hand.
const SLOT_SHORT := {
	Equipment.Slot.HEAD: "HD", Equipment.Slot.TORSO: "TR", Equipment.Slot.LEGS: "LG", Equipment.Slot.BRACE: "BR",
	Equipment.Slot.MAIN_HAND: "MH", Equipment.Slot.OFF_HAND: "OH",
	Equipment.Slot.RING_1: "R1", Equipment.Slot.RING_2: "R2", Equipment.Slot.AMULET: "AM",
}

## Everything the bottom hotbar draws for the current unit. Plain data, no Unit inside:
##   hands           main hand + off hand cells (big slots)
##   weapon_actions  abilities granted by worn weapons, in the unit's own order
##   spells          every other ability
##   armor           head / torso / legs / brace cells
##   jewelry         ring 1 / ring 2 / amulet cells
##   move, max_move  the movement bar
## An ability row: id (index into unit.abilities), name, short, cost, usable, icon, tip (tooltip data).
## A gear cell: slot, has_item, locked, short, icon, tip.
static func hotbar(u: Unit, can_act: bool) -> Dictionary:
	var granted := u.equipment.granted_abilities()
	var weapon_rows: Array[Dictionary] = []
	var spell_rows: Array[Dictionary] = []
	for i in u.abilities.size():
		var a: Ability = u.abilities[i]
		var row := _ability_row(u, a, i, can_act)
		if granted.has(a):
			weapon_rows.append(row)
		else:
			spell_rows.append(row)
	var hands: Array[Dictionary] = []
	for slot in [Equipment.Slot.MAIN_HAND, Equipment.Slot.OFF_HAND]:
		hands.append(_gear_cell(u, slot))
	var armor: Array[Dictionary] = []
	for slot in [Equipment.Slot.HEAD, Equipment.Slot.TORSO, Equipment.Slot.LEGS, Equipment.Slot.BRACE]:
		armor.append(_gear_cell(u, slot))
	var jewelry: Array[Dictionary] = []
	for slot in [Equipment.Slot.RING_1, Equipment.Slot.RING_2, Equipment.Slot.AMULET]:
		jewelry.append(_gear_cell(u, slot))
	return {
		"hands": hands, "weapon_actions": weapon_rows, "spells": spell_rows,
		"armor": armor, "jewelry": jewelry,
		"move": u.movement, "max_move": u.move_range,
		"ap": u.ap, "max_ap": u.max_ap,
		"skills_used": u.skill_slots_used(), "skills_max": u.skill_slots,
	}

static func _ability_row(u: Unit, a: Ability, index: int, can_act: bool) -> Dictionary:
	var icon: Texture2D = null
	for slot in Equipment.ALL_SLOTS:
		var worn: Item = u.equipment.get_item(slot)
		if worn != null and worn.ability == a:
			icon = worn.icon
			break
	# AP cost of each tier the ability has (index 0 = Base). A plain attack has just one entry.
	var tier_costs: Array[float] = []
	for t in range(1, AbilityText.tier_count(a) + 1):
		tier_costs.append(a.ap_cost_for_tier(t))
	return {
		"id": index,
		"name": a.display_name,
		"short": _initials(a.display_name),
		"cost": AbilityText.ap_str(a.ap_cost_for_tier(1)),
		"ap_cost": a.ap_cost_for_tier(1),
		"tier_costs": tier_costs,
		"usable": can_act and u.can_use(a),
		"cooldown": u.cooldown_left(a),
		"icon": icon,
		"tip": AbilityText.tooltip(u, a, can_act),
	}

static func _gear_cell(u: Unit, slot: int) -> Dictionary:
	var item: Item = u.equipment.get_item(slot)
	var locked := u.equipment.is_locked(slot)
	return {
		"slot": slot,
		"has_item": item != null,
		"locked": locked,
		"short": item.display_name.substr(0, 2).to_upper() if item != null else SLOT_SHORT[slot],
		"icon": item.icon if item != null else null,
		"tip": _gear_tip(slot, item, locked),
	}

static func _gear_tip(slot: int, item: Item, locked: bool) -> Dictionary:
	var label := Equipment.slot_label(slot)
	if item == null:
		return {
			"title": label,
			"subtitle": "LOCKED" if locked else "EMPTY",
			"body": "A two-handed weapon is using both hands." if locked else "Nothing is worn here. Click to open the equipment window.",
		}
	var sections: Array[Dictionary] = []
	if item.defense_summary() != "":
		sections.append({"heading": "PROPERTIES", "marker": Palette.INK_LIGHT, "lines": [item.defense_summary()]})
	if item.requirement_summary() != "":
		sections.append({"heading": "REQUIRES", "marker": Palette.INK_LIGHT, "lines": [item.requirement_summary()]})
	if item.ability != null:
		sections.append({"heading": "GRANTS", "marker": Palette.ACCENT,
			"lines": ["%s (%s AP)" % [item.ability.display_name, AbilityText.ap_str(item.ability.ap_cost)]]})
	return {
		"title": item.display_name,
		"subtitle": item.kind_label().to_upper(),
		"rank": label.to_upper(),
		"body": item.description,
		"sections": sections,
	}

## "Fire Bolt" -> "FB", "Longsword" -> "LO".
static func _initials(text: String) -> String:
	var words := text.strip_edges().split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	return text.substr(0, 2).to_upper()

## Attack preview for the target panel. `row` is an AttackForecast.build() dictionary (plus an
## optional "scale" for spell echoes). Display only: the soak order mirrors Unit.take_damage
## (resistance if enabled, then the matching ablative pool, the rest hits HP) on the AVERAGE roll.
static func forecast(row: Dictionary, ability: Ability, tier: int, extra_targets: int, foot: String) -> Dictionary:
	var defender: Unit = row["defender"]
	var dice := _dice(ability.damage_dice)
	var scale: float = float(row.get("scale", 1.0))
	var attacker: Unit = row.get("attacker")
	var bonus := ability.damage_bonus + Rules.scaling_bonus(attacker, ability)
	var lo := roundi(maxi(dice.x + bonus, 0) * scale)
	var hi := roundi(maxi(dice.x * dice.y + bonus, 0) * scale)
	var avg: int = int(row["dmg"])
	var core := _core_damage(defender, ability, avg, attacker)
	var split := _soak(defender, ability, avg, attacker)
	return {
		"ability": ability.display_name,
		"tier": tier,
		"tiered": AbilityText.tier_count(ability) > 1,
		"chance_label": String(row["chance_label"]).to_upper(),
		"hit": int(row["hit"]),
		"crit": int(row["crit"]),
		"dmg_min": lo, "dmg_max": hi,
		"hp_now": defender.hp,
		"hp_after": maxi(defender.hp - core, 0),
		# What the average roll takes off each bar (armor / barrier first, the rest hits HP).
		"to_armor": split["armor"], "to_barrier": split["barrier"], "to_hp": mini(split["hp"], defender.hp),
		"extra_targets": extra_targets,
		"foot": foot,
		# Charged casts commit to a tile or to the unit standing on it; the box shows the Tile / Unit buttons and the lock line.
		"lockable": ability.is_charged(), "lock_ticks": ability.charge_ticks(),
	}

## Forecast for a cast aimed at a tile with nobody on it (charged / area spells).
static func forecast_empty(ability: Ability, tier: int, foot: String) -> Dictionary:
	var dice := _dice(ability.damage_dice)
	return {
		"ability": ability.display_name, "tier": tier, "tiered": AbilityText.tier_count(ability) > 1, "chance_label": "HIT", "hit": -1, "crit": -1,
		"dmg_min": maxi(dice.x + ability.damage_bonus, 0), "dmg_max": maxi(dice.x * dice.y + ability.damage_bonus, 0),
		"hp_now": 0, "hp_after": 0, "to_armor": 0, "to_barrier": 0, "to_hp": 0, "extra_targets": 0, "foot": foot,
		"lockable": ability.is_charged(), "lock_ticks": ability.charge_ticks(),
	}

## What the forecast box shows the moment an ability is SELECTED, before any target is picked: its name, its tier
## (tiered spells only) and the damage range. `aim` tells the box to hide the hit / HP numbers and ask for a target.
static func aim_forecast(ability: Ability, tier: int) -> Dictionary:
	var fc := forecast_empty(ability, tier, "PICK A TARGET")
	fc["aim"] = true
	return fc

static func _dice(text: String) -> Vector2i:
	if text == "":
		return Vector2i.ZERO
	var parts := text.to_lower().split("d")
	return Vector2i(parts[0].to_int(), parts[1].to_int())

## How `amount` splits across the defender's bars (mirrors Unit.take_damage): {armor, barrier, hp}.
static func _soak(defender: Unit, ability: Ability, amount: int, attacker: Unit = null) -> Dictionary:
	var physical := ability.damage_type == Ability.DamageType.PHYSICAL
	var dealt := amount
	if Tuning.APPLY_RESISTANCE_IN_TAKE_DAMAGE:
		var resistance := defender.physical_resistance if physical else defender.magic_resistance
		dealt = maxi(roundi(amount * (1.0 - resistance)), 0)
	var defense := defender.physical_armor if physical else defender.magic_barrier
	var absorbed := mini(dealt - defender.pierced_amount(attacker, dealt, ability.damage_type), defense)
	return {
		"armor": absorbed if physical else 0,
		"barrier": 0 if physical else absorbed,
		"hp": dealt - absorbed,
	}

static func _core_damage(defender: Unit, ability: Ability, amount: int, attacker: Unit = null) -> int:
	var physical := ability.damage_type == Ability.DamageType.PHYSICAL
	var dealt := amount
	if Tuning.APPLY_RESISTANCE_IN_TAKE_DAMAGE:
		var resistance := defender.physical_resistance if physical else defender.magic_resistance
		dealt = maxi(roundi(amount * (1.0 - resistance)), 0)
	var defense := defender.physical_armor if physical else defender.magic_barrier
	return dealt - mini(dealt - defender.pierced_amount(attacker, dealt, ability.damage_type), defense)
