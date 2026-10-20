class_name InventoryDock
extends PanelContainer
## Docked inventory: the current unit's paper doll plus the party bag, in a fixed-size box that
## scrolls. Same rules as the equipment window (it edits Equipment and the shared bag array),
## shown right on the HUD. Read-only when the unit is not yours or it is not your turn.

signal equipment_changed(unit: Unit)

const Equipment = preload("res://scripts/inventory/equipment.gd")
const Item = preload("res://scripts/inventory/item.gd")
const PaperDollScript = preload("res://ui/paper_doll.gd")
const Unit = preload("res://scripts/battle/unit.gd")

@onready var _status: Label = %Status
@onready var _doll: PaperDollScript = %PaperDoll
@onready var _bag_title: Label = %BagTitle
@onready var _bag_list: VBoxContainer = %BagList

var _unit: Unit = null
var _bag: Array = []
var _editable: bool = false

func _ready() -> void:
	# The dock is narrow: the doll's big portrait is dropped, only the slot columns stay.
	(_doll.get_node("%Portrait") as Control).visible = false
	_doll.equip_attempted.connect(_on_equip_attempted)
	_doll.unequipped.connect(_on_unequipped)

## Call whenever the unit, the bag or the editable state may have changed.
func show_unit(unit: Unit, bag: Array, editable: bool) -> void:
	_unit = unit
	_bag = bag
	_editable = editable and unit != null
	visible = unit != null
	if unit == null:
		_doll.bind(null)
		return
	_doll.bind(unit.equipment)
	_doll.set_unit(unit)
	_doll.set_read_only(not _editable)
	_bag_title.visible = _editable
	_bag_list.visible = _editable
	if not _editable:
		_status.text = "Gear can be changed on your turn."
	elif _status.text == "" or _status.text.begins_with("Gear can"):
		_status.text = "Click a bag item to equip it, or drag it onto a slot. Right-click a slot to unequip."
	_rebuild_bag()

func _rebuild_bag() -> void:
	for child in _bag_list.get_children():
		_bag_list.remove_child(child)
		child.queue_free()
	if not _editable:
		return
	if _bag.is_empty():
		var empty := Label.new()
		empty.text = "The bag is empty."
		_bag_list.add_child(empty)
		return
	for item: Item in _bag:
		var button := Button.new()
		button.text = "%s  (%s)" % [item.display_name, item.kind_label()]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = item.description
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_doll.equip.bind(item))
		button.set_drag_forwarding(_drag_item.bind(item, button), Callable(), Callable())
		_bag_list.add_child(button)

func _drag_item(_at_position: Vector2, item: Item, source: Control) -> Variant:
	var preview := Label.new()
	preview.text = item.display_name
	source.set_drag_preview(preview)
	return {"item": item}

func _on_equip_attempted(item: Item, result) -> void:
	if not result.ok:
		_status.text = "Can't equip %s: %s" % [item.display_name, result.reason]
		return
	_bag.erase(item)
	var names: Array[String] = []
	for d: Item in result.displaced:
		_bag.append(d)
		names.append(d.display_name)
	var text := "%s -> %s." % [item.display_name, Equipment.slot_label(result.slot)]
	if not names.is_empty():
		text += " Back to bag: %s." % ", ".join(names)
	_status.text = text
	_after_change()

func _on_unequipped(item: Item, slot: int) -> void:
	_bag.append(item)
	_status.text = "%s removed from %s." % [item.display_name, Equipment.slot_label(slot)]
	_after_change()

func _after_change() -> void:
	_rebuild_bag()
	equipment_changed.emit(_unit)
