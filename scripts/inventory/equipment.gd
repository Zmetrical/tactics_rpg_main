extends RefCounted
## What one unit wears: 13 fixed paper-doll slots (9 gear + 4 consumable) and the rules that keep them consistent.
## Pure logic, no nodes. The UI listens to slot_changed and calls try_equip / unequip.
##
## This class never keeps an item it displaces. Every call hands displaced items back
## (Result.displaced, or unequip's return value) so the caller can put them in the bag.
## preview() runs an equip on a copy first, to see what would come off.

const Ability = preload("res://scripts/battle/ability.gd")
const Item = preload("res://scripts/inventory/item.gd")

## Fired whenever a slot's item or lock state changes.
signal slot_changed(slot: int)

enum Slot { NONE = -1, HEAD, TORSO, LEGS, BRACE, MAIN_HAND, OFF_HAND, RING_1, RING_2, AMULET, CONSUMABLE_1, CONSUMABLE_2, CONSUMABLE_3, CONSUMABLE_4 }
enum SlotState { UNLOCKED, LOCKED }

## Paper-doll left column.
const ARMOR_SLOTS: Array[int] = [Slot.HEAD, Slot.TORSO, Slot.LEGS, Slot.BRACE]
## Paper-doll right column.
const GEAR_SLOTS: Array[int] = [Slot.MAIN_HAND, Slot.OFF_HAND, Slot.RING_1, Slot.RING_2, Slot.AMULET]
## Paper-doll consumable row (under the torso).
const CONSUMABLE_SLOTS: Array[int] = [Slot.CONSUMABLE_1, Slot.CONSUMABLE_2, Slot.CONSUMABLE_3, Slot.CONSUMABLE_4]
const ALL_SLOTS: Array[int] = [
	Slot.HEAD, Slot.TORSO, Slot.LEGS, Slot.BRACE,
	Slot.MAIN_HAND, Slot.OFF_HAND, Slot.RING_1, Slot.RING_2, Slot.AMULET,
	Slot.CONSUMABLE_1, Slot.CONSUMABLE_2, Slot.CONSUMABLE_3, Slot.CONSUMABLE_4,
]

## Outcome of an equip attempt.
class Result extends RefCounted:
	var ok: bool = false
	## Slot the item ended up in (-1 when it failed).
	var slot: int = -1
	## Items that were taken off to make room, in the order they came off. Caller owns them now.
	var displaced: Array = []
	## Why it failed; empty on success.
	var reason: String = ""

## The wearer's stat mods (STR, DEX, CON, INT, WIS), set by Unit. Empty = no stat check (demo / tests).
var mods: Array[int] = []
var _items: Dictionary = {}   # Slot -> Item or null
var _states: Dictionary = {}  # Slot -> SlotState

func _init() -> void:
	for s in ALL_SLOTS:
		_items[s] = null
		_states[s] = SlotState.UNLOCKED

# --- static lookups -----------------------------------------------------------

static func slot_label(slot: int) -> String:
	match slot:
		Slot.HEAD: return "Head"
		Slot.TORSO: return "Torso"
		Slot.LEGS: return "Legs"
		Slot.BRACE: return "Brace"
		Slot.MAIN_HAND: return "Main Hand"
		Slot.OFF_HAND: return "Off Hand"
		Slot.RING_1: return "Ring 1"
		Slot.RING_2: return "Ring 2"
		Slot.AMULET: return "Amulet"
		Slot.CONSUMABLE_1: return "Consumable 1"
		Slot.CONSUMABLE_2: return "Consumable 2"
		Slot.CONSUMABLE_3: return "Consumable 3"
		Slot.CONSUMABLE_4: return "Consumable 4"
	return "?"

static func is_ring_slot(slot: int) -> bool:
	return slot == Slot.RING_1 or slot == Slot.RING_2

static func is_consumable_slot(slot: int) -> bool:
	return CONSUMABLE_SLOTS.has(slot)

## The one slot an armor piece or amulet fits. NONE for weapons, rings and consumables (they have a choice).
static func fixed_slot_for(item_type: int) -> int:
	match item_type:
		Item.ItemType.HEAD: return Slot.HEAD
		Item.ItemType.TORSO: return Slot.TORSO
		Item.ItemType.LEGS: return Slot.LEGS
		Item.ItemType.BRACE: return Slot.BRACE
		Item.ItemType.AMULET: return Slot.AMULET
	return Slot.NONE

