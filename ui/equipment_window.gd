extends Control
## Modal equipment window for one unit. One Stats / Skills tab row switches BOTH panels:
## Stats tab:  left = vitals, attributes, status effects.   right = paper doll.
## Skills tab: left = the unit's skill attributes (hover one for its card).   right = memory slots + every learned skill.
## The party bag (editable units only) stays on the far right of both tabs.
## Player units are editable; enemy units are a read-only preview.
## Owns no battle rules. It edits the unit's Equipment and the shared bag grid (inventory.gd) it is handed,
## then tells battle_view what changed. Diablo 2 rules: wearing an item takes it out of the bag, taking it off
## puts it back, and an equip or unequip that would not leave room in the bag is refused.

signal closed
signal equipment_changed(unit: Unit)
## A party tab (or Tab / a number key) asked to look at another unit. battle_view decides whether it is editable
## and calls open() again.
signal unit_requested(unit: Unit)

const Equipment = preload("res://scripts/inventory/equipment.gd")
const AbilityText = preload("res://ui/ability_text.gd")
const StatusText = preload("res://ui/status_text.gd")
const Ability = preload("res://scripts/battle/ability.gd")
const HotbarSlot = preload("res://ui/hud/hotbar_slot.gd")
const HudDivider = preload("res://ui/hud/hud_divider.gd")
const Inventory = preload("res://scripts/inventory/inventory.gd")
const BagGrid = preload("res://ui/bag_grid.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const Item = preload("res://scripts/inventory/item.gd")
const PaperDollScript = preload("res://ui/paper_doll.gd")
const SideTint = preload("res://ui/side_tint.gd")
const StatHeader = preload("res://ui/stat_header.gd")
const StatTooltip = preload("res://ui/stat_tooltip.gd")
const VitalsBar = preload("res://ui/vitals_bar.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const Discipline = preload("res://scripts/skills/discipline.gd")
const DisciplineTooltip = preload("res://ui/discipline_tooltip.gd")
const TurnChip = preload("res://ui/turn_chip.gd")
const TURN_CHIP_SCENE: PackedScene = preload("res://ui/turn_chip.tscn")

@onready var _dim: ColorRect = %Dim
@onready var _unit_name: Label = %UnitName
@onready var _side_tag: Label = %SideTag
@onready var _close: Button = %Close
@onready var _doll: PaperDollScript = %PaperDoll
@onready var _bag_panel: Control = %BagPanel
@onready var _bag_grid: BagGrid = %BagGrid
@onready var _vitals: VitalsBar = %Vitals
@onready var _ability_grid: GridContainer = %AbilityGrid
@onready var _stat_grid: GridContainer = %StatGrid
## The node named Abilities in the scene now holds the unit's status effects (the abilities moved to the Skills tab).
@onready var _effects: VBoxContainer = %Abilities
@onready var _status: Label = %Status
@onready var _tabs: HBoxContainer = %UnitTabs

const ABILITY_HEADERS: Array[String] = ["STR", "DEX", "CON", "INT", "WIS"]
## Both tab pages get this much height so the window does not jump when you switch tabs.
const PAGE_MIN_HEIGHT := 300.0
const STAT_HEADERS: Array[String] = ["AC", "PROF", "SPD", "MOVE", "JUMP", "CT"]
## Plain-text fallback for the stat headers. The real hover card is StatTooltip (ui/stat_tooltip.gd), set in _refresh_tips().
const STAT_TIPS := {
	"STR": "Strength", "DEX": "Dexterity", "CON": "Constitution", "INT": "Intelligence", "WIS": "Wisdom",
	"AC": "Armor Class: how hard this unit is to hit.", "PROF": "Proficiency bonus.", "SPD": "Speed: how fast the turn meter fills.",
	"MOVE": "Movement: tiles per turn.", "JUMP": "Jump: tiles of height it can climb.", "CT": "Charge Time: this unit's place in the turn order.",
}

var _unit: Unit = null
## The party's shared bag. Shared by reference with battle_view: this window adds and removes items.
var _bag: Inventory = null
## The bag placement being dragged or quick-equipped right now. Its cells count as free when checking room.
var _held: Inventory.Placement = null
## The party tabs: one turn-order chip per player unit, in party order. Built by set_party(). They sit in a strip
## OUTSIDE the window panel, above it (see _move_tabs_outside()).
var _party: Array[Unit] = []
var _tab_chips: Array[TurnChip] = []
## The window-level Stats / Skills tabs. Built by _build_stats_tabs().
## Left panel pages: _stats_page / _discipline_page. Right side: _doll (+ bag) / _skills_panel.
var _left_title: Label
var _stats_page: VBoxContainer
var _discipline_page: VBoxContainer
var _skills_panel: PanelContainer
var _skills_box: VBoxContainer
var _page_tabs: Array[Button] = []
var _page := 0
## Skill attribute picked on the Skills tab's left panel: the Learned list shows only that type. &"" = all.
var _attr_filter: StringName = &""
var _editable := false

func _ready() -> void:
	visible = false
	_dim.color = SideTint.DIM
	_build_grid(_ability_grid, ABILITY_HEADERS)
	_build_grid(_stat_grid, STAT_HEADERS)
	# A rule under each panel title, and one above the help line.
	_rule_after(_build_stats_tabs())
	_rule_after(get_node("Center/Window/Rows/Body/BagPanel/BagRows/BagTitle"))
	_rule_after(_doll.get_node("Rows/Title"))
	_rule_before(_status)
	_close.pressed.connect(close)
	_doll.equip_gate = _equip_gate
	_doll.unequip_gate = _unequip_gate
	_doll.equip_attempted.connect(_on_equip_attempted)
	_doll.unequip_blocked.connect(func(reason: String) -> void: _status.text = reason)
	_bag_grid.item_dropped.connect(_on_grid_drop)
	_bag_grid.right_clicked.connect(_on_grid_right_click)
	_bag_grid.drag_started.connect(func(p: Inventory.Placement) -> void: _held = p)
	_bag_grid.drag_ended.connect(func() -> void: _held = null)
	_doll.unequipped.connect(_on_unequipped)
	_move_tabs_outside()

## Lifts the party strip out of the window panel and stacks it above the panel, like the action bar and movement bar
## that sit outside their frames. The two are centered together as one block.
func _move_tabs_outside() -> void:
	var center: Control = get_node("Center")
	var window: Control = get_node("Center/Window")
	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 6)
	center.add_child(stack)
	_tabs.reparent(stack, false)
	window.reparent(stack, false)

## editable false = preview only. note: shown instead of the usual hint when set.
func open(unit: Unit, bag: Inventory, editable: bool, note: String = "") -> void:
	_unit = unit
	_bag = bag
	_editable = editable
	_unit_name.text = unit.unit_name
	_side_tag.text = SideTint.side_name(unit.side).to_upper()
	_side_tag.add_theme_color_override("font_color", SideTint.color_for(unit.side))
	_doll.bind(unit.equipment)
	_doll.set_read_only(not editable)
	_bag_panel.visible = editable
	if note != "":
		_status.text = note
	elif editable:
		_status.text = "Drag to move or equip. Right-click to equip or unequip."
	else:
		_status.text = "Preview only."
	_bag_grid.bind(bag)
	_refresh_info()
	_sync_tabs()
	visible = true

func close() -> void:
	if not visible:
		return
	visible = false
	_doll.bind(null)
	_unit = null
	closed.emit()

# --- party tabs ------------------------------------------------------------------

## Gives the window its party: one tab per unit, each a shortcut to that unit's gear and stats. Call once after the
## units exist. Tab / Shift+Tab step through the party, and keys 1-9 jump straight to a unit.
func set_party(units: Array[Unit]) -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_party = units.duplicate()
	_tab_chips.clear()
	for i in _party.size():
		var unit := _party[i]
		# The same chip the turn order bar uses (marker, portrait, name). Its marker is the unit's number key.
		var chip := TURN_CHIP_SCENE.instantiate() as TurnChip
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.tooltip_text = "Show %s (key %d, or Tab to cycle)" % [unit.unit_name, i + 1]
		chip.gui_input.connect(_on_chip_input.bind(unit))
		_tabs.add_child(chip)
		chip.set_entry(unit, str(i + 1))
		_tab_chips.append(chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tabs.add_child(spacer)
	var hint := Label.new()
	hint.text = "Tab: next unit"
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	hint.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_tabs.add_child(hint)
	if visible:
		_sync_tabs()

## Shows the strip only while one of your own units is open (they are party shortcuts, so an enemy preview has none).
## The open unit's chip is full strength and wears the turn bar's arrow; the others are dimmed, the fallen more so.
func _sync_tabs() -> void:
	_tabs.visible = _party.size() > 1 and _unit != null and _unit.side == Unit.Side.PLAYER
	for i in _tab_chips.size():
		var unit := _party[i]
		var open := unit == _unit
		_tab_chips[i].set_entry(unit, ("\u25bc%d" if open else "%d") % (i + 1))
		_tab_chips[i].modulate = Color(1, 1, 1, 1.0 if open else (0.55 if unit.is_alive() else 0.25))

func _on_chip_input(event: InputEvent, unit: Unit) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if unit.is_alive():
		_on_tab_pressed(unit)

func _on_tab_pressed(unit: Unit) -> void:
	# Re-clicking the open unit would untoggle its tab, and a request the battle refused would leave the wrong
	# tab lit, so the tabs are always put back in step afterwards.
	if unit != _unit:
		unit_requested.emit(unit)
	_sync_tabs()

## Steps to the next (+1) or previous (-1) living party member.
func _cycle_unit(step: int) -> void:
	var count := _party.size()
	if count == 0:
		return
	var i := _party.find(_unit)
	if i == -1:
		i = -1 if step > 0 else count
	for _n in count:
		i = posmod(i + step, count)
		if _party[i] != _unit and _party[i].is_alive():
			_request_unit(_party[i])
			return

func _request_unit(unit: Unit) -> void:
	unit_requested.emit(unit)
	_sync_tabs()

## Tab / Shift+Tab and 1-9, only while the window is open. Handled here, ahead of the GUI, so Tab never walks
## keyboard focus around the window.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# Tab is always swallowed so it never walks keyboard focus, but it only switches units while the tabs are showing.
	if key.keycode == KEY_TAB:
		if _tabs.visible:
			_cycle_unit(-1 if key.shift_pressed else 1)
		get_viewport().set_input_as_handled()
		return
	if not _tabs.visible or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	var n: int = key.keycode - KEY_1
	if n >= 0 and n < mini(_party.size(), 9):
		if _party[n] != _unit and _party[n].is_alive():
			_request_unit(_party[n])
		get_viewport().set_input_as_handled()

## Same numbers the hover panel shows, so the window is the one place to read a unit.
func _refresh_info() -> void:
	_vitals.set_unit(_unit)
	var mods: Array[String] = []
	for m in _unit.mods:
		mods.append("%+d" % m)
	_fill_row(_ability_grid, mods)
	_fill_row(_stat_grid, [str(_unit.ac), "+%d" % _unit.prof, str(_unit.spd), str(_unit.move_range), str(_unit.jump), str(_unit.ct)])
	_refresh_tips(_ability_grid, ABILITY_HEADERS)
	_refresh_tips(_stat_grid, STAT_HEADERS)
	_refresh_effects()
	_refresh_disciplines()
	_refresh_skills()

## A grid is one header row then one value row (5 ability columns, 6 stat columns).
func _build_grid(grid: GridContainer, headers: Array[String]) -> void:
	for h in headers:
		var head := _cell(h, StatHeader.new())
		head.mouse_filter = Control.MOUSE_FILTER_STOP
		head.tooltip_text = STAT_TIPS.get(h, h)
		grid.add_child(head)
	for _h in headers:
		grid.add_child(_cell("0"))

func _cell(text: String, label: Label = null) -> Label:
	if label == null:
		label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

## Gives every header in the grid's first row the hover card for the unit being shown, with its live numbers.
func _refresh_tips(grid: GridContainer, headers: Array[String]) -> void:
	for i in headers.size():
		(grid.get_child(i) as StatHeader).tip = StatTooltip.tip(headers[i], _unit)

func _fill_row(grid: GridContainer, values: Array[String]) -> void:
	for i in values.size():
		(grid.get_child(grid.columns + i) as Label).text = values[i]

# --- Stats / Skills tabs ------------------------------------------------------------

## One tab row for the whole window (between the party tabs and the two panels). Each tab changes both panels:
## Stats = stat page + paper doll, Skills = skill-attribute page + memory / learned skills. Returns the left panel's
## title so the caller can put a rule under it.
func _build_stats_tabs() -> Control:
	var window_rows: VBoxContainer = get_node("Center/Window/Rows")
	var body: HBoxContainer = window_rows.get_node("Body")
	var rows: VBoxContainer = body.get_node("StatsPanel/StatsRows")
	_left_title = rows.get_node("StatsTitle")

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	for i in 2:
		var tab := Button.new()
		tab.text = "Stats" if i == 0 else "Skills"
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_show_page.bind(i))
		tab_row.add_child(tab)
		_page_tabs.append(tab)
	window_rows.add_child(tab_row)
	window_rows.move_child(tab_row, body.get_index())

	# Left, Stats page: the widgets that were always there.
	_stats_page = _new_page()
	rows.add_child(_stats_page)
	for node: Control in [_vitals, _ability_grid, _stat_grid, _effects]:
		node.reparent(_stats_page)
	# Left, Skills page: the disciplines list, rebuilt by _refresh_disciplines().
	_discipline_page = _new_page()
	rows.add_child(_discipline_page)

	# Right, Skills panel: sits next to the paper doll and takes its place on the Skills tab. It scrolls vertically
	# when the skills don't fit, never horizontally, so rows wrap instead of widening the window.
	_skills_panel = PanelContainer.new()
	var panel_rows := VBoxContainer.new()
	panel_rows.add_theme_constant_override("separation", 14)
	_skills_panel.add_child(panel_rows)
	var title := Label.new()
	title.text = "Skills"
	title.theme_type_variation = &"TitleLabel"
	panel_rows.add_child(title)
	panel_rows.add_child(_rule())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_rows.add_child(scroll)
	_skills_box = VBoxContainer.new()
	_skills_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_skills_box)
	body.add_child(_skills_panel)
	body.move_child(_skills_panel, _doll.get_index() + 1)

	_show_page(0)
	return _left_title

