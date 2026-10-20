extends Resource
## One equippable thing. ItemType decides which paper-doll slot it fits;
## Handedness only matters for weapons.

const Ability = preload("res://scripts/battle/ability.gd")

enum ItemType { WEAPON, HEAD, TORSO, LEGS, BRACE, RING, AMULET, CONSUMABLE }
enum Handedness { ONE_HANDED, TWO_HANDED, OFF_HAND_ONLY }

const TYPE_NAMES: Array[String] = ["Weapon", "Head", "Torso", "Legs", "Brace", "Ring", "Amulet", "Consumable"]
const HAND_NAMES: Array[String] = ["One-handed", "Two-handed", "Off-hand only"]

@export var display_name: String = ""
@export var item_type: ItemType = ItemType.WEAPON
## Weapons only. OFF_HAND_ONLY is for shields and tomes.
@export var handedness: Handedness = Handedness.ONE_HANDED
@export var icon: Texture2D
## The attack a weapon grants its wearer (same Ability type the battle code already uses).
@export var ability: Ability
@export_multiline var description: String = ""
## Cells the item covers in the bag (width, height). Leave at 0, 0 to use the default for its type (see bag_size()).
@export var grid_size: Vector2i = Vector2i.ZERO
## Health pools granted while worn: Physical Armor = physical health, Magic Barrier = magic health.
## Armor gives Physical Armor, magical gear gives Magic Barrier. They add up across all worn gear.
@export_group("Defense")
@export var physical_armor: int = 0
@export var magic_barrier: int = 0

## Minimum stat MODS (STR, DEX, CON, INT, WIS) the wearer needs to equip this. 0 = no requirement.
@export_group("Requirements")
@export var req_str: int = 0
@export var req_dex: int = 0
@export var req_con: int = 0
@export var req_int: int = 0
@export var req_wis: int = 0

const STAT_LABELS: Array[String] = ["STR", "DEX", "CON", "INT", "WIS"]

## Required mod per stat, in Ability.Stat order (STR, DEX, CON, INT, WIS).
func requirements() -> Array[int]:
	return [req_str, req_dex, req_con, req_int, req_wis]

## "STR 2, INT 1" for tooltips; empty when the item asks for nothing.
func requirement_summary() -> String:
	var parts: Array[String] = []
	var reqs := requirements()
	for i in reqs.size():
		if reqs[i] > 0:
			parts.append("%s %d" % [STAT_LABELS[i], reqs[i]])
	return ", ".join(parts)

## Bag footprint in cells: grid_size when set, else a default by type (swords tall and thin, armor chunky, rings and consumables one cell).
func bag_size() -> Vector2i:
	if grid_size.x > 0 and grid_size.y > 0:
		return grid_size
	match item_type:
		ItemType.WEAPON:
			match handedness:
				Handedness.TWO_HANDED:
					return Vector2i(2, 4)
				Handedness.OFF_HAND_ONLY:
					return Vector2i(2, 3)
			return Vector2i(1, 3)
		ItemType.HEAD, ItemType.LEGS:
			return Vector2i(2, 2)
		ItemType.TORSO:
			return Vector2i(2, 3)
		ItemType.BRACE:
			return Vector2i(2, 1)
	return Vector2i(1, 1)

func is_weapon() -> bool:
	return item_type == ItemType.WEAPON

func is_two_handed() -> bool:
	return is_weapon() and handedness == Handedness.TWO_HANDED

## "Two-handed weapon", "Ring", ... for tooltips.
func kind_label() -> String:
	if is_weapon():
		return "%s weapon" % HAND_NAMES[handedness]
	return TYPE_NAMES[item_type]

## "+8 Physical Armor" for tooltips; empty when the item grants no defense.
func defense_summary() -> String:
	var parts: Array[String] = []
	if physical_armor != 0:
		parts.append("%+d Physical Armor" % physical_armor)
	if magic_barrier != 0:
		parts.append("%+d Magic Barrier" % magic_barrier)
	return ", ".join(parts)
