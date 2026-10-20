extends VBoxContainer
## The bottom hotbar, 2 rows tall, in three boxes drawn with the unit panel's frame. Left to right: gear box, main box, end box.
##   (listed below in the order they are built)
##   main box     hands (Main Hand / Off Hand side by side) | weapon actions (2 cols) | spells (6 cols),
##                with two tabs on top, each its own container with no bottom edge: the taller AP bar over
##                hands + weapon actions, the shorter movement bar over the spells
##   end box      END TURN plus small buttons (Esc, equipment, zoom + / -)
##   gear box     a row of empty slots on top, a horizontal divider, then
##                armor (2 x 2: Head / Torso / Legs / Brace) | rings + amulet (Ring 1 / Ring 2 / Amulet)
## Sections are split by ornate dividers (hud_divider.gd); boxes, slots and buttons are flat (hud_style.gd).
##
## There is no description box: hovering any slot shows a tooltip card (tooltip_card.gd).
## Clicking an ability picks it; clicking a worn item opens the equipment window.
## Keyboard / controller: navigate() moves a cursor over the usable abilities, accept() picks.
##
## Display and intent only. BattleUI feeds it UnitView.hotbar() data and decides what a choice means.

signal ability_chosen(action_id: int)
signal gear_chosen(slot: int)
signal end_turn_pressed
signal end_turn_answered(yes: bool)
signal back_pressed
signal inventory_pressed
signal zoom_requested(zoom_in: bool)

## What the bar lets the player do right now.
##   READY   everything
##   AIMING  abilities (switch what you aim), Esc; not End Turn or equipment
##   CONFIRM only Esc (and YES / NO while the end-turn question is up)
##   LOCKED  nothing (text playing, equipment window open); tooltips still work
enum Mode { READY, AIMING, CONFIRM, LOCKED }

const Palette = preload("res://ui/theme/gbc_palette.gd")
const Equipment = preload("res://scripts/inventory/equipment.gd")
const HotbarSlot = preload("res://ui/hud/hotbar_slot.gd")
const MovementBar = preload("res://ui/hud/movement_bar.gd")
const ApBar = preload("res://ui/hud/ap_bar.gd")
const HudStyle = preload("res://ui/hud/hud_style.gd")
const HudDivider = preload("res://ui/hud/hud_divider.gd")

const ROWS := 2
const CELL := 44.0
const GAP := 3
const WEAPON_COLS := 2
const SPELL_COLS := 6
const ARMOR_COLS := 2
const JEWELRY_COLS := 2
## The extra row on top of the gear box: empty slots, one group over the armor and one over the rings + amulet.
const SPARE_COLS_LEFT := ARMOR_COLS
const SPARE_COLS_RIGHT := JEWELRY_COLS
## Space above and below the horizontal divider inside the gear box.
const GEAR_ROW_GAP := 4
## A hand slot covers 2 x 2 cells, so it is as tall as the 2 rows beside it.
const HAND_SIZE := Vector2(CELL * 2.0 + GAP, CELL * 2.0 + GAP)
## Gap between sections. The two tabs split over the middle divider, so this must leave room for both tabs' side margins:
## 2 * SECTION_GAP + DIVIDER_W > 2 * HudStyle.MARGIN_X.
const SECTION_GAP := 10
const DIVIDER_W := 7
## Width of hands + weapon actions, so the AP bar ends exactly where the spells begin.
const LEFT_W := HAND_SIZE.x * 2.0 + GAP + float(SECTION_GAP * 2 + DIVIDER_W) + CELL * WEAPON_COLS + GAP * (WEAPON_COLS - 1)

const HAND_SLOTS: Array[int] = [Equipment.Slot.MAIN_HAND, Equipment.Slot.OFF_HAND]
const ARMOR_SLOTS: Array[int] = [Equipment.Slot.HEAD, Equipment.Slot.TORSO, Equipment.Slot.LEGS, Equipment.Slot.BRACE]
const JEWELRY_SLOTS: Array[int] = [Equipment.Slot.RING_1, Equipment.Slot.RING_2, Equipment.Slot.AMULET]

var mode: Mode = Mode.LOCKED

