extends PanelContainer
## One paper-doll cell: icon, name (or the slot's own name when empty), lock overlay.
## Emits intent only; paper_doll.gd decides what a click or a drop means.

signal clicked(slot: int, button: int)
signal item_dropped(slot: int, item: Item)

const Equipment = preload("res://scripts/inventory/equipment.gd")
const Item = preload("res://scripts/inventory/item.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")

var slot: int = Equipment.Slot.NONE
## (item, slot) -> bool. Set by the paper doll; without it nothing can be dropped here.
var can_accept: Callable = Callable()
## () -> bool. Set by the paper doll: false in a read-only preview, so the worn item cannot be dragged out.
var can_drag: Callable = Callable()
## One cell wide: shows two letters instead of a name (the tooltip has the full text).
var compact := false

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label
@onready var _lock: Label = %Lock

var _item: Item = null
var _locked: bool = false
var _selected: bool = false
## While a bag item is dragged over this cell: 0 = none, 1 = it can be equipped here (green), -1 = it cannot (red).
var _drop_hint: int = 0

func _ready() -> void:
	_refresh()

func set_slot(p_slot: int) -> void:
	slot = p_slot
	if is_node_ready():
		_refresh()

func show_contents(item: Item, locked: bool) -> void:
	_item = item
	_locked = locked
	if is_node_ready():
		_refresh()

## Highlights the cell (used for the ring slot that the next ring will replace).
func set_selected(value: bool) -> void:
	_selected = value
	if is_node_ready():
		_refresh()

func _refresh() -> void:
	_icon.texture = _item.icon if _item != null else null
	_label.text = _label_text()
	_label.modulate.a = 1.0 if _item != null else 0.5
	queue_redraw()
	_lock.visible = _locked
	modulate.a = 0.55 if _locked else 1.0
	tooltip_text = _tooltip()
	if _selected:
		add_theme_stylebox_override("panel", _selected_style())
	else:
		remove_theme_stylebox_override("panel")

## A worn item shows its first two letters (nothing when it has an icon), like in the bag grid; the tooltip has the
## name. An empty slot shows its own name, or two letters in a one-cell slot ("Ring 1" -> "R1").
func _label_text() -> String:
	# A locked slot shows only the lock overlay, not its own name.
	if _locked:
		return ""
	if _item != null:
		return "" if _item.icon != null else _item.display_name.substr(0, 2).to_upper()
	var full := Equipment.slot_label(slot)
	if not compact:
		return full
	var words := full.split(" ", false)
	return (words[0].substr(0, 1) + (words[1] if words.size() > 1 else words[0].substr(1, 1))).to_upper()

## Gap between the slot edge and a worn item's box.
const EQUIPPED_INSET := 4.0

## The worn item as a box that fills its slot, inset by EQUIPPED_INSET on every side. One rule for every slot,
## whatever the item's bag footprint: the box is as tall and wide as the slot allows (Head and Torso set the look).
func _draw() -> void:
	if _item != null:
		var rect := Rect2(Vector2(EQUIPPED_INSET, EQUIPPED_INSET), size - Vector2(EQUIPPED_INSET, EQUIPPED_INSET) * 2.0)
		draw_rect(rect, Palette.INK)
		draw_rect(rect.grow(-2.0), Palette.PANEL)
	if _drop_hint != 0:
		var tint := Palette.HP_GREEN if _drop_hint > 0 else Palette.HP_RED
		tint.a = 0.45
		draw_rect(Rect2(Vector2.ZERO, size), tint)

func _set_drop_hint(value: int) -> void:
	if _drop_hint == value:
		return
	_drop_hint = value
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_set_drop_hint(0)

func _tooltip() -> String:
	if _item == null:
		return "%s (empty)" % Equipment.slot_label(slot)
	var text := "%s\n%s" % [_item.display_name, _item.kind_label()]
	if _item.defense_summary() != "":
		text += "\n" + _item.defense_summary()
	if _item.requirement_summary() != "":
		text += "\nRequires " + _item.requirement_summary()
	if _item.description != "":
		text += "\n" + _item.description
	return text

func _selected_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL
	sb.border_color = Palette.INK
	sb.set_border_width_all(4)
	sb.set_content_margin_all(6)
	return sb

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicked.emit(slot, event.button_index)
		accept_event()

# Drag source: the worn item, to put it back in the bag. Data is {"item": Item, "slot": int}.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _item == null or _locked or not can_drag.is_valid() or not can_drag.call():
		return null
	var preview := Label.new()
	preview.text = _item.display_name
	set_drag_preview(preview)
	return {"item": _item, "slot": slot}

# Drop target. Drag data is {"item": Item} from the bag; an item still worn (it has a "slot") is not equipped again.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not data.has("item") or not (data["item"] is Item) or data.has("slot"):
		return false
	var ok: bool = can_accept.is_valid() and can_accept.call(data["item"], slot)
	_set_drop_hint(1 if ok else -1)
	return ok

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_set_drop_hint(0)
	item_dropped.emit(slot, data["item"])
