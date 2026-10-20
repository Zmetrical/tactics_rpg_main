extends PanelContainer
## Attack preview. It uses the same frame, size (702x136) and slot as the battle log box, so the bottom-center
## text box looks the same whether it is showing the preview or the log. Shows: ability name, HIT / CRIT, damage range and
## the target's projected HP. Display only. The target's own panel (bars, rings) sits beside its
## sprite; this box only carries the numbers for the attack about to be confirmed.
## Data comes from UnitView.forecast() (target picked) or UnitView.aim_forecast() (ability selected, no target yet);
## an empty dictionary hides the box.
## Charged casts also get a TILE / UNIT button row at the bottom: TILE (the cast hits whatever stands there when it lands) or
## UNIT (the cast follows the unit). The box only displays the choice and reports presses; battle_view owns the
## state and pushes it back with set_lock().

## The player pressed TILE (false) or UNIT (true).
signal lock_mode_changed(lock_on_unit: bool)

@onready var _title: Label = %FcTitle
@onready var _hit: Label = %FcHit
@onready var _dmg: Label = %FcDmg
@onready var _crit: Label = %FcCrit
@onready var _title_sep: HSeparator = %TitleSep
@onready var _hp: Label = %FcHp
@onready var _foot: Label = %FcFoot
@onready var _sep: HSeparator = %FcSep
@onready var _lock_row: HBoxContainer = %LockRow
@onready var _lock_tile: Button = %LockTile
@onready var _lock_unit: Button = %LockUnit

var _lock_on_unit := false
var _unit_available := true   # false: no unit on the picked tile, so UNIT can't be chosen
var _last: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var group := ButtonGroup.new()   # exactly one of TILE / UNIT is always down
	_lock_tile.button_group = group
	_lock_unit.button_group = group
	_lock_tile.pressed.connect(func() -> void: lock_mode_changed.emit(false))
	_lock_unit.pressed.connect(func() -> void: lock_mode_changed.emit(true))
	_refresh_lock()

## What the lock buttons show. unit_available = false greys UNIT out (a unit lock needs a unit on the tile).
func set_lock(on_unit: bool, unit_available := true) -> void:
	_lock_on_unit = on_unit
	_unit_available = unit_available
	_refresh_lock()
	if visible and not _last.is_empty():
		show_forecast(_last)   # the footer line follows the choice

func show_forecast(fc: Dictionary) -> void:
	if fc.is_empty():
		hide_forecast()
		return
	_last = fc
	# A tiered spell wears its tier in the title ("CHAIN ARC T2"); weapons and untiered abilities show just the name.
	var title := String(fc["ability"]).to_upper()
	if bool(fc.get("tiered", false)):
		title += " T%d" % int(fc.get("tier", 1))
	_title.text = title
	# Ability selected, no target yet ("aim"): the small box with the damage range, the prompt and (charged casts) the
	# TILE / UNIT choice. Target picked: the log-sized box with one number per row (chance, crit, damage), nothing else.
	var aim := bool(fc.get("aim", false))
	custom_minimum_size = Vector2(460, 0) if aim else Vector2(702, 136)
	_hit.visible = not aim
	_dmg.visible = not aim   # the hover box is just the name and the prompt
	_title_sep.visible = not aim   # line between the action name and its numbers
	_crit.visible = not aim
	_hp.visible = false   # the target panel already shows the target's HP
	_hit.text = "%s %s" % [fc["chance_label"], _pct(int(fc["hit"]))]
	_crit.text = "CRIT %s" % _pct(int(fc["crit"]))
	_dmg.text = "DMG %d" % int(fc["dmg_min"]) if int(fc["dmg_min"]) == int(fc["dmg_max"]) else "DMG %d-%d" % [int(fc["dmg_min"]), int(fc["dmg_max"])]
	var lockable := bool(fc.get("lockable", false))
	_lock_row.visible = lockable and aim
	var foot: Array[String] = []
	if aim:
		if String(fc["foot"]) != "":
			foot.append(String(fc["foot"]))
		if int(fc["extra_targets"]) > 0:
			foot.append("+%d MORE" % int(fc["extra_targets"]))
	_foot.text = " ".join(foot)
	_foot.visible = _foot.text != ""
	_sep.visible = _foot.visible   # line between the numbers and the prompt
	visible = true

func hide_forecast() -> void:
	visible = false
	_last = {}

func _refresh_lock() -> void:
	_lock_tile.set_pressed_no_signal(not _lock_on_unit)
	_lock_unit.set_pressed_no_signal(_lock_on_unit)
	_lock_unit.disabled = not _unit_available

static func _pct(v: int) -> String:
	return "--" if v < 0 else "%d%%" % v