func _new_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.custom_minimum_size = Vector2(0, PAGE_MIN_HEIGHT)
	return page

## Switches the left panel and the doll / skills panel. The bag is not touched: it stays on both tabs.
## The Skills panel is held to the paper doll's size so the window does not jump.
func _show_page(index: int) -> void:
	_page = index
	var skills := index == 1
	_left_title.text = "Skill Attributes" if skills else "Stats"
	_stats_page.visible = not skills
	_discipline_page.visible = skills
	_skills_panel.custom_minimum_size = _doll.get_combined_minimum_size()
	_doll.visible = not skills
	_skills_panel.visible = skills
	for i in _page_tabs.size():
		_page_tabs[i].set_pressed_no_signal(i == index)

## Title, rule, icon container: the layout both tabs use for every section.
func _section(parent: Control, title: String) -> void:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	parent.add_child(_rule())

func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func _none(parent: Control, text: String) -> void:
	var none := Label.new()
	none.text = text
	none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	none.custom_minimum_size = Vector2(1, 0)
	none.add_theme_color_override("font_color", Palette.INK_LIGHT)
	parent.add_child(none)

## Stats tab, bottom section: the unit's status effects and Armor Shred / Fracture stacks as icons. Hover for details.
func _refresh_effects() -> void:
	_clear(_effects)
	_section(_effects, "Status")
	var rows := StatusText.entries(_unit)
	if rows.is_empty():
		_none(_effects, "None.")
		return
	var row := _icon_row()
	for d: Dictionary in rows:
		row.add_child(_slot(d, d.get("accent", Palette.INK)))
	_effects.add_child(row)