# --- queries ------------------------------------------------------------------

## "" when the wearer's stats meet the item's requirements, else why not ("Needs STR 2 (has 1).").
func requirement_error(item: Item) -> String:
	if item == null or mods.is_empty():
		return ""
	var reqs := item.requirements()
	for i in reqs.size():
		if i < mods.size() and mods[i] < reqs[i]:
			return "%s needs %s %d (has %d)." % [item.display_name, Item.STAT_LABELS[i], reqs[i], mods[i]]
	return ""

func meets_requirements(item: Item) -> bool:
	return requirement_error(item) == ""

func get_item(slot: int) -> Item:
	return _items.get(slot)

func get_state(slot: int) -> int:
	return _states.get(slot, SlotState.UNLOCKED)

func is_locked(slot: int) -> bool:
	return get_state(slot) == SlotState.LOCKED

## Could this item go in this slot (ignoring what is already there)?
## A locked Off Hand still accepts: equipping into it bumps the two-hander (Rule 3).
## A two-hander accepts MainHand or OffHand because Rule 1 redirects it to MainHand.
func can_equip(item: Item, slot: int) -> bool:
	if item == null or not ALL_SLOTS.has(slot):
		return false
	if item.is_weapon():
		match item.handedness:
			Item.Handedness.TWO_HANDED:
				return slot == Slot.MAIN_HAND or slot == Slot.OFF_HAND
			Item.Handedness.OFF_HAND_ONLY:
				return slot == Slot.OFF_HAND
		return slot == Slot.MAIN_HAND or slot == Slot.OFF_HAND
	if item.item_type == Item.ItemType.RING:
		return is_ring_slot(slot)
	if item.item_type == Item.ItemType.CONSUMABLE:
		return is_consumable_slot(slot)
	return fixed_slot_for(item.item_type) == slot

## Where the next ring goes: Ring 1 if empty, else Ring 2 if empty,
## else (both full) the ring slot the player has selected.
func pick_ring_slot(selected_ring: int = Slot.RING_1) -> int:
	if _items[Slot.RING_1] == null:
		return Slot.RING_1
	if _items[Slot.RING_2] == null:
		return Slot.RING_2
	return selected_ring if is_ring_slot(selected_ring) else Slot.RING_1

## Where the next consumable goes: the first empty consumable slot, else `target_slot` if it is one
## (replacing what is there), else Consumable 1.
func pick_consumable_slot(target_slot: int = Slot.NONE) -> int:
	if is_consumable_slot(target_slot) and _items[target_slot] == null:
		return target_slot
	for s in CONSUMABLE_SLOTS:
		if _items[s] == null:
			return s
	return target_slot if is_consumable_slot(target_slot) else Slot.CONSUMABLE_1

## Every attack the worn weapons grant.
func granted_abilities() -> Array[Ability]:
	var out: Array[Ability] = []
	for s in ALL_SLOTS:
		var item: Item = _items[s]
		if item != null and item.ability != null:
			out.append(item.ability)
	return out

## Sum of one defense property ("physical_armor" or "magic_barrier")
## over everything worn.
func total_defense(property: StringName) -> float:
	var total := 0.0
	for s in ALL_SLOTS:
		var item: Item = _items[s]
		if item != null:
			total += float(item.get(property))
	return total

## What equipping `item` would do, without doing it: the same rules run on a throwaway copy, so the answer
## (ok, reason, displaced) can never drift from try_equip. Lets the UI check there is bag room for what comes off.
func preview(item: Item, target_slot: int = Slot.NONE, selected_ring: int = Slot.RING_1) -> Result:
	var copy = get_script().new()
	copy.mods = mods
	copy._items = _items.duplicate()
	copy._states = _states.duplicate()
	return copy.try_equip(item, target_slot, selected_ring)

# --- equip / unequip ----------------------------------------------------------

