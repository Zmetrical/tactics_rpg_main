extends Control
## The bag as a Diablo 2 style grid: every item is a box covering its footprint of cells.
##
##   drag an item        move it in the grid, or drop it on a paper-doll slot to equip it
##   drag a worn item    drop it here to put it back (the paper-doll slot starts that drag)
##   right-click item    quick equip (right_clicked; the window decides)
##   hover               tooltip card
##
## While a drag is over the grid the footprint is tinted green (fits) or red (does not).
## Draws straight from the Inventory and redraws on its `changed`. Owns no rules: a drop is reported
## through item_dropped and the window decides what it means.

## A drop to apply. payload = {"item", "placement"} from this grid or {"item", "slot"} from the paper doll.
signal item_dropped(payload: Dictionary, pos: Vector2i)
signal right_clicked(placement: Inventory.Placement)
## A drag started from an item in this grid, and the moment it ended (dropped anywhere or cancelled).
signal drag_started(placement: Inventory.Placement)
signal drag_ended

const AbilityText = preload("res://ui/ability_text.gd")
const Inventory = preload("res://scripts/inventory/inventory.gd")
const Item = preload("res://scripts/inventory/item.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const TooltipCard = preload("res://ui/hud/tooltip_card.gd")

const CELL := 44
const FONT := 16

var _bag: Inventory = null
var _tip_item: Item = null
var _dragging: Inventory.Placement = null
var _hover_pos := Inventory.NO_SPACE
var _hover_size := Vector2i.ONE
var _hover_ok := false

func _ready() -> void:
	custom_minimum_size = Vector2(Inventory.COLS * CELL, Inventory.ROWS * CELL)
	mouse_filter = Control.MOUSE_FILTER_STOP

func bind(bag: Inventory) -> void:
	if _bag != null and _bag.changed.is_connected(queue_redraw):
		_bag.changed.disconnect(queue_redraw)
	_bag = bag
	if _bag != null:
		_bag.changed.connect(queue_redraw)
	queue_redraw()

# --- drawing --------------------------------------------------------------------

func _draw() -> void:
	var grid := Rect2(Vector2.ZERO, Vector2(Inventory.COLS * CELL, Inventory.ROWS * CELL))
	draw_rect(grid, Palette.BG)
	# Lines are 2 px filled rects, not 1 px draw_line: the UI is scaled from 1920x1080, and a 1 px line lands on
	# uneven pixels at fractional scale, so the cells looked unequal.
	for x in range(Inventory.COLS + 1):
		draw_rect(Rect2(x * CELL - 1, 0, 2, grid.size.y), Palette.INK_LIGHT)
	for y in range(Inventory.ROWS + 1):
		draw_rect(Rect2(0, y * CELL - 1, grid.size.x, 2), Palette.INK_LIGHT)
	if _bag == null:
		return
	for p in _bag.placements():
		_draw_item(p)
	if _hover_pos != Inventory.NO_SPACE:
		var tint := Palette.HP_GREEN if _hover_ok else Palette.HP_RED
		tint.a = 0.45
		var box := Rect2(Vector2(_hover_pos * CELL), Vector2(_hover_size * CELL)).intersection(grid)
		draw_rect(box, tint)

func _draw_item(p: Inventory.Placement) -> void:
	var box := Rect2(Vector2(p.pos * CELL), Vector2(p.size() * CELL)).grow(-1.0)
	var lifted := p == _dragging
	draw_rect(box, Palette.INK_LIGHT if lifted else Palette.INK)
	draw_rect(box.grow(-2.0), Palette.BG if lifted else Palette.PANEL)
	if p.item.icon != null:
		draw_texture_rect(p.item.icon, box.grow(-4.0), false, Color(1, 1, 1, 0.4 if lifted else 1.0))
		return
	# No icon art yet: the item's first two letters.
	var font := get_theme_default_font()
	var text := p.item.display_name.substr(0, 2).to_upper()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT)
	var at := box.get_center() + Vector2(-text_size.x * 0.5, font.get_ascent(FONT) - text_size.y * 0.5)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, Palette.INK_LIGHT if lifted else Palette.INK)

# --- input ----------------------------------------------------------------------

func _cell_at(at: Vector2) -> Vector2i:
	return Vector2i(int(floorf(at.x / CELL)), int(floorf(at.y / CELL)))

func _gui_input(event: InputEvent) -> void:
	if _bag == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var p := _bag.placement_at(_cell_at(event.position))
		if p != null:
			right_clicked.emit(p)
			accept_event()

func _get_drag_data(at_position: Vector2) -> Variant:
	if _bag == null:
		return null
	var p := _bag.placement_at(_cell_at(at_position))
	if p == null:
		return null
	_dragging = p
	drag_started.emit(p)
	set_drag_preview(_make_preview(p.item))
	queue_redraw()
	return {"item": p.item, "placement": p}

## The dragged item's footprint under the mouse, centred on it.
func _make_preview(item: Item) -> Control:
	var size := Vector2(item.bag_size() * CELL)
	var holder := Control.new()
	var box := Panel.new()
	box.size = size
	box.position = -size * 0.5
	box.modulate.a = 0.8
	var label := Label.new()
	label.text = item.display_name
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	holder.add_child(box)
	return holder

func _drop_pos(at: Vector2, size: Vector2i) -> Vector2i:
	return _cell_at(at) - size / 2

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if _bag == null or not (data is Dictionary) or not (data.get("item") is Item):
		return false
	var item: Item = data["item"]
	_hover_size = item.bag_size()
	_hover_pos = _drop_pos(at_position, _hover_size)
	_hover_ok = _bag.can_place(item, _hover_pos, data.get("placement"))
	queue_redraw()
	return _hover_ok

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var item: Item = data["item"]
	item_dropped.emit(data, _drop_pos(at_position, item.bag_size()))

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_hover_pos = Inventory.NO_SPACE
		queue_redraw()
	if what == NOTIFICATION_DRAG_END and _dragging != null:
		_dragging = null
		drag_ended.emit()

# --- tooltip --------------------------------------------------------------------

func _get_tooltip(at_position: Vector2) -> String:
	_tip_item = null
	if _bag == null:
		return ""
	var p := _bag.placement_at(_cell_at(at_position))
	if p == null:
		return ""
	_tip_item = p.item
	return p.item.display_name

func _make_custom_tooltip(_for_text: String) -> Object:
	if _tip_item == null:
		return null
	return TooltipCard.build(tip_for(_tip_item))

static func tip_for(item: Item) -> Dictionary:
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
		"body": item.description,
		"sections": sections,
	}