## Highest rank first, then A to Z.
func _discipline_before(x: StringName, y: StringName) -> bool:
	var rx := _unit.discipline_rank(x)
	var ry := _unit.discipline_rank(y)
	if rx != ry:
		return rx > ry
	return Discipline.display_name(x) < Discipline.display_name(y)

## Skills tab, left panel: one row per trained discipline. Hover a row for the discipline's card.
func _refresh_disciplines() -> void:
	_clear(_discipline_page)
	var ids: Array[StringName] = []
	for id: StringName in _unit.discipline_ranks.keys():
		if _unit.discipline_rank(id) > 0:
			ids.append(id)
	if ids.is_empty():
		_none(_discipline_page, "No skill attribute training.")
		return
	ids.sort_custom(_discipline_before)
	if not ids.has(_attr_filter):
		_attr_filter = &""
	for id in ids:
		var tip := DisciplineTooltip.tip(id, _unit)
		var stat := Discipline.stat_of(id)
		var row := HBoxContainer.new()
		var picked := id == _attr_filter
		var name_label := _discipline_label(("> " if picked else "") + Discipline.display_name(id), tip)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.gui_input.connect(_on_attribute_input.bind(id))
		row.add_child(name_label)
		var info := _discipline_label(
				"%s %+d   Rank %d" % [Discipline.stat_letters(stat), _unit.mod(stat), _unit.discipline_rank(id)], tip)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		info.size_flags_horizontal = Control.SIZE_SHRINK_END
		info.add_theme_color_override("font_color", Palette.ACCENT if picked else Palette.INK_LIGHT)
		info.gui_input.connect(_on_attribute_input.bind(id))
		row.add_child(info)
		_discipline_page.add_child(row)

