extends PanelContainer
## Top bar of the run map: one battle unit panel (ui/hud/unit_panel_3d.tscn, docked) per party member,
## a separator, then the gold. Clicking a panel opens the battle's equipment window (ui/equipment_window.tscn,
## Stats / Skills, paper doll and bag; without its unit tabs or grey overlay here) on that member.
## No run rules here: data comes from RunState and gear edits are written back to RunState.party.
## The window edits RunState.bag in place. RunState has no signals, so the bar compares a small signature
## every frame (while the window is closed) and refreshes itself after a fight, a campfire or a shop.

const Equipment = preload("res://scripts/inventory/equipment.gd")
const Item = preload("res://scripts/inventory/item.gd")
const PanelScript = preload("res://ui/hud/unit_panel_3d.gd")
const PanelScene = preload("res://ui/hud/unit_panel_3d.tscn")
const Unit = preload("res://scripts/battle/unit.gd")
const UnitView = preload("res://ui/hud/unit_view.gd")
const WindowScript = preload("res://ui/equipment_window.gd")

## Click target around one docked panel; draws the highlight border while selected.
class PartySlot extends Control:
	const Pal = preload("res://ui/theme/gbc_palette.gd")
	const BORDER := 3.0

	signal clicked

	var selected := false:
		set(value):
			selected = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			clicked.emit()

	func _draw() -> void:
		if selected:
			draw_rect(Rect2(Vector2.ONE, size - Vector2(2.0, 2.0)), Pal.ACCENT, false, BORDER)

@onready var _party: HBoxContainer = $Row/Party
@onready var _gold: Label = $Row/GoldLabel
@onready var _window: WindowScript = $"../EquipmentWindow"

var _members: Array = []          # the PartyMember each slot was built for
var _units: Array[Unit] = []      # one lightweight Unit per member (the window edits these)
var _slots: Array[PartySlot] = []
var _panels: Array[PanelScript] = []
var _selected := -1               # index of the member the window shows, -1 = window closed
var _sig: Array = []

func _ready() -> void:
	# Map look: no grey overlay, no unit tabs (set_party() is never called, so the strip stays hidden),
	# and the window ignores the mouse outside its panel so the party panels stay clickable.
	(_window.get_node("Dim") as CanvasItem).visible = false
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.equipment_changed.connect(_on_equipment_changed)
	_window.closed.connect(_on_window_closed)

func is_window_open() -> bool:
	return _selected >= 0

func _process(_delta: float) -> void:
	if not RunState.active or _selected >= 0:
		return
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		refresh(true)

func _unhandled_input(event: InputEvent) -> void:
	if _selected < 0:
		return
	var key := event as InputEventKey
	var close: bool = event.is_action_pressed("ui_cancel") \
			or (key != null and key.pressed and not key.echo and key.keycode in [KEY_ESCAPE, KEY_I])
	if close:
		_window.close()
		get_viewport().set_input_as_handled()

## Redraws gold and every panel from RunState. `reload_gear` re-reads worn gear into the Units
## (pass false when the Units already hold it, as after a window edit).
func refresh(reload_gear := true) -> void:
	_gold.text = "Gold %d" % RunState.gold
	var party := RunState.party
	var same := party.size() == _members.size()
	if same:
		for i in party.size():
			if party[i] != _members[i]:
				same = false
				break
	if not same:
		_rebuild_slots()
	else:
		for i in party.size():
			if reload_gear:
				_load_gear(_units[i], party[i])
			_units[i].hp = clampi(party[i].current_hp, 0, _units[i].max_hp)
	for i in _panels.size():
		_panels[i].set_view(_view_for(_units[i]), same)
	_sig = _signature()

# --- panels --------------------------------------------------------------------------------

func _rebuild_slots() -> void:
	if _window.visible:
		_window.close()
	for slot in _slots:
		_party.remove_child(slot)
		slot.queue_free()
	_members.clear()
	_units.clear()
	_slots.clear()
	_panels.clear()
	for i in RunState.party.size():
		var member = RunState.party[i]
		var slot := PartySlot.new()
		slot.custom_minimum_size = Vector2(PanelScript.FLAT_W, PanelScript.H_BASE)
		var panel: PanelScript = PanelScene.instantiate()
		panel.docked = true
		slot.add_child(panel)
		_party.add_child(slot)
		panel.show_panel()
		slot.clicked.connect(_on_slot_clicked.bind(i))
		_members.append(member)
		_units.append(_make_unit(member))
		_slots.append(slot)
		_panels.append(panel)

## Same keys as UnitView.build(). The AP / MV line means nothing on the map, so it is switched off.
func _view_for(unit: Unit) -> Dictionary:
	var view := UnitView.build(unit)
	view["max_ap"] = 0.0
	return view

func _make_unit(member) -> Unit:
	var u := Unit.new(member.unit_data, Unit.Side.PLAYER, Vector2i.ZERO)
	_load_gear(u, member)
	u.hp = clampi(member.current_hp, 0, u.max_hp)
	return u

## Unit wears exactly what the party member wears.
func _load_gear(u: Unit, member) -> void:
	for slot in Equipment.ALL_SLOTS:
		u.equipment.unequip(slot)
	for slot in Equipment.ALL_SLOTS:
		var worn: Item = member.equipment.get_item(slot)
		if worn != null:
			u.equipment.try_equip(worn, slot)

func _signature() -> Array:
	var s: Array = [RunState.gold, RunState.party.size(), RunState.bag.placements().size()]
	for m in RunState.party:
		s.append(m.get_instance_id())
		s.append(m.current_hp)
		for slot in Equipment.ALL_SLOTS:
			var item: Item = m.equipment.get_item(slot)
			s.append(item.get_instance_id() if item != null else 0)
	return s

# --- equipment window ----------------------------------------------------------------------

func _on_slot_clicked(i: int) -> void:
	if _selected == i:
		_window.close()
		return
	_open(i)

func _open(i: int) -> void:
	_selected = i
	_update_highlight()
	_window.open(_units[i], RunState.bag, true)

func _on_window_closed() -> void:
	_selected = -1
	_update_highlight()
	_sig = _signature()

func _update_highlight() -> void:
	for i in _slots.size():
		_slots[i].selected = i == _selected

## The window already edited the Unit's gear and RunState.bag; copy the gear back into the party member.
func _on_equipment_changed(unit: Unit) -> void:
	var i := _units.find(unit)
	if i < 0:
		return
	var worn := Equipment.new()
	for slot in Equipment.ALL_SLOTS:
		var item: Item = unit.equipment.get_item(slot)
		if item != null:
			worn.try_equip(item, slot)
	RunState.party[i].equipment = worn
	_refresh_later.call_deferred()

func _refresh_later() -> void:
	refresh(false)