var _move_bar: Control
var _ap_bar: Control
var _hand_slots: Array = []
var _weapon_slots: Array = []
var _spell_slots: Array = []
var _armor_slots: Array = []
var _jewelry_slots: Array = []
var _spare_slots: Array = []   # the empty row on top of the gear box; never filled, never clickable
var _action_slots: Array = []
var _end_btn: Button
var _confirm_box: VBoxContainer
var _yes_btn: Button
var _no_btn: Button
var _esc_btn: Button
var _bag_btn: Button

var _order: Array[int] = []   # usable ability ids in cursor order: weapon actions, then spells
var _cursor_id := -1
var _hover_slot: HotbarSlot = null   # the usable ability slot under the mouse
var _cursor_shown := false
var _aim_id := -1
var _aim_tier := 1
var _confirming := false
var _end_cursor := 1   # NO is the safe default

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# Left column: the AP and movement tabs sitting on the main box. The tabs overlap the box's top border
	# by the frame thickness (negative separation, drawn on top) so the border is open under them.
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_vertical = Control.SIZE_SHRINK_END
	column.add_theme_constant_override("separation", -HudStyle.FRAME_PX)
	row.add_child(column)

	var tabs_inset := MarginContainer.new()
	tabs_inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs_inset.z_index = 1
	tabs_inset.add_theme_constant_override("margin_left", 0)
	tabs_inset.add_theme_constant_override("margin_right", 0)
	tabs_inset.add_theme_constant_override("margin_top", 0)
	tabs_inset.add_theme_constant_override("margin_bottom", 0)
	column.add_child(tabs_inset)
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The tab gap sits exactly over the divider below; each tab's bar spans exactly its sections.
	tabs.add_theme_constant_override("separation", int(2.0 * SECTION_GAP + DIVIDER_W - 2.0 * HudStyle.MARGIN_X))
	tabs_inset.add_child(tabs)

	# AP tab: taller bar, exactly as wide as hands + weapon actions.
	var ap_tab := PanelContainer.new()
	ap_tab.add_theme_stylebox_override("panel", HudStyle.tab())
	ap_tab.size_flags_vertical = Control.SIZE_SHRINK_END
	tabs.add_child(ap_tab)
	_ap_bar = ApBar.new()
	_ap_bar.custom_minimum_size = Vector2(LEFT_W, 0.0)
	ap_tab.add_child(_ap_bar)

	# Movement tab: shorter bar, exactly as wide as the spells.
	var move_tab := PanelContainer.new()
	move_tab.add_theme_stylebox_override("panel", HudStyle.tab())
	move_tab.size_flags_vertical = Control.SIZE_SHRINK_END
	move_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(move_tab)
	_move_bar = MovementBar.new()
	_move_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_tab.add_child(_move_bar)

	var main := PanelContainer.new()
	main.add_theme_stylebox_override("panel", HudStyle.frame())
	column.add_child(main)
	var inner := HBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", SECTION_GAP)
	main.add_child(inner)

	var hands := HBoxContainer.new()
	hands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hands.add_theme_constant_override("separation", GAP)
	inner.add_child(hands)
	for i in HAND_SLOTS.size():
		hands.add_child(_make_slot(HotbarSlot.Kind.GEAR, HAND_SIZE, _hand_slots))
	inner.add_child(HudDivider.new())
	inner.add_child(_grid(WEAPON_COLS, WEAPON_COLS * ROWS, _weapon_slots, Palette.INK))
	inner.add_child(HudDivider.new())
	inner.add_child(_grid(SPELL_COLS, SPELL_COLS * ROWS, _spell_slots, Palette.ACCENT))

	_action_slots = _weapon_slots + _spell_slots
	for s: HotbarSlot in _action_slots:
		s.picked.connect(_on_action_picked)
		s.mouse_entered.connect(_on_action_hover.bind(s))
		s.mouse_exited.connect(_on_action_unhover.bind(s))

	row.add_child(_build_side_panel())

	var gear := PanelContainer.new()
	gear.add_theme_stylebox_override("panel", HudStyle.frame())
	gear.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(gear)
	row.move_child(gear, 0)   # the gear box is the leftmost box
	var gear_col := VBoxContainer.new()
	gear_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gear_col.add_theme_constant_override("separation", GEAR_ROW_GAP)
	gear.add_child(gear_col)

	# Top row: empty slots (blank cells, the flat BG / grey-border look), laid out like the row below so the
	# two groups sit over armor and rings + amulet.
	var spare_row := HBoxContainer.new()
	spare_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spare_row.add_theme_constant_override("separation", SECTION_GAP)
	gear_col.add_child(spare_row)
	spare_row.add_child(_spare_grid(SPARE_COLS_LEFT))
	var spare_gap := Control.new()
	spare_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spare_gap.custom_minimum_size = Vector2(DIVIDER_W, 0.0)
	spare_row.add_child(spare_gap)
	spare_row.add_child(_spare_grid(SPARE_COLS_RIGHT))

	# Horizontal separator between the empty row and the equipment row.
	gear_col.add_child(_end_rule())

	var gear_row := HBoxContainer.new()
	gear_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gear_row.add_theme_constant_override("separation", SECTION_GAP)
	gear_col.add_child(gear_row)
	gear_row.add_child(_gear_grid(ARMOR_COLS, ARMOR_SLOTS.size(), _armor_slots))
	gear_row.add_child(HudDivider.new())
	gear_row.add_child(_gear_grid(JEWELRY_COLS, JEWELRY_SLOTS.size(), _jewelry_slots))

	# Gear slots exist now: wire them.
	for s: HotbarSlot in _hand_slots + _armor_slots + _jewelry_slots:
		if not s.picked.is_connected(_on_gear_picked):
			s.picked.connect(_on_gear_picked)
	show_end_confirm(false)
	set_mode(Mode.LOCKED, false)