## Click a skill attribute to show only its skills in the Learned list. Click it again to show everything.
func _on_attribute_input(event: InputEvent, id: StringName) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_attr_filter = &"" if _attr_filter == id else id
	_refresh_disciplines()
	_refresh_skills()

## A label that shows the discipline's TooltipCard on hover (same widget the stat headers use).
func _discipline_label(text: String, tip: Dictionary) -> StatHeader:
	var label := StatHeader.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.tooltip_text = text   # plain fallback; Godot only asks for the card when this is not empty
	label.tip = tip
	return label

## Skills tab, right panel: the memory slots (what the hotbar can use), then every learned skill. A learned skill that is in memory
## is drawn inverted. For your own units, clicking a skill memorizes it or takes it out of memory.
func _refresh_skills() -> void:
	_clear(_skills_box)
	var memorized := _unit.memorized_skills()
	memorized.sort_custom(_skill_before)
	_section(_skills_box, "Memory  %d/%d" % [memorized.size(), _unit.skill_slots])
	var slots := _icon_row()
	for a in memorized:
		# A skill is as wide as the memory squares it fills (a 2-slot skill is a 2-square rectangle).
		slots.add_child(_skill_slot(a, false))
	for _i in _unit.skill_slots_free():
		slots.add_child(_slot({}, Palette.INK))
	_skills_box.add_child(slots)

	var learned: Array[Ability] = []
	for a in _unit.learned_skills():
		if _attr_filter == &"" or _requires_attribute(a, _attr_filter):
			learned.append(a)
	learned.sort_custom(_skill_before)
	if _attr_filter == &"":
		_section(_skills_box, "Learned")
	else:
		_section(_skills_box, "Learned: %s" % Discipline.display_name(_attr_filter))
	if learned.is_empty():
		_none(_skills_box, "Nothing learned yet." if _attr_filter == &"" else "No learned skills of this type.")
	else:
		var row := _icon_row()
		for a in learned:
			row.add_child(_skill_slot(a, _unit.is_memorized(a)))
		_skills_box.add_child(row)

