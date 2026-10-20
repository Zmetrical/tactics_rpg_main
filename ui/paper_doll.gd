extends PanelContainer
## Paper-doll equipment panel, laid out like Diablo 2's: a tall Main Hand slot on the left and a tall Off Hand slot
## on the right, Head over Torso in the middle with the Amulet beside the head and a vertical Ring pair right of the
## torso, and a bottom row of Brace (the gloves spot), four Consumable slots under the torso, and Legs (the boots
## spot). LAYOUT holds every slot's rectangle in pixels.
## Slots are 44 px cells with 16 px gutters; a worn item fills its slot (see equipment_slot.gd), same rule everywhere.
##
## Owns no rules. Clicks and drops become Equipment.try_equip / unequip calls, and the cells
## redraw from Equipment.slot_changed. Displaced items are reported, never kept: the owner of
## the bag listens to equip_attempted / unequipped and files them.
##
## Left-click a ring slot to select it: when both rings are full, the next ring replaces it.
## Right-click any slot to unequip. Drop {"item": Item} on a slot to equip.

signal equip_attempted(item: Item, result)
signal unequipped(item: Item, slot: int)
## A right-click unequip was refused (unequip_gate gave a reason).
signal unequip_blocked(reason: String)

const Equipment = preload("res://scripts/inventory/equipment.gd")
const Item = preload("res://scripts/inventory/item.gd")
const SlotScene = preload("res://ui/equipment_slot.tscn")
const SlotView = preload("res://ui/equipment_slot.gd")
const Unit = preload("res://scripts/battle/unit.gd")

## Slot -> Rect2(x, y, w, h) inside the 396 x 332 doll area. Built from the bag's 44 px cell: 2 cells wide for
## the big slots, 16 px between groups, 4 px inside one. Columns, left to right: Main Hand (0), Rings (104),
## Head + Torso (152), Amulet (248), Off Hand (308). The consumable row spans Rings..Amulet under the Torso.
const LAYOUT := {
	Equipment.Slot.MAIN_HAND: Rect2(0, 0, 88, 228),
	Equipment.Slot.RING_1: Rect2(244, 96, 44, 44),
	Equipment.Slot.RING_2: Rect2(244, 144, 44, 44),
	Equipment.Slot.HEAD: Rect2(152, 0, 88, 88),
	Equipment.Slot.TORSO: Rect2(152, 96, 88, 132),
	Equipment.Slot.AMULET: Rect2(244, 44, 44, 44),
	Equipment.Slot.OFF_HAND: Rect2(308, 0, 88, 228),
	Equipment.Slot.BRACE: Rect2(0, 244, 88, 88),
	Equipment.Slot.CONSUMABLE_1: Rect2(104, 266, 44, 44),
	Equipment.Slot.CONSUMABLE_2: Rect2(152, 266, 44, 44),
	Equipment.Slot.CONSUMABLE_3: Rect2(200, 266, 44, 44),
	Equipment.Slot.CONSUMABLE_4: Rect2(248, 266, 44, 44),
	Equipment.Slot.LEGS: Rect2(308, 244, 88, 88),
}

@onready var _doll: Control = %Doll

var _equipment: Equipment = null
var _views: Dictionary = {}  # Slot -> SlotView
var _selected_ring: int = Equipment.Slot.RING_1
var _read_only: bool = false
## (item, target_slot, selected_ring) -> String. Set by the owner of the bag: "" = go ahead, otherwise why not
## (for example no bag room for what would come off). A refusal is reported through equip_attempted.
var equip_gate: Callable = Callable()
## (item) -> String. Same idea for taking an item off with a right-click.
var unequip_gate: Callable = Callable()

func _ready() -> void:
	for s in Equipment.ALL_SLOTS:
		_add_slot(s)
	_refresh_all()

## Show this unit's equipment. Safe to call before the panel is in the tree.
func bind(equipment: Equipment) -> void:
	if _equipment != null:
		_equipment.slot_changed.disconnect(_refresh_slot)
	_equipment = equipment
	if _equipment != null:
		_equipment.slot_changed.connect(_refresh_slot)
	_refresh_all()

## Preview mode: slots show gear but ignore clicks and drops (used for enemy units).
func set_read_only(value: bool) -> void:
	_read_only = value
	_refresh_all()

## Equip as if the player dropped `item` on target_slot (NONE = double-click: let the rules pick).
func equip(item: Item, target_slot: int = Equipment.Slot.NONE) -> void:
	if _equipment == null or _read_only:
		return
	if equip_gate.is_valid():
		var why: String = equip_gate.call(item, target_slot, _selected_ring)
		if why != "":
			var refused := Equipment.Result.new()
			refused.reason = why
			equip_attempted.emit(item, refused)
			return
	var result: Equipment.Result = _equipment.try_equip(item, target_slot, _selected_ring)
	# The next ring replaces the one just filled only if the player re-selects; follow the new ring.
	if result.ok and Equipment.is_ring_slot(result.slot):
		_set_selected_ring(result.slot)
	equip_attempted.emit(item, result)

func _add_slot(slot: int) -> void:
	var view: SlotView = SlotScene.instantiate()
	_doll.add_child(view)
	var rect: Rect2 = LAYOUT[slot]
	view.custom_minimum_size = Vector2.ZERO
	view.position = rect.position
	view.size = rect.size
	view.compact = rect.size.x < 60.0
	view.set_slot(slot)
	view.can_accept = _can_accept
	view.can_drag = func() -> bool: return not _read_only
	view.clicked.connect(_on_slot_clicked)
	view.item_dropped.connect(_on_item_dropped)
	_views[slot] = view

func _can_accept(item: Item, slot: int) -> bool:
	return not _read_only and _equipment != null and _equipment.can_equip(item, slot)

func _on_slot_clicked(slot: int, button: int) -> void:
	if _read_only:
		return
	if button == MOUSE_BUTTON_LEFT:
		if Equipment.is_ring_slot(slot):
			_set_selected_ring(slot)
	elif button == MOUSE_BUTTON_RIGHT and _equipment != null:
		var worn: Item = _equipment.get_item(slot)
		if worn == null:
			return
		if unequip_gate.is_valid():
			var why: String = unequip_gate.call(worn)
			if why != "":
				unequip_blocked.emit(why)
				return
		var item: Item = _equipment.unequip(slot)
		if item != null:
			unequipped.emit(item, slot)

func _on_item_dropped(slot: int, item: Item) -> void:
	equip(item, slot)

func _set_selected_ring(slot: int) -> void:
	var old := _selected_ring
	_selected_ring = slot
	_refresh_slot(old)
	_refresh_slot(slot)

func _refresh_all() -> void:
	for s in _views:
		_refresh_slot(s)

func _refresh_slot(slot: int) -> void:
	var view: SlotView = _views.get(slot)
	if view == null:
		return
	var item: Item = null
	var locked := false
	if _equipment != null:
		item = _equipment.get_item(slot)
		locked = _equipment.is_locked(slot)
	view.show_contents(item, locked)
	view.set_selected(slot == _selected_ring and not _read_only)