# --- Called by BattleUI ------------------------------------------------------------

## data = UnitView.hotbar(unit, can_act). Updates the slots in place (so an open tooltip survives).
func show_data(data: Dictionary) -> void:
	if _move_bar == null:
		return
	_fill(_hand_slots, data.get("hands", []))
	_fill(_weapon_slots, data.get("weapon_actions", []))
	_fill(_spell_slots, data.get("spells", []))
	_fill(_armor_slots, data.get("armor", []))
	_fill(_jewelry_slots, data.get("jewelry", []))
	_move_bar.set_values(int(data.get("move", 0)), int(data.get("max_move", 0)))
	_ap_bar.set_values(float(data.get("ap", 0.0)), float(data.get("max_ap", 0.0)))
	_order.clear()
	for s: HotbarSlot in _action_slots:
		if s.is_usable():
			_order.append(s.key)
	if not _order.has(_cursor_id):
		_cursor_id = _order[0] if not _order.is_empty() else -1
	_refresh_marks()

## Hovering a reachable tile: the movement bar marks what walking there would spend. cost <= 0 clears.
func set_move_preview(cost: int) -> void:
	if _move_bar != null:
		_move_bar.set_preview(cost)

func set_mode(p_mode: Mode, can_end_turn: bool) -> void:
	mode = p_mode
	if _end_btn == null:
		return
	_end_btn.disabled = not (mode == Mode.READY and can_end_turn)
	_esc_btn.disabled = mode == Mode.LOCKED
	_bag_btn.disabled = mode != Mode.READY
	_apply_lock()
	_refresh_marks()

## Greys out what the player can't use right now. Abilities and both bars go grey while LOCKED or answering END TURN?;
## worn gear goes grey whenever it isn't clickable (anything but READY). While AIMING the bars and abilities stay live:
## the AP bar previews the cost and the player can still switch abilities.
func _apply_lock() -> void:
	var idle := mode == Mode.LOCKED or mode == Mode.CONFIRM
	for s: HotbarSlot in _action_slots:
		s.set_locked(idle)
	for s: HotbarSlot in _hand_slots + _armor_slots + _jewelry_slots:
		s.set_locked(mode != Mode.READY)
	_ap_bar.set_enabled(not idle)
	_move_bar.set_enabled(not idle)

## The ability being aimed (drawn inverted), or -1, and the tier it is being aimed at. The AP bar previews that tier's cost.
func set_aiming(action_id: int, tier := 1) -> void:
	_aim_id = action_id
	_aim_tier = tier if action_id >= 0 else 1
	_refresh_marks()

## Swaps END TURN for the "END TURN? YES / NO" question.
func show_end_confirm(on: bool) -> void:
	if _end_btn == null:
		return
	_confirming = on
	_end_btn.visible = not on
	_confirm_box.visible = on
	if on:
		_end_cursor = 1
		_style_confirm()

