extends Control
## Target panel: the unit panel again, from the ENEMY's side. It is the same pseudo-3D panel
## (ui/hud/unit_panel_3d.tscn, bars and rings included), anchored to the target's sprite on the
## opposite side from the current unit's panel, plus CONFIRM and CANCEL. The attack preview (hit %,
## crit %, damage range, projected HP) is NOT here: it lives in ForecastBox, centered above the HUD.
## `forecast_changed` tells whoever owns that box what to show.
## The buttons hang under the card INSIDE its flat viewport (UnitPanel3D.set_footer), so the same tilt shader
## bends them with the card. Controls drawn through a shader cannot take the mouse, so this node does it:
## every mouse event is mapped back through the tilt (UnitPanel3D.to_flat) to see which button, if any, is
## under the pointer. Keyboard / controller: navigate() + accept().

signal confirmed
signal cancelled
## Emitted with the forecast to show (open / refresh) or {} (close).
signal forecast_changed(forecast: Dictionary)

const UnitPanel3D = preload("res://ui/hud/unit_panel_3d.gd")

const Palette = preload("res://ui/theme/gbc_palette.gd")

const BUTTON_ROW_H := 48
const BUTTON_GAP := 4
const BUTTON_ROW_W := 280   # two 136 wide buttons and the gap between them

@onready var _panel: UnitPanel3D = %Panel
@onready var _buttons: HBoxContainer = %Buttons
@onready var _confirm: Button = %Confirm
@onready var _cancel: Button = %Cancel

var selected := 0   # 0 = CONFIRM, 1 = CANCEL
var _open := false
var _down := -1   # the button the mouse is holding down, or -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.preferred_side = UnitPanel3D.PanelSide.LEFT
	_confirm.pressed.connect(func() -> void: _choose(0))
	_cancel.pressed.connect(func() -> void: _choose(1))
	# Under the card, centred, inside the tilted viewport. Reparenting can drop the scene owner, and
	# %Confirm / %Cancel are looked up through it, so put it back.
	_panel.set_footer(_buttons, BUTTON_ROW_H)
	for n: Node in [_buttons, _confirm, _cancel]:
		n.owner = self
	_buttons.position = Vector2(roundf((UnitPanel3D.FLAT_W - BUTTON_ROW_W) * 0.5), UnitPanel3D.H_BASE + BUTTON_GAP)
	_buttons.visible = false

## view = UnitView.build(target) (or UnitView.tile), forecast = UnitView.forecast().
func open(view: Dictionary, forecast: Dictionary, camera: Camera3D, anchor: Callable, half_width_world: float) -> void:
	_panel.set_view(view)
	_panel.set_preview(forecast)
	_panel.track(camera, anchor, half_width_world)
	_panel.show_panel()
	_open = true
	_buttons.visible = true
	_down = -1
	_select(0)
	forecast_changed.emit(forecast)

## Keeps the panel where it is and refreshes the numbers (the target's stats changed).
func refresh(view: Dictionary, forecast: Dictionary) -> void:
	if _open:
		_panel.set_view(view, true)
		_panel.set_preview(forecast)
		forecast_changed.emit(forecast)

func close() -> void:
	_open = false
	_panel.set_preview({})
	_panel.hide_panel()
	_buttons.visible = false
	_down = -1
	forecast_changed.emit({})

func is_open() -> bool:
	return _open

func panel() -> UnitPanel3D:
	return _panel

func navigate(dir: Vector2i) -> bool:
	if not _open:
		return false
	_select(clampi(selected + dir.x + dir.y, 0, 1))
	return true

func accept() -> bool:
	if not _open:
		return false
	_choose(selected)
	return true

func _select(i: int) -> void:
	selected = i
	_confirm.text = ("\u25b6 " if i == 0 else "  ") + "CONFIRM"
	_cancel.text = ("\u25b6 " if i == 1 else "  ") + "CANCEL"
	_mark(_confirm, i == 0, _down == 0)
	_mark(_cancel, i == 1, _down == 1)

## The selected button wears the theme's thick "hover" frame; one being held down wears the pressed look.
func _mark(b: Button, on: bool, down: bool) -> void:
	b.remove_theme_color_override("font_color")
	if down:
		b.add_theme_stylebox_override("normal", b.get_theme_stylebox("pressed"))
		b.add_theme_color_override("font_color", Palette.PANEL)
	elif on:
		b.add_theme_stylebox_override("normal", b.get_theme_stylebox("hover"))
	else:
		b.remove_theme_stylebox_override("normal")

## 0 = CONFIRM, 1 = CANCEL, -1 = neither, for a point of the panel quad (the tilted picture).
func _button_at(quad_pos: Vector2) -> int:
	var flat := _panel.to_flat(quad_pos)
	if flat.x < 0.0:
		return -1
	var p := flat - _buttons.position
	if Rect2(_confirm.position, _confirm.size).has_point(p):
		return 0
	if Rect2(_cancel.position, _cancel.size).has_point(p):
		return 1
	return -1

## The mouse over the tilted buttons: hover selects, press and release on the same button chooses it.
## Only events that are on a button are swallowed; everything else carries on to the map.
func _input(event: InputEvent) -> void:
	if not _open or not _panel.visible:
		return
	if not (event is InputEventMouseMotion or event is InputEventMouseButton):
		return
	var hit := _button_at((_panel.make_input_local(event) as InputEventMouse).position)
	if event is InputEventMouseMotion:
		if hit >= 0:
			_select(hit)
			get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if hit >= 0:
			_down = hit
			_select(hit)
			get_viewport().set_input_as_handled()
	elif _down >= 0:
		var held := _down
		_down = -1
		_select(selected)
		get_viewport().set_input_as_handled()
		if hit == held:
			_choose(held)

func _choose(i: int) -> void:
	if not _open:
		return
	if i == 0:
		confirmed.emit()
	else:
		cancelled.emit()
