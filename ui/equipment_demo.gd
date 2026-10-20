extends Control
## Playable sandbox for the paper doll. Run scenes/equipment_demo.tscn (F6).
## Click a bag item to equip it, or drag it onto a slot. Right-click a slot to unequip.
## Left-click a ring slot to choose which ring the next one replaces when both are full.

const Equipment = preload("res://scripts/inventory/equipment.gd")
const Item = preload("res://scripts/inventory/item.gd")
const PaperDollScript = preload("res://ui/paper_doll.gd")

const ITEM_PATHS: Array[String] = [
	"res://data/items/iron_helm.tres",
	"res://data/items/iron_cuirass.tres",
	"res://data/items/iron_greaves.tres",
	"res://data/items/leather_brace.tres",
	"res://data/items/longsword.tres",
	"res://data/items/shortsword.tres",
	"res://data/items/greataxe.tres",
	"res://data/items/quarterstaff.tres",
	"res://data/items/shortbow.tres",
	"res://data/items/tower_shield.tres",
	"res://data/items/spellbook.tres",
	"res://data/items/copper_ring.tres",
	"res://data/items/silver_ring.tres",
	"res://data/items/jade_ring.tres",
	"res://data/items/sun_amulet.tres",
	"res://data/items/health_potion.tres",
	"res://data/items/mana_potion.tres",
]

@onready var _doll: PaperDollScript = %PaperDoll
@onready var _bag_list: VBoxContainer = %Bag
@onready var _log: Label = %Log

var _equipment := Equipment.new()
var _bag: Array[Item] = []

func _ready() -> void:
	for path in ITEM_PATHS:
		_bag.append(load(path))
	_doll.bind(_equipment)
	_doll.equip_attempted.connect(_on_equip_attempted)
	_doll.unequipped.connect(_on_unequipped)
	_rebuild_bag()
	_log.text = "Ready."

func _rebuild_bag() -> void:
	for child in _bag_list.get_children():
		child.queue_free()
	for item in _bag:
		var button := Button.new()
		button.text = "%s  (%s)" % [item.display_name, item.kind_label()]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = item.description
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
		_log.text = "Can't equip %s: %s" % [item.display_name, result.reason]
		return
	_bag.erase(item)
	var names: Array[String] = []
	for d: Item in result.displaced:
		_bag.append(d)
		names.append(d.display_name)
	var text := "Equipped %s -> %s." % [item.display_name, Equipment.slot_label(result.slot)]
	if not names.is_empty():
		text += " Returned to bag: %s." % ", ".join(names)
	_log.text = text
	_rebuild_bag()

func _on_unequipped(item: Item, slot: int) -> void:
	_bag.append(item)
	_log.text = "Unequipped %s from %s." % [item.display_name, Equipment.slot_label(slot)]
	_rebuild_bag()
