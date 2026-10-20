extends Node
## The battle HUD's single UI state machine. It owns the bottom-center box (action menu OR battle
## log), the attack preview box above it, and three copies of the same unit panel (current unit,
## hovered unit, attack target), and is the only thing that decides which of them is live.
##
## It never calls combat code. Intent leaves through the "out" signals; facts arrive through the
## "in" signals and set_context(). battle_view.gd connects both sides to Battle (see the wiring notes
## in docs/battle_ui_redesign.md). Panels read UnitView dictionaries, never Units directly.

# --- out: what the player asked for -------------------------------------------
## Index into Unit.abilities (Ability has no id field of its own).
signal action_chosen(action_id: int)
## The target confirmed on the target panel. null = a cast aimed at an empty tile.
signal target_confirmed(unit: Unit)
signal end_turn_requested
signal inventory_requested
## The + / - buttons on the hotbar. true = zoom in.
signal zoom_requested(zoom_in: bool)
## Esc / right-click / B while picking a target: the game undoes one aim step, or cancels targeting
## and then calls aim_cancelled().
signal aim_back_requested
## The ability that is already being aimed was clicked again: go up one tier (the game checks the spell has one and the
## unit can pay for it).
signal aim_tier_up_requested
## The TILE / UNIT buttons on the forecast box (charged casts only). true = follow the unit. The game decides
## whether it is allowed and pushes the result back through set_lock_mode().
signal lock_mode_changed(lock_on_unit: bool)
## CANCEL on the target panel: back to target selection, no AP spent, nothing sent to combat.
signal confirm_cancelled
## For tests and tools.
signal state_changed(old_state: int, new_state: int)

# --- in: what the game tells the UI -------------------------------------------
signal log_line_pushed(text: String)
## The confirmed attack has fully played out (rules resolved and the on-map presentation done).
signal attack_resolved
signal unit_stats_changed(unit: Unit)
signal inventory_closed
signal battle_finished

enum State { IDLE, ROOT_MENU, INVENTORY, TARGET_SELECT, CONFIRM, EXECUTING, LOG_PLAYING }
enum Confirm { NONE, ATTACK, END_TURN }

## Every legal transition. _go() refuses anything else.
const TRANSITIONS: Dictionary = {
	State.IDLE: [State.ROOT_MENU, State.LOG_PLAYING],
	State.ROOT_MENU: [State.TARGET_SELECT, State.INVENTORY, State.CONFIRM, State.LOG_PLAYING, State.IDLE],
	State.INVENTORY: [State.ROOT_MENU, State.LOG_PLAYING, State.IDLE],
	State.TARGET_SELECT: [State.CONFIRM, State.ROOT_MENU, State.LOG_PLAYING, State.IDLE],
	State.CONFIRM: [State.ROOT_MENU, State.TARGET_SELECT, State.EXECUTING, State.LOG_PLAYING, State.IDLE],
	State.EXECUTING: [State.LOG_PLAYING, State.ROOT_MENU, State.TARGET_SELECT, State.IDLE],
	State.LOG_PLAYING: [State.IDLE, State.ROOT_MENU, State.TARGET_SELECT, State.CONFIRM],
}

## New log lines take over the box from these states (and return to them afterwards).
const LOG_PREEMPTS: Array[State] = [State.IDLE, State.ROOT_MENU, State.TARGET_SELECT, State.CONFIRM]