func is_confirming() -> bool:
	return _confirming

## dir: (-1,0) left, (1,0) right, (0,-1) up, (0,1) down. Returns true when handled.
func navigate(dir: Vector2i) -> bool:
	if _confirming:
		_end_cursor = clampi(_end_cursor + dir.x, 0, 1)
		_style_confirm()
		return true
	if (mode != Mode.READY and mode != Mode.AIMING) or _order.is_empty():
		return false
	if not _cursor_shown:
		_cursor_shown = true
	else:
		var i := _order.find(_cursor_id)
		i = clampi((i if i >= 0 else 0) + dir.x + dir.y, 0, _order.size() - 1)
		_cursor_id = _order[i]
	_refresh_marks()
	return true

## Accept on the keyboard cursor. The first press only reveals the cursor.
func accept() -> bool:
	if _confirming:
		if mode == Mode.CONFIRM:
			end_turn_answered.emit(_end_cursor == 0)
			return true
		return false
	if (mode != Mode.READY and mode != Mode.AIMING) or not _order.has(_cursor_id):
		return false
	if not _cursor_shown:
		_cursor_shown = true
		_refresh_marks()
		return true
	ability_chosen.emit(_cursor_id)
	return true

# --- Building -----------------------------------------------------------------------

func _make_slot(kind: int, slot_size: Vector2, bucket: Array) -> HotbarSlot:
	var s := HotbarSlot.new()
	s.setup(kind, slot_size)
	bucket.append(s)
	return s

func _grid(columns: int, count: int, bucket: Array, accent: Color) -> GridContainer:
	var g := GridContainer.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.columns = columns
	g.add_theme_constant_override("h_separation", GAP)
	g.add_theme_constant_override("v_separation", GAP)
	for i in count:
		var s := _make_slot(HotbarSlot.Kind.ACTION, Vector2(CELL, CELL), bucket)
		s.accent = accent
		g.add_child(s)
	return g

func _gear_grid(columns: int, count: int, bucket: Array) -> GridContainer:
	var g := GridContainer.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.columns = columns
	g.add_theme_constant_override("h_separation", GAP)
	g.add_theme_constant_override("v_separation", GAP)
	for i in count:
		g.add_child(_make_slot(HotbarSlot.Kind.GEAR, Vector2(CELL, CELL), bucket))
	return g

## One row of empty slots. They stay blank (set_data({}) in setup), so they draw as the empty-slot sprite and ignore clicks.
func _spare_grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.columns = columns
	g.add_theme_constant_override("h_separation", GAP)
	g.add_theme_constant_override("v_separation", GAP)
	for i in columns:
		g.add_child(_make_slot(HotbarSlot.Kind.GEAR, Vector2(CELL, CELL), _spare_slots))
	return g

func _build_side_panel() -> PanelContainer:
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", HudStyle.frame())
	side.size_flags_vertical = Control.SIZE_SHRINK_END
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	side.add_child(col)

	var end_slot := VBoxContainer.new()
	end_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_slot.custom_minimum_size = Vector2(156, 64)
	col.add_child(end_slot)
	_end_btn = Button.new()
	_end_btn.text = "END TURN"
	_end_btn.focus_mode = Control.FOCUS_NONE
	_end_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_end_btn.tooltip_text = "End this unit's turn."
	_end_btn.pressed.connect(_on_end_pressed)
	end_slot.add_child(_end_btn)
	_confirm_box = VBoxContainer.new()
	_confirm_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var question := Label.new()
	question.text = "END TURN?"
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_box.add_child(question)
	var answers := HBoxContainer.new()
	answers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_box.add_child(answers)
	_yes_btn = _answer_button("YES", 0)
	_no_btn = _answer_button("NO", 1)
	answers.add_child(_yes_btn)
	answers.add_child(_no_btn)
	end_slot.add_child(_confirm_box)

	col.add_child(_end_rule())
	var small := GridContainer.new()
	small.mouse_filter = Control.MOUSE_FILTER_IGNORE
	small.columns = 2
	small.add_theme_constant_override("h_separation", 6)
	small.add_theme_constant_override("v_separation", 6)
	col.add_child(small)
	_esc_btn = _small_button("Esc", "Back / cancel (Esc or right click)")
	_esc_btn.pressed.connect(func() -> void: back_pressed.emit())
	_bag_btn = _small_button("I", "Equipment (I)")
	_bag_btn.pressed.connect(func() -> void: inventory_pressed.emit())
	var zoom_in := _small_button("+", "Zoom in (mouse wheel)")
	zoom_in.pressed.connect(func() -> void: zoom_requested.emit(true))
	var zoom_out := _small_button("-", "Zoom out (mouse wheel)")
	zoom_out.pressed.connect(func() -> void: zoom_requested.emit(false))
	for b: Button in [_esc_btn, _bag_btn, zoom_in, zoom_out]:
		HudStyle.style_button(b, 2)
		small.add_child(b)
	HudStyle.style_button(_end_btn, 2)
	return side