## Skills sorted by weight: memory cost first (light to heavy), then by type (branch, then skill attribute), then A to Z.
## Plain spells / abilities with no skill attribute come last within their weight.
func _skill_before(x: Ability, y: Ability) -> bool:
	if x.memory_cost != y.memory_cost:
		return x.memory_cost < y.memory_cost
	var dx: StringName = x.get("discipline") if x.get("discipline") != null else &""
	var dy: StringName = y.get("discipline") if y.get("discipline") != null else &""
	var has_x := Discipline.exists(dx)
	var has_y := Discipline.exists(dy)
	if has_x != has_y:
		return has_x
	if has_x:
		var bx := Discipline.branch_of(dx)
		var by := Discipline.branch_of(dy)
		if bx != by:
			return bx < by
		if dx != dy:
			return Discipline.display_name(dx) < Discipline.display_name(dy)
	return x.display_name < y.display_name

## True when `a` is a skill that lists `id` among its skill attribute requirements (hybrids count under each).
func _requires_attribute(a: Ability, id: StringName) -> bool:
	if a.has_method("all_requirements"):
		return a.all_requirements().has(id)
	return false

func _skill_slot(a: Ability, marked: bool) -> HotbarSlot:
	var tip := AbilityText.tooltip(_unit, a, true)
	var footer: Array = tip.get("footer", [])
	footer.append("Memory: %d slot%s%s" % [a.memory_cost, "" if a.memory_cost == 1 else "s",
			"" if _unit.is_memorized(a) else "  (not memorized, can't be used)"])
	if _editable:
		footer.append("Click: %s" % ("take out of memory" if _unit.is_memorized(a) else "memorize"))
	tip["footer"] = footer
	# Multi-slot skills are drawn as a wide rectangle, in the Learned list too, so you can see before
	# memorizing how much room they will take.
	var slot := _slot({
		"id": 0, "short": _initials(a.display_name), "usable": true, "cooldown": _unit.cooldown_left(a), "tip": tip,
	}, Palette.ACCENT if AbilityText.is_spell(a) else Palette.INK, a.memory_cost)
	if marked:
		slot.set_aiming(true)
	if _editable:
		slot.picked.connect(_on_skill_clicked.bind(a))
	return slot

