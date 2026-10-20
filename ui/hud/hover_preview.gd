extends Control
## Hover view: the same unit panel as the current unit (portrait, name, team, AP / MV, HP / Magic /
## Armor bars with Fracture and Shred rings), shown beside whichever unit the mouse is over.
## It can be LOCKED to one unit (during an attack); while locked, hover cannot change it.

const UnitPanel3D = preload("res://ui/hud/unit_panel_3d.gd")

@onready var _panel: UnitPanel3D = %Panel

var _locked := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.preferred_side = UnitPanel3D.PanelSide.LEFT   # the current unit's panel is on the right
	visible = true   # this node is only a holder; the panel inside decides what is on screen

## The panel follows `anchor` (Callable -> world Vector3 of the shown unit's chest).
func track(camera: Camera3D, anchor: Callable, half_width_world: float) -> void:
	_panel.track(camera, anchor, half_width_world)

func panel() -> UnitPanel3D:
	return _panel

## True while a unit's panel is on screen.
func is_showing() -> bool:
	return _panel.is_active()

## Hover shows `view`. Ignored while locked. `same_unit` = the same unit as before (bars slide
## instead of snapping).
func show_view(view: Dictionary, same_unit: bool = false) -> void:
	if _locked:
		return
	_show(view, same_unit)

## The mouse left every unit. Ignored while locked.
func clear() -> void:
	if _locked:
		return
	_panel.hide_panel()

func lock(view: Dictionary) -> void:
	_locked = true
	_show(view, false)

## Fresh numbers for the locked unit (bars slide to them).
func update_locked(view: Dictionary) -> void:
	if _locked:
		_show(view, true)

func unlock() -> void:
	_locked = false
	_panel.hide_panel()

func is_locked() -> bool:
	return _locked

## Hides the panel without touching the lock (the target panel is taking over).
func suppress() -> void:
	_panel.hide_panel()

func _show(view: Dictionary, same_unit: bool) -> void:
	_panel.set_view(view, same_unit)
	_panel.show_panel()