func _end_rule() -> Control:
	var d := HudDivider.new()
	d.vertical = false
	return d

func _small_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(72, 40)
	return b

func _answer_button(text: String, index: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	HudStyle.style_button(b, 2)
	b.mouse_entered.connect(func() -> void:
		if _confirming and mode == Mode.CONFIRM:
			_end_cursor = index
			_style_confirm())
	b.pressed.connect(func() -> void:
		if _confirming and mode == Mode.CONFIRM:
			end_turn_answered.emit(index == 0))
	return b

# --- Internals ----------------------------------------------------------------------

func _fill(slots: Array, cells: Array) -> void:
	for i in slots.size():
		(slots[i] as HotbarSlot).set_data(cells[i] if i < cells.size() else {})

func _refresh_marks() -> void:
	for s: HotbarSlot in _action_slots:
		s.set_aiming(not s.is_blank() and s.key == _aim_id, _aim_tier)
		s.set_cursor(_cursor_shown and not s.is_blank() and s.key == _cursor_id and (mode == Mode.READY or mode == Mode.AIMING))
	_refresh_ap_preview()

## The AP bar previews what the ability under the mouse would spend (over the aimed spell: the next tier, which is what
## another click buys); failing that, the aimed one at its chosen tier (also while the attack waits for CONFIRM); failing
## that, the one under the keyboard cursor. Nothing while the bar is locked.
func _refresh_ap_preview() -> void:
	if _ap_bar == null:
		return
	var cost := 0.0
	if mode != Mode.LOCKED:
		if _hover_slot != null and (mode == Mode.READY or mode == Mode.AIMING):
			cost = _hover_slot.cost_for_tier(_aim_tier + 1) if _hover_slot.key == _aim_id else _hover_slot.ap_cost
		elif _aim_id >= 0:
			cost = _slot_cost(_aim_id, _aim_tier)
		elif _cursor_shown and mode == Mode.READY:
			cost = _slot_cost(_cursor_id)
	_ap_bar.set_preview(cost)

func _slot_cost(action_id: int, tier := 1) -> float:
	for s: HotbarSlot in _action_slots:
		if not s.is_blank() and s.key == action_id:
			return s.cost_for_tier(tier)
	return 0.0

func _style_confirm() -> void:
	_yes_btn.text = "%sYES" % ["\u25b6 " if _end_cursor == 0 else ""]
	_no_btn.text = "%sNO" % ["\u25b6 " if _end_cursor == 1 else ""]

func _on_action_picked(id: int) -> void:
	if mode == Mode.READY or mode == Mode.AIMING:
		_cursor_id = id
		ability_chosen.emit(id)

func _on_action_unhover(slot: HotbarSlot) -> void:
	if _hover_slot == slot:
		_hover_slot = null
		_refresh_ap_preview()

func _on_action_hover(slot: HotbarSlot) -> void:
	_hover_slot = slot if slot.is_usable() else null
	if slot.is_usable() and (mode == Mode.READY or mode == Mode.AIMING):
		_cursor_id = slot.key
		_cursor_shown = false   # the mouse is in charge; the hover outline shows where it is
		_refresh_marks()
	_refresh_ap_preview()

func _on_gear_picked(slot: int) -> void:
	if mode == Mode.READY:
		gear_chosen.emit(slot)

func _on_end_pressed() -> void:
	if mode == Mode.READY:
		end_turn_pressed.emit()