func _on_skill_clicked(_key: int, a: Ability) -> void:
	if _unit == null:
		return
	if _unit.is_memorized(a):
		_unit.unmemorize(a)
		_status.text = "%s taken out of memory." % a.display_name
	elif _unit.memorize(a):
		_status.text = "%s memorized." % a.display_name
	else:
		_status.text = "%s needs %d free memory slot%s (%d free). Take another skill out of memory first." % [
				a.display_name, a.memory_cost, "" if a.memory_cost == 1 else "s", _unit.skill_slots_free()]
		return
	_after_change()

func _initials(text: String) -> String:
	var out := ""
	for word in text.split(" ", false):
		out += word.substr(0, 1).to_upper()
	return out.substr(0, 2)

func _icon_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	return row

## One 48 px icon slot, the same widget the hotbar uses. {} = an empty square. `span` squares wide: the width of that
## many squares plus the gaps between them (the icon rows use an 8 px gap).
func _slot(data: Dictionary, accent: Color, span: int = 1) -> HotbarSlot:
	var slot := HotbarSlot.new()
	slot.setup(HotbarSlot.Kind.ACTION, Vector2(48 * span + 8 * (span - 1), 48))
	slot.accent = accent
	slot.set_data(data)
	return slot

# --- dividers -------------------------------------------------------------------

func _rule() -> Control:
	var d := HudDivider.new()
	d.vertical = false
	return d

func _rule_after(node: Control) -> void:
	var parent := node.get_parent()
	parent.add_child(_rule())
	parent.move_child(parent.get_child(parent.get_child_count() - 1), node.get_index() + 1)

func _rule_before(node: Control) -> void:
	var parent := node.get_parent()
	parent.add_child(_rule())
	parent.move_child(parent.get_child(parent.get_child_count() - 1), node.get_index())

# --- bag <-> equipment ------------------------------------------------------------

## The placement that `item` is coming out of: the one being dragged, else any copy.
func _source_for(item: Item) -> Inventory.Placement:
	if _held != null and _held.item == item:
		return _held
	return _bag.placement_of(item)

## Called by the paper doll before every equip. "" = go ahead. The equip rules run on a copy to see what would
## come off, and all of it has to fit in the bag once the item being equipped has left it.
func _equip_gate(item: Item, target_slot: int, selected_ring: int) -> String:
	var preview := _unit.equipment.preview(item, target_slot, selected_ring)
	if not preview.ok:
		return ""   # the real equip reports the same reason
	if not _bag.can_fit_all(preview.displaced, _source_for(item)):
		return "No room in the bag for what would come off."
	return ""

func _unequip_gate(item: Item) -> String:
	if _bag.find_space(item) == Inventory.NO_SPACE:
		return "No room in the bag for %s." % item.display_name
	return ""

## Right-click an item in the bag: equip it where it fits.
func _on_grid_right_click(placement: Inventory.Placement) -> void:
	_held = placement
	_doll.equip(placement.item)
	_held = null

## Something was dropped on the bag grid: a bag item moving, or a worn item coming off.
func _on_grid_drop(payload: Dictionary, pos: Vector2i) -> void:
	var item: Item = payload["item"]
	if payload.has("placement"):
		_bag.move(payload["placement"], pos)
	elif payload.has("slot"):
		var slot: int = payload["slot"]
		if _unit.equipment.get_item(slot) != item:
			return
		_unit.equipment.unequip(slot)
		_bag.place(item, pos)
		_status.text = "%s removed from %s." % [item.display_name, Equipment.slot_label(slot)]
		_after_change()

func _on_equip_attempted(item: Item, result) -> void:
	if not result.ok:
		_status.text = "Can't equip %s: %s" % [item.display_name, result.reason]
		return
	# The item leaves the bag, then whatever it pushed off a slot takes its place (the gate checked it fits).
	var source := _source_for(item)
	if source != null:
		_bag.remove(source)
	var names: Array[String] = []
	for d: Item in result.displaced:
		names.append(d.display_name)
		if _bag.add(d) == null:
			push_warning("Bag full: %s was lost" % d.display_name)
	var text := "%s -> %s." % [item.display_name, Equipment.slot_label(result.slot)]
	if not names.is_empty():
		text += " Replaced: %s." % ", ".join(names)
	_status.text = text
	_after_change()

func _on_unequipped(item: Item, slot: int) -> void:
	if _bag.add(item) == null:
		push_warning("Bag full: %s was lost" % item.display_name)
	_status.text = "%s removed from %s." % [item.display_name, Equipment.slot_label(slot)]
	_after_change()

func _after_change() -> void:
	_refresh_info()
	equipment_changed.emit(_unit)