## Generic entry point. Weapons go through try_equip_weapon, rings through the dynamic ring rule,
## consumables to the first free consumable slot (or the one dropped on),
## everything else to its fixed slot.
## target_slot: where the player dropped it, or NONE for "just equip it" (double-click).
## A ring dropped on a specific ring slot goes there; otherwise the dynamic rule picks the slot.
## selected_ring: which ring slot is highlighted, used only when both rings are full.
func try_equip(item: Item, target_slot: int = Slot.NONE, selected_ring: int = Slot.RING_1) -> Result:
	if item == null:
		return _fail("No item.")
	var req_error := requirement_error(item)
	if req_error != "":
		return _fail(req_error)
	if item.is_weapon():
		return try_equip_weapon(item, target_slot)
	if item.item_type == Item.ItemType.RING:
		var ring_slot: int = target_slot if is_ring_slot(target_slot) else pick_ring_slot(selected_ring)
		return _place(item, ring_slot)
	if item.item_type == Item.ItemType.CONSUMABLE:
		return _place(item, pick_consumable_slot(target_slot))
	var fixed: int = fixed_slot_for(item.item_type)
	if target_slot != Slot.NONE and target_slot != fixed:
		return _fail("%s does not fit the %s slot." % [item.display_name, slot_label(target_slot)])
	return _place(item, fixed)

## Weapon conflict rules. target_slot NONE means "default": MainHand for one-handers,
## OffHand for off-hand-only items. A two-hander ignores target_slot entirely.
func try_equip_weapon(weapon: Item, target_slot: int) -> Result:
	if weapon == null or not weapon.is_weapon():
		return _fail("Not a weapon.")
	var result := Result.new()

	# Rule 1: two-handed. Forced to MainHand, clears both hands, locks OffHand.
	if weapon.handedness == Item.Handedness.TWO_HANDED:
		result.slot = Slot.MAIN_HAND
		_take_into(result, Slot.MAIN_HAND)
		_take_into(result, Slot.OFF_HAND)
		_set_item(Slot.MAIN_HAND, weapon)
		_set_state(Slot.OFF_HAND, SlotState.LOCKED)
		result.ok = true
		return result

	var dest: int = target_slot
	if weapon.handedness == Item.Handedness.OFF_HAND_ONLY:
		if dest == Slot.NONE:
			dest = Slot.OFF_HAND
		if dest != Slot.OFF_HAND:
			return _fail("%s can only go in the Off Hand." % weapon.display_name)
	else:
		if dest == Slot.NONE:
			dest = Slot.MAIN_HAND
		if dest != Slot.MAIN_HAND and dest != Slot.OFF_HAND:
			return _fail("%s needs a hand slot." % weapon.display_name)

	# Rules 2 and 3: if MainHand holds a two-hander, it comes off and OffHand unlocks first.
	var main: Item = _items[Slot.MAIN_HAND]
	if main != null and main.is_two_handed():
		_take_into(result, Slot.MAIN_HAND)
		_set_state(Slot.OFF_HAND, SlotState.UNLOCKED)
	# Then equip, replacing whatever is in the destination.
	_take_into(result, dest)
	_set_item(dest, weapon)
	result.slot = dest
	result.ok = true
	return result

## Take the item out of a slot and hand it back (null if the slot was empty).
## Removing a two-hander unlocks the Off Hand.
func unequip(slot: int) -> Item:
	var item: Item = _items.get(slot)
	if item == null:
		return null
	_set_item(slot, null)
	if slot == Slot.MAIN_HAND and item.is_two_handed():
		_set_state(Slot.OFF_HAND, SlotState.UNLOCKED)
	return item

# --- internals ----------------------------------------------------------------

func _place(item: Item, slot: int) -> Result:
	if not can_equip(item, slot):
		return _fail("%s does not fit the %s slot." % [item.display_name, slot_label(slot)])
	var result := Result.new()
	_take_into(result, slot)
	_set_item(slot, item)
	result.slot = slot
	result.ok = true
	return result

func _fail(reason: String) -> Result:
	var result := Result.new()
	result.reason = reason
	return result

## Move whatever is in `slot` onto result.displaced.
func _take_into(result: Result, slot: int) -> void:
	var old: Item = _items[slot]
	if old == null:
		return
	_set_item(slot, null)
	result.displaced.append(old)

func _set_item(slot: int, item: Item) -> void:
	if _items[slot] == item:
		return
	_items[slot] = item
	slot_changed.emit(slot)

func _set_state(slot: int, state: int) -> void:
	if _states[slot] == state:
		return
	_states[slot] = state
	slot_changed.emit(slot)