const Palette = preload("res://ui/theme/gbc_palette.gd")
const SideTint = preload("res://ui/side_tint.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const Ability = preload("res://scripts/battle/ability.gd")
const UnitView = preload("res://ui/hud/unit_view.gd")
const HotbarScript = preload("res://ui/hud/hotbar.gd")
const BattleLogScript = preload("res://ui/hud/battle_log.gd")
const ForecastBoxScript = preload("res://ui/hud/forecast_box.gd")
const HoverPreviewScript = preload("res://ui/hud/hover_preview.gd")
const TargetPanelScript = preload("res://ui/hud/target_panel.gd")
const UnitPanelScript = preload("res://ui/hud/unit_panel_3d.gd")

var state: State = State.IDLE
var confirm_kind: Confirm = Confirm.NONE

@onready var _bar: HotbarScript = %Hotbar
@onready var _log: BattleLogScript = %BattleLog
@onready var _hover: HoverPreviewScript = %HoverPreview
@onready var _forecast_box: ForecastBoxScript = %ForecastBox
@onready var _target_panel: TargetPanelScript = %TargetPanel
@onready var _active_panel: UnitPanelScript = %ActiveUnitPanel

var _active: Unit = null
var _can_act := false
var _can_end := false
var _hover_unit: Unit = null
var _pending_target: Unit = null
var _locked: Unit = null   # the unit the hover preview is locked to during an attack
var _last_forecast: Dictionary = {}
var _resume: State = State.IDLE
var _attack_active := false
var _unlock_after_log := false   # an enemy attack finished while its log is still held: unlock when it is dismissed
var _aim_id := -1   # the ability being aimed (index into Unit.abilities), or -1
var _aim_tier := 1   # the tier it is being aimed at; battle_view tells us through set_aim_tier()
var _camera: Camera3D = null
var _anchor_provider := Callable()
var _half_world := 1.0

func _ready() -> void:
	log_line_pushed.connect(_on_log_line_pushed)
	attack_resolved.connect(_on_attack_resolved)
	unit_stats_changed.connect(_on_unit_stats_changed)
	inventory_closed.connect(_on_inventory_closed)
	battle_finished.connect(_on_battle_finished)
	_log.finished.connect(_on_log_finished)
	_bar.ability_chosen.connect(_on_action_picked)
	_bar.gear_chosen.connect(func(_slot: int) -> void: _on_inventory_pressed())
	_bar.inventory_pressed.connect(_on_inventory_pressed)
	_bar.end_turn_pressed.connect(_on_end_turn_pressed)
	_bar.end_turn_answered.connect(_on_end_turn_answered)
	_bar.back_pressed.connect(func() -> void: back())
	_bar.zoom_requested.connect(zoom_requested.emit)
	_target_panel.confirmed.connect(_on_target_confirm_pressed)
	_target_panel.cancelled.connect(_cancel_confirm)
	_target_panel.forecast_changed.connect(_forecast_box.show_forecast)
	_forecast_box.lock_mode_changed.connect(lock_mode_changed.emit)
	_apply()

## camera: the stage camera. anchor_provider: Callable(subject) -> Vector3, the world point a panel
## follows; subject is a Unit, or a Vector2i tile for a cast with no unit on it.
## half_width_world: half the sprite width in world units.
func setup(camera: Camera3D, anchor_provider: Callable, half_width_world: float, map_center: Callable = Callable()) -> void:
	_camera = camera
	_anchor_provider = anchor_provider
	_half_world = half_width_world
	_active_panel.track(camera, func() -> Vector3: return _anchor_provider.call(_active) if _active != null else Vector3.ZERO, half_width_world)
	_hover.track(camera, func() -> Vector3: return _anchor_provider.call(_hover_subject()) if _hover_subject() != null else Vector3.ZERO, half_width_world)

	# The current unit's panel follows the map centre (so it reacts to camera rotation);
	# the hover and target panels always sit on the opposite side.
	_active_panel.side_mode = UnitPanelScript.SideMode.MAP_CENTER
	_active_panel.map_center = map_center
	for p: UnitPanelScript in [_hover.panel(), _target_panel.panel()]:
		p.side_mode = UnitPanelScript.SideMode.OPPOSITE
		p.opposite_of = _active_panel

func state_name() -> String:
	return State.keys()[state]

# --- Context from the game ------------------------------------------------------

## Called whenever the current unit or its ability to act may have changed. A different unit means
## a new turn: the UI goes back to the root menu on a player turn, and hides the menu otherwise.
func set_context(unit: Unit, can_act: bool, can_end_turn: bool) -> void:
	var turn_changed := unit != _active
	_active = unit
	_can_act = can_act
	_can_end = can_end_turn
	if unit == null:
		_active_panel.hide_panel()
		_go(State.IDLE)
		return
	_active_panel.set_view(UnitView.build(unit))
	_active_panel.show_panel()
	if turn_changed:
		_on_turn_changed()
	else:
		_apply()

## Mouse hover over a reachable tile: the movement bar marks what walking there would spend.
## cost <= 0 clears the preview.
func set_move_preview(cost: int) -> void:
	_bar.set_move_preview(cost)

## Mouse hover over a unit (or null). The hover panel is the current-unit panel for that unit. It
## ignores this while locked to an attack target, stays hidden over the current unit (whose own panel
## is already up) and while the target panel is open.
func set_hover_unit(unit: Unit) -> void:
	var same := unit != null and unit == _hover_unit
	_hover_unit = unit
	if unit == null or unit == _active or _target_panel.is_open():
		_hover.clear()
	else:
		_hover.show_view(UnitView.build(unit), same)

## The unit whose panel the hover panel follows: the locked attack target, else the hovered unit.
func _hover_subject() -> Unit:
	return _locked if _hover.is_locked() else _hover_unit

## The tier of the spell being aimed changed (clicked up, key 1 / 2 / 3, or Esc reset it): the slot badge and the AP preview follow.
func set_aim_tier(tier: int) -> void:
	_aim_tier = tier
	_apply()

## The Tile / Unit lock choice the forecast box buttons show. unit_available = false greys UNIT out
## (the picked tile has nobody on it).
func set_lock_mode(lock_on_unit: bool, unit_available := true) -> void:
	_forecast_box.set_lock(lock_on_unit, unit_available)

## The aim finished backing out (targeting cancelled): back to the plain bar.
func aim_cancelled() -> void:
	if state == State.TARGET_SELECT or (state == State.LOG_PLAYING and _resume == State.TARGET_SELECT):
		_aim_id = -1
		_aim_tier = 1
		_enter(State.ROOT_MENU)

## A target was picked on the map. forecast = UnitView.forecast(...); target = null for an empty tile.
func begin_confirm(target: Unit, cell: Vector2i, forecast: Dictionary) -> void:
	if state != State.TARGET_SELECT:
		return
	_pending_target = target
	_last_forecast = forecast
	var view := UnitView.build(target) if target != null else UnitView.tile(cell, Palette.INK_LIGHT)
	var subject: Variant = target if target != null else cell
	_hover.suppress()   # the target panel is the target's panel now
	_target_panel.open(view, forecast, _camera, func() -> Vector3: return _anchor_provider.call(subject), _half_world)
	confirm_kind = Confirm.ATTACK
	_enter(State.CONFIRM)

## An attack the player did not confirm on the target panel (enemy turn, opportunity attack, a charged
## cast landing) is about to play on `victim`: show its panel, locked, until unlock_victim().
func lock_victim(victim: Unit) -> void:
	if victim == null or _attack_active:
		return
	_locked = victim
	_unlock_after_log = false
	# Same as the player's own attack: the log of this attack waits for Enter / a click on its last line.
	_log.hold_last = true
	_hover.lock(UnitView.build(victim))

## That attack has finished playing: back to plain hover.
func unlock_victim() -> void:
	if _attack_active or not _hover.is_locked():
		return
	if _log.is_busy():
		_unlock_after_log = true   # keep the victim's panel up until the held log is dismissed
		return
	_log.hold_last = false
	_locked = null
	_hover.unlock()
	set_hover_unit(_hover_unit)

func is_log_busy() -> bool:
	return _log.is_busy()

func is_hover_locked() -> bool:
	return _hover.is_locked()

# --- State machine ---------------------------------------------------------------

## The state the UI rests in between actions.
func _rest_state() -> State:
	return State.ROOT_MENU if _active != null and _active.side == Unit.Side.PLAYER else State.IDLE

## The state whose face is on screen: a playing log hides the menu but not what is behind it. The log of the
## player's own attack is the exception: it is part of the attack, so the HUD stays hidden (as when executing)
## until the player dismisses it.
func _face_state() -> State:
	if state != State.LOG_PLAYING:
		return state
	return State.EXECUTING if _attack_active else _resume

## Go to `next`, unless the log is playing: then the log takes the box and `next` is where we
## return when it finishes. EXECUTING and INVENTORY are never interrupted.
func _enter(next: State) -> void:
	if _log.is_busy() and next != State.INVENTORY and next != State.EXECUTING and next != State.LOG_PLAYING:
		_resume = next
		next = State.LOG_PLAYING
	_go(next)

func _go(next: State) -> void:
	if next == state:
		_apply()
		return
	if not (TRANSITIONS[state] as Array).has(next):
		push_error("BattleUI: illegal transition %s -> %s" % [State.keys()[state], State.keys()[next]])
		return
	var old := state
	state = next
	_apply()
	state_changed.emit(old, next)

func _on_turn_changed() -> void:
	_aim_id = -1
	_aim_tier = 1
	_target_panel.close()
	confirm_kind = Confirm.NONE
	_pending_target = null
	if state == State.EXECUTING or (state == State.LOG_PLAYING and _attack_active):
		_resume = _rest_state()   # the attack sequence finishes first, then the new turn's menu
		return
	if state == State.LOG_PLAYING:
		_resume = _rest_state()
		_apply()
		return
	_enter(_rest_state())

func _apply() -> void:
	if not is_node_ready():
		return
	var face := _face_state()
	var log_face := state == State.LOG_PLAYING or (state == State.EXECUTING and _log.is_busy())
	_log.visible = log_face
	# The hotbar stays up under the log (the log sits above it); the log just locks it.
	var bar_states: Array[State] = [State.ROOT_MENU, State.TARGET_SELECT, State.CONFIRM, State.INVENTORY]
	var show_bar := _active != null and bar_states.has(face)
	# The attack preview (target panel + forecast box) is the whole interface while a target is picked: the hotbar
	# has nothing to do there (CONFIRM / CANCEL / Esc all live on the target panel), so it steps aside.
	if face == State.CONFIRM and confirm_kind == Confirm.ATTACK:
		show_bar = false
	_bar.visible = show_bar
	if show_bar:
		var mode := HotbarScript.Mode.LOCKED
		if not log_face:
			match face:
				State.ROOT_MENU:
					mode = HotbarScript.Mode.READY
				State.TARGET_SELECT:
					mode = HotbarScript.Mode.AIMING
				State.CONFIRM:
					mode = HotbarScript.Mode.CONFIRM
		_bar.show_data(UnitView.hotbar(_active, _can_act))
		_bar.set_mode(mode, _can_end)
		var aiming := face == State.TARGET_SELECT or (face == State.CONFIRM and confirm_kind == Confirm.ATTACK)
		_bar.set_aiming(_aim_id if aiming else -1, _aim_tier)
		_bar.show_end_confirm(face == State.CONFIRM and confirm_kind == Confirm.END_TURN)
	if face != State.CONFIRM or confirm_kind != Confirm.ATTACK:
		if _target_panel.is_open() and state != State.LOG_PLAYING and state != State.EXECUTING:
			_target_panel.close()
			set_hover_unit(_hover_unit)
	# An ability is selected and waiting for a target: the forecast box names it (and its tier). Once a target is
	# picked the target panel feeds the box real numbers; in every other state the box is not ours to show.
	var aimed := _aimed_ability()
	if face == State.TARGET_SELECT and aimed != null:
		_forecast_box.show_forecast(UnitView.aim_forecast(aimed, _aim_tier))
	elif not _target_panel.is_open():
		_forecast_box.hide_forecast()

## The ability being aimed (from the hotbar id), or null.
func _aimed_ability() -> Ability:
	if _active == null or _aim_id < 0 or _aim_id >= _active.abilities.size():
		return null
	return _active.abilities[_aim_id]

# --- Bar choices ----------------------------------------------------------------------

## An ability slot was picked. From the plain bar this starts aiming; while already aiming it switches
## to the new ability. Picking the ability that is already being aimed goes up a tier instead (click twice for
## Tier 2, three times for Tier 3).
func _on_action_picked(action_id: int) -> void:
	if state != State.ROOT_MENU and state != State.TARGET_SELECT:
		return
	if state == State.TARGET_SELECT and action_id == _aim_id:
		aim_tier_up_requested.emit()
		return
	_aim_id = action_id
	_aim_tier = 1
	if state == State.ROOT_MENU:
		_enter(State.TARGET_SELECT)
	else:
		_apply()
	action_chosen.emit(action_id)

func _on_end_turn_pressed() -> void:
	if state != State.ROOT_MENU:
		return
	# No confirmation: END TURN ends the turn right away.
	_go(State.IDLE)
	end_turn_requested.emit()

func _on_inventory_pressed() -> void:
	if state != State.ROOT_MENU:
		return
	_enter(State.INVENTORY)
	inventory_requested.emit()

func _on_end_turn_answered(yes: bool) -> void:
	if state != State.CONFIRM or confirm_kind != Confirm.END_TURN:
		return
	confirm_kind = Confirm.NONE
	if yes:
		_go(State.IDLE)
		end_turn_requested.emit()
	else:
		_enter(State.ROOT_MENU)

func _on_target_confirm_pressed() -> void:
	if state != State.CONFIRM or confirm_kind != Confirm.ATTACK:
		return
	var target := _pending_target
	_target_panel.close()
	confirm_kind = Confirm.NONE
	_attack_active = true
	_log.hold_last = true   # the attack's log waits for Enter / a click on its last line before the HUD returns
	_locked = target
	if target != null:
		_hover.lock(UnitView.build(target))
	_go(State.EXECUTING)
	target_confirmed.emit(target)

func _cancel_confirm() -> void:
	if state != State.CONFIRM or confirm_kind != Confirm.ATTACK:
		return
	_target_panel.close()
	confirm_kind = Confirm.NONE
	_pending_target = null
	set_hover_unit(_hover_unit)   # hover panel comes back if the mouse is still over a unit
	_enter(State.TARGET_SELECT)
	confirm_cancelled.emit()

## Back goes up exactly one layer.
func back() -> bool:
	match _face_state():
		State.TARGET_SELECT:
			aim_back_requested.emit()
		State.CONFIRM:
			if confirm_kind == Confirm.END_TURN:
				confirm_kind = Confirm.NONE
				_enter(State.ROOT_MENU)
			else:
				_cancel_confirm()
		_:
			return false
	return true

# --- Facts from the game --------------------------------------------------------------

func _on_log_line_pushed(text: String) -> void:
	_log.push_line(text)
	if LOG_PREEMPTS.has(state):
		_resume = state
		_go(State.LOG_PLAYING)
	else:
		_apply()   # EXECUTING / INVENTORY / LOG_PLAYING: just refresh which face is up

func _on_log_finished() -> void:
	if state == State.LOG_PLAYING:
		if _attack_active:
			_finish_attack()
		else:
			_log.hold_last = false
			if _unlock_after_log:
				_unlock_after_log = false
				_locked = null
				_hover.unlock()
				set_hover_unit(_hover_unit)
			_go(_resume)
	elif state == State.EXECUTING:
		_apply()
		# Rules and presentation may still be running; attack_resolved decides.

func _on_attack_resolved() -> void:
	if not _attack_active or state != State.EXECUTING:
		return
	if _log.is_busy():
		_resume = _rest_state()
		_go(State.LOG_PLAYING)
	else:
		_finish_attack()

## Unlock and go back to the menu once BOTH the attack and its log lines are done. The ability that was just used
## stays selected (back to aiming it) when the unit can still use it; otherwise the plain menu.
func _finish_attack() -> void:
	_attack_active = false
	_log.hold_last = false
	_pending_target = null
	_locked = null
	_hover.unlock()
	set_hover_unit(_hover_unit)
	var again := _aimed_ability()
	if again != null and _rest_state() == State.ROOT_MENU and _can_act and _active.can_use(again):
		_aim_tier = 1
		_go(State.TARGET_SELECT)
		action_chosen.emit(_aim_id)   # battle_view re-enters targeting (and calls aim_cancelled() if the game refuses)
		return
	_aim_id = -1
	_go(_rest_state())

## _apply() only reads HUD state (never `unit`), and _refresh_hud emits this for every unit on the map, so it runs
## only when this unit is one the HUD actually shows. Was: a full hotbar rebuild per unit per refresh.
func _on_unit_stats_changed(unit: Unit) -> void:
	var shown := false
	if unit == _active:
		_active_panel.set_view(UnitView.build(unit))
		shown = true
	if _hover.is_locked() and unit == _locked:
		_hover.update_locked(UnitView.build(unit))
		shown = true
	elif unit == _hover_unit and unit != _active and not _target_panel.is_open() and not _hover.is_locked():
		_hover.show_view(UnitView.build(unit), true)
		shown = true
	if unit == _pending_target and _target_panel.is_open():
		_target_panel.refresh(UnitView.build(unit), _last_forecast)
		shown = true
	if shown and [State.ROOT_MENU, State.TARGET_SELECT].has(_face_state()):
		_apply()

func _on_inventory_closed() -> void:
	if state == State.INVENTORY:
		_enter(State.ROOT_MENU)

func _on_battle_finished() -> void:
	_target_panel.close()
	confirm_kind = Confirm.NONE
	_attack_active = false
	_log.hold_last = false
	_locked = null
	_hover.unlock()
	_go(State.IDLE)

# --- Input -----------------------------------------------------------------------------

## battle_view calls this first from _unhandled_input. true = the UI used the event.
func handle_input(event: InputEvent) -> bool:
	if state == State.IDLE or state == State.INVENTORY:
		return false
	var clicked := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	var left_click := clicked and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	var right_click := clicked and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT
	var accept := event.is_action_pressed("ui_accept") or left_click
	var cancel := event.is_action_pressed("ui_cancel") or right_click
	var dir := _direction(event)

	# Text on screen: a press types it out, then advances it.
	if _log.visible:
		if accept:
			_log.advance_input()
			return true
		return clicked

	match state:
		State.ROOT_MENU:
			if dir != Vector2i.ZERO:
				return _bar.navigate(dir)
			if event.is_action_pressed("ui_accept"):
				return _bar.accept()
			if cancel:
				return back()
		State.TARGET_SELECT:
			if cancel:
				return back()
		State.CONFIRM:
			if confirm_kind == Confirm.END_TURN:
				if dir != Vector2i.ZERO:
					return _bar.navigate(dir)
				if event.is_action_pressed("ui_accept"):
					return _bar.accept()
			else:
				if dir != Vector2i.ZERO:
					return _target_panel.navigate(dir)
				if event.is_action_pressed("ui_accept"):
					return _target_panel.accept()
			if cancel:
				return back()
			return clicked   # clicks elsewhere must not re-aim while the panel is open
		State.EXECUTING:
			return clicked
	return false

static func _direction(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("ui_left", true):
		return Vector2i.LEFT
	if event.is_action_pressed("ui_right", true):
		return Vector2i.RIGHT
	if event.is_action_pressed("ui_up", true):
		return Vector2i.UP
	if event.is_action_pressed("ui_down", true):
		return Vector2i.DOWN
	return Vector2i.ZERO
