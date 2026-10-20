> **Note:** the layered ActionMenu described below was replaced by the hotbar. See `docs/hotbar.md`.

# Battle UI redesign

Godot 4.7, typed GDScript. Everything below was run: the scene was rendered under a virtual display and driven with real input events, and `tests/test_battle_ui.gd` (48 checks) passes. Your 10 existing test files give identical results before and after (their 6 pre-existing failures are unrelated: the Sprite3D-count smoke checks and `compact mode` in vitals).

Screens: `docs/screens/hover_preview.png`, `docs/screens/target_confirm.png`, `docs/screens/bottom_box_layers.png`.

## 1. Assumptions

1. **Break / Shred**: Break (counters Magic Shield) = `Unit.shield_break_stacks`, Shred (counters Armor) = `Unit.armor_shred_stacks`, both 0..`CombatTuning.MAX_STACKS` (7). Rings sit left of Magic Shield and Armor respectively.
2. **Pseudo-3D**: the flat panel is drawn in a `SubViewport`, then a canvas shader tapers and lifts one edge, pixel for pixel (no filtering). The CONFIRM / CANCEL buttons stay unskewed under the panel so mouse hit boxes match what is drawn.
3. **Palette**: each new panel uses INK / INK_LIGHT / BG / PANEL plus the side accent (blue player, red enemy). So HP is drawn in ink (the old green/yellow/red HP thresholds are not used in the new panels), and the Magic Shield bar and Break ring take the accent. Bar captions and `n/max` count as part of the bar. The portrait shows your sprite art as it is.
4. **"Bottom-right target panel"** = the hover preview. It locks to the primary target (for an area spell, the unit on the clicked tile, else the first victim).
5. **Kept from the old bar**: spell tier stays on keys 1/2/3, and the old Tile/Unit lock buttons became the **L** key while aiming. Choosing a tile or aiming (TARGET_SELECT, MOVE) stays mouse-driven because the project has no map cursor; only the menus and the confirm panel are keyboard/controller driven. "B" is the gamepad B button (`ui_cancel`).

## 2. Layout wireframes

Bottom bar, root layer (the center box is 702x136):

```
 (left empty)     +----------------------------------+ +-------------------------+   +-----------------------+
                  | > ATTACK        INVENTORY        | | Use a weapon or a spell.|   | HP    [########--] 7/12|
                  |   MOVE          END TURN         | |                         |   | (5)MAGIC [#####---] .. |
                  +----------------------------------+ +-------------------------+   | (3)ARMOR [####-----] ..|
                       action menu (2x2, ▶ cursor)            description box        +-----------------------+
                                                                                          hover preview
```

Attack layer:

```
                  +----------------------------------+ +-------------------------+
                  |  WEAPON  [SPELL ]                | | Fire Bolt               |
                  | > FIRE BOLT              1 AP    | | 1 AP | Range 6          |
                  |   BURNING BURST          1 AP    | | Attack roll | 1d10      |
                  |   CHAIN ARC              1 AP  ▼ | | magical                 |
                  +----------------------------------+ +-------------------------+
```

While text plays (the log owns the whole center box):

```
                  +--------------------------------------------------------------+
                  | Mage uses Fire Bolt                                          |
                  | Mage -> Goblin: d20 17, total 22 vs AC 15 (normal) HIT, 6 dmg|
                  |                                                           ▼  |
                  +--------------------------------------------------------------+
```

Target confirmation (world space, anchored to sprites):

```
   +--------------+                 +--------------+
   |<>  MAGE      \                 |<> GOBLIN     /|
   |    PLAYER    |    (mage)  (gob)|   ENEMY      |
   |    AP 2/8 .. /                 |   FIRE BOLT  |
   +--------------+                 |   HIT 42% CRIT 0%
     right edge recedes             |   DMG 1-10   |
                                    |   HP 7 > 1 (-6)
                                    +--------------+
                                    | > CONFIRM    CANCEL |
```

## 3. UI state machine

States: `IDLE, ROOT_MENU, ATTACK_MENU, INVENTORY, MOVE, TARGET_SELECT, CONFIRM, EXECUTING, LOG_PLAYING`. Back = right-click / Esc / gamepad B. `CONFIRM` has two kinds: attack confirm and END TURN confirm.

| State | Input / event | Next state |
|---|---|---|
| IDLE | player's turn starts (`set_context`) | ROOT_MENU |
| IDLE | `log_line_pushed` | LOG_PLAYING (back to IDLE after) |
| ROOT_MENU | ATTACK | ATTACK_MENU |
| ROOT_MENU | INVENTORY (emits `inventory_requested`) | INVENTORY |
| ROOT_MENU | MOVE (emits `move_requested`) | MOVE |
| ROOT_MENU | END TURN | CONFIRM (end turn) |
| ROOT_MENU | Back | stays |
| ATTACK_MENU | pick usable action (emits `action_chosen`) | TARGET_SELECT |
| ATTACK_MENU | left/right | switch WEAPON / SPELL tab (same state) |
| ATTACK_MENU | Back | ROOT_MENU |
| INVENTORY | equipment window closed (`inventory_closed`) | ROOT_MENU |
| MOVE | tile walked (`move_finished`) | ROOT_MENU |
| MOVE | Back | ROOT_MENU |
| TARGET_SELECT | click valid target (`begin_confirm`) | CONFIRM (attack) |
| TARGET_SELECT | Back (emits `aim_back_requested`; game undoes an aim step or cancels, then `aim_cancelled()`) | stays / ATTACK_MENU |
| CONFIRM (attack) | CONFIRM (emits `target_confirmed`) | EXECUTING |
| CONFIRM (attack) | CANCEL button / Back | TARGET_SELECT (emits `confirm_cancelled`, no AP spent) |
| CONFIRM (end turn) | YES (emits `end_turn_requested`) | IDLE |
| CONFIRM (end turn) | NO / Back | ROOT_MENU |
| EXECUTING | `attack_resolved`, log already done | ROOT_MENU (IDLE on an enemy turn); hover unlocks |
| EXECUTING | `attack_resolved`, log still playing | LOG_PLAYING |
| LOG_PLAYING | log finishes, attack sequence active | ROOT_MENU / IDLE; hover unlocks |
| LOG_PLAYING | log finishes, otherwise | the state it interrupted |
| ROOT, ATTACK, MOVE, TARGET_SELECT, CONFIRM | `log_line_pushed` | LOG_PLAYING (returns to the interrupted state) |
| LOG_PLAYING / EXECUTING | accept / left click | types out the line, then advances it |
| any | `battle_finished` | IDLE |

`BattleUI.TRANSITIONS` holds this table; `_go()` refuses and logs any other jump.

## 4. Scene trees

```
BattleLog (PanelContainer)               # ui/hud/battle_log.tscn
├─ Text (RichTextLabel)                  # typewriter, scroll follows the newest line
└─ Arrow (Label "▼")                     # bottom-right, blinks while a line waits

ActionMenu (HBoxContainer)               # ui/hud/action_menu.tscn
├─ MenuPanel (PanelContainer)
│  └─ Layers (VBoxContainer)
│     ├─ RootGrid (GridContainer, 2 cols)         # 4 Buttons, ▶ cursor
│     ├─ AttackLayer (VBoxContainer)
│     │  ├─ Tabs (HBoxContainer)                  # WEAPON | SPELL
│     │  ├─ List (VBoxContainer)                  # 3 rows: name + AP cost
│     │  └─ More (Label "▼")
│     └─ EndLayer (VBoxContainer)                 # "END TURN?" YES / NO
└─ DescPanel (PanelContainer)
   └─ Description (Label)                         # range, dice, type

UnitPanel3D (Control)                    # ui/hud/unit_panel_3d.tscn
├─ Screen (TextureRect + ShaderMaterial)          # shows the viewport through the skew shader
└─ Viewport (SubViewport, transparent)
   └─ Flat (PanelContainer)
      └─ Rows (VBoxContainer)
         ├─ Header (HBoxContainer)
         │  ├─ Portrait (Control, diamond_portrait.gd)
         │  └─ Info (VBoxContainer): NameLabel, TeamTag, Stats
         └─ Forecast (VBoxContainer, hidden unless target panel): FcHit, FcDmg, FcHp, FcFoot

HoverPreview (PanelContainer)            # ui/hud/hover_preview.tscn
└─ Rows (VBoxContainer)
   ├─ HpRow:     RingGap (spacer) | HpBar (stat_bar.gd)
   ├─ ShieldRow: BreakMeter (circle_meter.gd) | ShieldBar (stat_bar.gd)
   └─ ArmorRow:  ShredMeter (circle_meter.gd) | ArmorBar (stat_bar.gd)

CircleMeter (Control)                    # one script, no children: draws an Image + the number

TargetPanel (Control, full rect)         # ui/hud/target_panel.tscn
├─ Panel (UnitPanel3D instance, anchored RIGHT of the enemy sprite)
└─ Buttons (HBoxContainer): Confirm, Cancel       # unskewed, under the panel

BattleUI (Node)                          # the state machine; finds the above by unique name
```

`scenes/battle.tscn` now holds: `UI/WorldPanels` (ActiveUnitPanel, TargetPanel), the HUD `BottomRow` with `CenterBox` (ActionMenu + BattleLog stacked) and `HoverPreview` bottom-right, and a `BattleUI` node.

## 5. GDScript

Files (all new, under `ui/hud/` unless noted): `unit_view.gd`, `stat_bar.gd`, `circle_meter.gd`, `diamond_portrait.gd`, `unit_panel_3d.gd`, `hover_preview.gd`, `battle_log.gd`, `action_menu.gd`, `target_panel.gd`, `battle_ui.gd`, `shaders/pseudo3d_panel.gdshader`, `tests/test_battle_ui.gd`. Scenes are in the project zip. `UnitView` is where your existing unit data is connected.

**`ui/hud/unit_view.gd`**

```gdscript
extends RefCounted
## THE connection point between your unit data and the new HUD.
##
## Every HUD widget (unit panel, hover preview, target panel, action menu) renders plain
## Dictionaries and never sees a Unit. To feed the HUD from different data, change only this file.
## Field mapping, all read from scripts/battle/unit.gd:
##   hp / max_hp                      -> unit.hp / unit.max_hp
##   shield / max_shield (Magic Shield) -> unit.magic_shield / unit.max_magic_shield
##   armor / max_armor                -> unit.physical_armor / unit.max_physical_armor
##   break (0-7, counters Magic Shield) -> unit.shield_break_stacks
##   shred (0-7, counters Armor)        -> unit.armor_shred_stacks
##   ap / move                        -> unit.ap, unit.movement (and max_ap, move_range)

const Ability = preload("res://scripts/battle/ability.gd")
const AbilityText = preload("res://ui/ability_text.gd")
const AttackForecast = preload("res://ui/attack_forecast.gd")
const SideTint = preload("res://ui/side_tint.gd")
const Tuning = preload("res://scripts/battle/combat_tuning.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const UnitSprites = preload("res://scripts/battle/unit_sprites.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")

## Everything the unit panel, hover preview and target panel draw.
static func build(u: Unit) -> Dictionary:
	var view := {
		"name": u.unit_name,
		"team": SideTint.side_name(u.side).to_upper(),
		"accent": SideTint.color_for(u.side),
		"letter": u.unit_name.substr(0, 1).to_upper(),
		"hp": u.hp, "max_hp": u.max_hp,
		"shield": u.magic_shield, "max_shield": u.max_magic_shield,
		"armor": u.physical_armor, "max_armor": u.max_physical_armor,
		"break": u.shield_break_stacks,
		"shred": u.armor_shred_stacks,
		"max_stacks": Tuning.MAX_STACKS,
		"ap": u.ap, "max_ap": u.max_ap,
		"move": u.movement, "max_move": u.move_range,
		"sprite_tex": null,
		"sprite_rect": Rect2(),
	}
	# Same lookup stage_3d.gd uses to pick the unit's sprite block.
	var file_name := u.data.resource_path.get_file().get_basename()
	var tex := UnitSprites.sheet_for(file_name)
	if tex != null:
		view["sprite_tex"] = tex
		view["sprite_rect"] = UnitSprites.frame_rect(file_name, UnitSprites.Row.FRONT, UnitSprites.IDLE_FRAME)
	return view

## Stand-in for an area / tile-locked cast aimed at a tile with no unit on it.
static func tile(cell: Vector2i, accent: Color) -> Dictionary:
	return {
		"name": "TILE %d,%d" % [cell.x, cell.y], "team": "AREA", "accent": accent, "letter": "+",
		"hp": 0, "max_hp": 0, "shield": 0, "max_shield": 0, "armor": 0, "max_armor": 0,
		"break": 0, "shred": 0, "max_stacks": Tuning.MAX_STACKS,
		"ap": 0.0, "max_ap": 0.0, "move": 0, "max_move": 0, "sprite_tex": null, "sprite_rect": Rect2(),
	}

## Action-menu rows, in the unit's own ability order. `id` is the index into unit.abilities
## (Ability has no id field, so the index is the action_id; see BattleUI.action_chosen).
static func actions(u: Unit, can_act: bool) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in u.abilities.size():
		var a: Ability = u.abilities[i]
		rows.append({
			"id": i,
			"name": a.display_name,
			"cost": "%s AP" % AbilityText.ap_str(a.ap_cost_for_tier(1)),
			"usable": can_act and u.can_use(a),
			"spell": AbilityText.is_spell(a),
			"detail": AbilityText.brief(a),
		})
	return rows

## Attack preview for the target panel. `row` is an AttackForecast.build() dictionary (plus an
## optional "scale" for spell echoes). Display only: the soak order mirrors Unit.take_damage
## (resistance if enabled, then the matching ablative pool, the rest hits HP) on the AVERAGE roll.
static func forecast(row: Dictionary, ability: Ability, tier: int, extra_targets: int, foot: String) -> Dictionary:
	var defender: Unit = row["defender"]
	var dice := _dice(ability.damage_dice)
	var scale: float = float(row.get("scale", 1.0))
	var lo := roundi(maxi(dice.x + ability.damage_bonus, 0) * scale)
	var hi := roundi(maxi(dice.x * dice.y + ability.damage_bonus, 0) * scale)
	var avg: int = int(row["dmg"])
	var core := _core_damage(defender, ability, avg)
	return {
		"ability": ability.display_name,
		"tier": tier,
		"chance_label": String(row["chance_label"]).to_upper(),
		"hit": int(row["hit"]),
		"crit": int(row["crit"]),
		"dmg_min": lo, "dmg_max": hi,
		"hp_now": defender.hp,
		"hp_after": maxi(defender.hp - core, 0),
		"extra_targets": extra_targets,
		"foot": foot,
	}

## Forecast for a cast aimed at a tile with nobody on it (charged / area spells).
static func forecast_empty(ability: Ability, tier: int, foot: String) -> Dictionary:
	var dice := _dice(ability.damage_dice)
	return {
		"ability": ability.display_name, "tier": tier, "chance_label": "HIT", "hit": -1, "crit": -1,
		"dmg_min": maxi(dice.x + ability.damage_bonus, 0), "dmg_max": maxi(dice.x * dice.y + ability.damage_bonus, 0),
		"hp_now": 0, "hp_after": 0, "extra_targets": 0, "foot": foot,
	}

static func _dice(text: String) -> Vector2i:
	if text == "":
		return Vector2i.ZERO
	var parts := text.to_lower().split("d")
	return Vector2i(parts[0].to_int(), parts[1].to_int())

static func _core_damage(defender: Unit, ability: Ability, amount: int) -> int:
	var physical := ability.damage_type == Ability.DamageType.PHYSICAL
	var dealt := amount
	if Tuning.APPLY_RESISTANCE_IN_TAKE_DAMAGE:
		var resistance := defender.physical_resistance if physical else defender.magic_resistance
		dealt = maxi(roundi(amount * (1.0 - resistance)), 0)
	var defense := defender.physical_armor if physical else defender.magic_shield
	return dealt - mini(dealt, defense)
```

**`ui/hud/battle_ui.gd`**

```gdscript
extends Node
## The battle HUD's single UI state machine. It owns the bottom-center box (action menu OR battle
## log), the current-unit panel, the target panel and the bottom-right hover preview, and is the
## only thing that decides which of them is live.
##
## It never calls combat code. Intent leaves through the "out" signals; facts arrive through the
## "in" signals and set_context(). battle_view.gd connects both sides to Battle (see the wiring notes
## in docs/battle_ui_redesign.md). Panels read UnitView dictionaries, never Units directly.

# --- out: what the player asked for -------------------------------------------
## Index into Unit.abilities (Ability has no id field of its own).
signal action_chosen(action_id: int)
## The target confirmed on the target panel. null = a cast aimed at an empty tile.
signal target_confirmed(unit: Unit)
signal move_requested
signal end_turn_requested
signal inventory_requested
## Esc / right-click / B while picking a target: the game undoes one aim step, or cancels targeting
## and then calls aim_cancelled().
signal aim_back_requested
## CANCEL on the target panel: back to target selection, no AP spent, nothing sent to combat.
signal confirm_cancelled
## For tests and tools.
signal state_changed(old_state: int, new_state: int)

# --- in: what the game tells the UI -------------------------------------------
signal log_line_pushed(text: String)
## The confirmed attack has fully played out (rules resolved and the on-map presentation done).
signal attack_resolved
signal unit_stats_changed(unit: Unit)
signal move_finished
signal inventory_closed
signal battle_finished

enum State { IDLE, ROOT_MENU, ATTACK_MENU, INVENTORY, MOVE, TARGET_SELECT, CONFIRM, EXECUTING, LOG_PLAYING }
enum Confirm { NONE, ATTACK, END_TURN }

## Every legal transition. _go() refuses anything else.
const TRANSITIONS: Dictionary = {
	State.IDLE: [State.ROOT_MENU, State.LOG_PLAYING],
	State.ROOT_MENU: [State.ATTACK_MENU, State.INVENTORY, State.MOVE, State.CONFIRM, State.LOG_PLAYING, State.IDLE],
	State.ATTACK_MENU: [State.ROOT_MENU, State.TARGET_SELECT, State.LOG_PLAYING, State.IDLE],
	State.INVENTORY: [State.ROOT_MENU, State.LOG_PLAYING, State.IDLE],
	State.MOVE: [State.ROOT_MENU, State.LOG_PLAYING, State.IDLE],
	State.TARGET_SELECT: [State.ATTACK_MENU, State.CONFIRM, State.ROOT_MENU, State.LOG_PLAYING, State.IDLE],
	State.CONFIRM: [State.ROOT_MENU, State.TARGET_SELECT, State.EXECUTING, State.LOG_PLAYING, State.IDLE],
	State.EXECUTING: [State.LOG_PLAYING, State.ROOT_MENU, State.IDLE],
	State.LOG_PLAYING: [State.IDLE, State.ROOT_MENU, State.ATTACK_MENU, State.MOVE, State.TARGET_SELECT, State.CONFIRM],
}

## New log lines take over the box from these states (and return to them afterwards).
const LOG_PREEMPTS: Array[State] = [State.IDLE, State.ROOT_MENU, State.ATTACK_MENU, State.MOVE, State.TARGET_SELECT, State.CONFIRM]

const Palette = preload("res://ui/theme/gbc_palette.gd")
const SideTint = preload("res://ui/side_tint.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const UnitView = preload("res://ui/hud/unit_view.gd")
const ActionMenuScript = preload("res://ui/hud/action_menu.gd")
const BattleLogScript = preload("res://ui/hud/battle_log.gd")
const HoverPreviewScript = preload("res://ui/hud/hover_preview.gd")
const TargetPanelScript = preload("res://ui/hud/target_panel.gd")
const UnitPanelScript = preload("res://ui/hud/unit_panel_3d.gd")

var state: State = State.IDLE
var confirm_kind: Confirm = Confirm.NONE

@onready var _menu: ActionMenuScript = %ActionMenu
@onready var _log: BattleLogScript = %BattleLog
@onready var _hover: HoverPreviewScript = %HoverPreview
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
var _camera: Camera3D = null
var _anchor_provider := Callable()
var _half_world := 1.0

func _ready() -> void:
	log_line_pushed.connect(_on_log_line_pushed)
	attack_resolved.connect(_on_attack_resolved)
	unit_stats_changed.connect(_on_unit_stats_changed)
	move_finished.connect(_on_move_finished)
	inventory_closed.connect(_on_inventory_closed)
	battle_finished.connect(_on_battle_finished)
	_log.finished.connect(_on_log_finished)
	_menu.command_chosen.connect(_on_command_chosen)
	_menu.action_chosen.connect(_on_action_picked)
	_menu.end_turn_answered.connect(_on_end_turn_answered)
	_target_panel.confirmed.connect(_on_target_confirm_pressed)
	_target_panel.cancelled.connect(_cancel_confirm)
	_apply()

## camera: the stage camera. anchor_provider: Callable(subject) -> Vector3, the world point a panel
## follows; subject is a Unit, or a Vector2i tile for a cast with no unit on it.
## half_width_world: half the sprite width in world units.
func setup(camera: Camera3D, anchor_provider: Callable, half_width_world: float) -> void:
	_camera = camera
	_anchor_provider = anchor_provider
	_half_world = half_width_world
	_active_panel.track(camera, func() -> Vector3: return _anchor_provider.call(_active) if _active != null else Vector3.ZERO, half_width_world)

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

## Mouse hover over a unit (or null). The preview ignores this while it is locked to an attack target.
func set_hover_unit(unit: Unit) -> void:
	var same := unit != null and unit == _hover_unit
	_hover_unit = unit
	if unit == null:
		_hover.clear()
	else:
		_hover.show_view(UnitView.build(unit), same)

## The aim finished backing out (targeting cancelled): back to the attack list.
func aim_cancelled() -> void:
	if state == State.TARGET_SELECT or (state == State.LOG_PLAYING and _resume == State.TARGET_SELECT):
		_enter(State.ATTACK_MENU)

## A target was picked on the map. forecast = UnitView.forecast(...); target = null for an empty tile.
func begin_confirm(target: Unit, cell: Vector2i, forecast: Dictionary) -> void:
	if state != State.TARGET_SELECT:
		return
	_pending_target = target
	_last_forecast = forecast
	var view := UnitView.build(target) if target != null else UnitView.tile(cell, Palette.INK_LIGHT)
	var subject: Variant = target if target != null else cell
	_target_panel.open(view, forecast, _camera, func() -> Vector3: return _anchor_provider.call(subject), _half_world)
	confirm_kind = Confirm.ATTACK
	_enter(State.CONFIRM)

func is_log_busy() -> bool:
	return _log.is_busy()

func is_hover_locked() -> bool:
	return _hover.is_locked()

# --- State machine ---------------------------------------------------------------

## The state the UI rests in between actions.
func _rest_state() -> State:
	return State.ROOT_MENU if _active != null and _active.side == Unit.Side.PLAYER else State.IDLE

## The state whose face is on screen: a playing log hides the menu but not what is behind it.
func _face_state() -> State:
	return _resume if state == State.LOG_PLAYING else state

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
	var menu_states: Array[State] = [State.ROOT_MENU, State.ATTACK_MENU, State.TARGET_SELECT, State.CONFIRM, State.MOVE, State.INVENTORY]
	_menu.visible = not log_face and menu_states.has(face)
	match face:
		State.ROOT_MENU:
			_menu.show_root(_root_flags())
			_menu.set_frozen(false)
		State.ATTACK_MENU:
			_menu.show_attack(_rows(), _menu.layer == ActionMenuScript.Layer.ATTACK)
			_menu.set_frozen(false)
		State.TARGET_SELECT:
			_menu.show_attack(_rows(), true)
			_menu.set_frozen(true)
		State.CONFIRM:
			if confirm_kind == Confirm.END_TURN:
				_menu.show_end_confirm()
				_menu.set_frozen(false)
			else:
				_menu.show_attack(_rows(), true)
				_menu.set_frozen(true)
		State.MOVE:
			_menu.show_root(_root_flags())
			_menu.root_cursor = ActionMenuScript.Command.MOVE
			_menu.set_frozen(true)
		State.INVENTORY:
			_menu.show_root(_root_flags())
			_menu.root_cursor = ActionMenuScript.Command.INVENTORY
			_menu.set_frozen(true)
	if face != State.CONFIRM or confirm_kind != Confirm.ATTACK:
		if _target_panel.is_open() and state != State.LOG_PLAYING and state != State.EXECUTING:
			_target_panel.close()

func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if _active != null:
		rows = UnitView.actions(_active, _can_act)
	return rows

func _root_flags() -> Array[bool]:
	var any_usable := false
	for r in _rows():
		if bool(r["usable"]):
			any_usable = true
	var can_move := _can_act and _active != null and _active.movement > 0
	return [any_usable, true, can_move, _can_end]

# --- Menu choices ------------------------------------------------------------------

func _on_command_chosen(command: int) -> void:
	if state != State.ROOT_MENU:
		return
	match command:
		ActionMenuScript.Command.ATTACK:
			_enter(State.ATTACK_MENU)
		ActionMenuScript.Command.INVENTORY:
			_enter(State.INVENTORY)
			inventory_requested.emit()
		ActionMenuScript.Command.MOVE:
			_enter(State.MOVE)
			move_requested.emit()
		ActionMenuScript.Command.END_TURN:
			confirm_kind = Confirm.END_TURN
			_enter(State.CONFIRM)

func _on_action_picked(action_id: int) -> void:
	if state != State.ATTACK_MENU:
		return
	_enter(State.TARGET_SELECT)
	action_chosen.emit(action_id)

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
	_enter(State.TARGET_SELECT)
	confirm_cancelled.emit()

## Back goes up exactly one layer.
func back() -> bool:
	match _face_state():
		State.ATTACK_MENU:
			_enter(State.ROOT_MENU)
		State.TARGET_SELECT:
			aim_back_requested.emit()
		State.CONFIRM:
			if confirm_kind == Confirm.END_TURN:
				confirm_kind = Confirm.NONE
				_enter(State.ROOT_MENU)
			else:
				_cancel_confirm()
		State.MOVE:
			_enter(State.ROOT_MENU)
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

## Unlock and go back to the menu once BOTH the attack and its log lines are done.
func _finish_attack() -> void:
	_attack_active = false
	_pending_target = null
	_locked = null
	_hover.unlock()
	set_hover_unit(_hover_unit)
	_go(_rest_state())

func _on_unit_stats_changed(unit: Unit) -> void:
	if unit == _active:
		_active_panel.set_view(UnitView.build(unit))
	if _hover.is_locked() and unit == _locked:
		_hover.update_locked(UnitView.build(unit))
	elif unit == _hover_unit and not _hover.is_locked():
		_hover.show_view(UnitView.build(unit), true)
	if unit == _pending_target and _target_panel.is_open():
		_target_panel.refresh(UnitView.build(unit), _last_forecast)
	if [State.ROOT_MENU, State.ATTACK_MENU, State.TARGET_SELECT].has(_face_state()):
		_apply()

func _on_move_finished() -> void:
	if state == State.MOVE:
		_enter(State.ROOT_MENU)

func _on_inventory_closed() -> void:
	if state == State.INVENTORY:
		_enter(State.ROOT_MENU)

func _on_battle_finished() -> void:
	_target_panel.close()
	confirm_kind = Confirm.NONE
	_attack_active = false
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
		State.ROOT_MENU, State.ATTACK_MENU:
			if dir != Vector2i.ZERO:
				return _menu.navigate(dir)
			if event.is_action_pressed("ui_accept"):
				return _menu.accept()
			if cancel:
				return back()
		State.TARGET_SELECT:
			if cancel:
				return back()
		State.CONFIRM:
			if confirm_kind == Confirm.END_TURN:
				if dir != Vector2i.ZERO:
					return _menu.navigate(dir)
				if event.is_action_pressed("ui_accept"):
					return _menu.accept()
			else:
				if dir != Vector2i.ZERO:
					return _target_panel.navigate(dir)
				if event.is_action_pressed("ui_accept"):
					return _target_panel.accept()
			if cancel:
				return back()
			return clicked   # clicks elsewhere must not re-aim while the panel is open
		State.MOVE:
			if cancel:
				return back()
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
```

**`ui/hud/circle_meter.gd`**

```gdscript
extends Control
## Ring meter with a number in the middle (Break / Shred, 0-7).
##
## The ring is painted pixel by pixel into a small Image and shown with nearest-neighbour
## filtering at an integer scale, so the edge is a hard pixel staircase: no anti-aliasing, no
## draw_arc. The fill runs clockwise from 12 o'clock. Image is rebuilt only when a value changes.

const Palette = preload("res://ui/theme/gbc_palette.gd")

## Image size in meter pixels, and the integer scale it is drawn at (one meter pixel = 2 screen px,
## the same as the pixel font's 2x).
const IMG := 20
const SCALE := 2
## Distance bands from the centre, in meter pixels: [0,HOLE) panel, [HOLE,TRACK) border,
## [TRACK,EDGE) fill band (2 px), [EDGE,RADIUS) border.
const HOLE := 6.0
const TRACK := 7.0
const EDGE := 9.0
const RADIUS := 10.0
const FONT := 16

@export var fill_color: Color = Palette.INK:
	set(value):
		fill_color = value
		_rebuild()

var value := 0
var max_value := 7
var _tex: ImageTexture = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(IMG * SCALE, IMG * SCALE)
	_rebuild()

func set_value(new_value: int, new_max: int) -> void:
	if new_value == value and new_max == max_value and _tex != null:
		return
	value = new_value
	max_value = maxi(new_max, 1)
	_rebuild()

## Pixels lit in the fill band for the current value (used by the tests).
func filled_pixels() -> int:
	var img := _image()
	var n := 0
	for y in IMG:
		for x in IMG:
			if img.get_pixel(x, y) == fill_color and _band(x, y) == 2:
				n += 1
	return n

func _band(x: int, y: int) -> int:
	var d := Vector2(x + 0.5 - IMG * 0.5, y + 0.5 - IMG * 0.5).length()
	if d >= RADIUS:
		return 0
	if d >= EDGE:
		return 1
	if d >= TRACK:
		return 2
	if d >= HOLE:
		return 1
	return 3

func _image() -> Image:
	var img := Image.create(IMG, IMG, false, Image.FORMAT_RGBA8)
	var ratio := clampf(float(value) / float(max_value), 0.0, 1.0)
	for y in IMG:
		for x in IMG:
			var c := Color(0, 0, 0, 0)
			match _band(x, y):
				1:
					c = Palette.INK
				2:
					# Clockwise from 12 o'clock.
					var dx := x + 0.5 - IMG * 0.5
					var dy := y + 0.5 - IMG * 0.5
					var turn := fposmod(atan2(dx, -dy), TAU) / TAU
					c = fill_color if turn < ratio else Palette.BG
				3:
					c = Palette.PANEL
			img.set_pixel(x, y, c)
	return img

func _rebuild() -> void:
	_tex = ImageTexture.create_from_image(_image())
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(IMG * SCALE, IMG * SCALE)), false)
	var font := get_theme_default_font()
	var text := str(value)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
	var base := floorf((IMG * SCALE + font.get_ascent(FONT) - font.get_descent(FONT)) * 0.5)
	draw_string(font, Vector2(floorf((IMG * SCALE - w) * 0.5), base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, Palette.INK)
```

**`ui/hud/unit_panel_3d.gd`**

```gdscript
extends Control
## Fire Emblem-style unit panel: diamond portrait, name, team tag (and a forecast block when used
## as the target panel). Faked in 2D, no 3D nodes:
##   1. the flat panel lives in a SubViewport (Viewport/Flat) and is drawn normally by Controls;
##   2. Screen shows that viewport through shaders/pseudo3d_panel.gdshader, which tapers and
##      lifts one edge (pixel for pixel, no filtering);
##   3. every frame the panel is placed beside the tracked unit's sprite on screen, using the
##      stage camera. Left of the sprite by default; it flips to the other side near a screen edge.
## Display only: it ignores the mouse. Data comes in as UnitView dictionaries.

const Palette = preload("res://ui/theme/gbc_palette.gd")
const DiamondPortrait = preload("res://ui/hud/diamond_portrait.gd")

enum PanelSide { LEFT, RIGHT }

const FLAT_W := 320
const H_BASE := 112
const H_FORECAST := 176
## Pixels the far edge rises (also the quad's headroom). Must match the shader's `lift`.
const LIFT := 16
## Gap between the sprite's edge and the panel, and the keep-clear margin at the screen edge.
const GAP := 10
const MARGIN := 8

@export var preferred_side: PanelSide = PanelSide.LEFT
@export_range(0.0, 0.5) var taper := 0.16
## Pixels kept clear under the panel (the target panel's buttons live there).
@export var extra_below := 0

@onready var _screen: TextureRect = %Screen
@onready var _viewport: SubViewport = %Viewport
@onready var _portrait: DiamondPortrait = %Portrait
@onready var _name: Label = %NameLabel
@onready var _team: Label = %TeamTag
@onready var _stats: Label = %Stats
@onready var _forecast: VBoxContainer = %Forecast
@onready var _fc_hit: Label = %FcHit
@onready var _fc_dmg: Label = %FcDmg
@onready var _fc_hp: Label = %FcHp
@onready var _fc_foot: Label = %FcFoot

var _camera: Camera3D = null
var _anchor := Callable()
var _half_world := 1.0
var _active := false
var _height := H_BASE
var _side: PanelSide = PanelSide.LEFT
var _material: ShaderMaterial = null
var _side_applied := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = (_screen.material as ShaderMaterial).duplicate() as ShaderMaterial
	_screen.material = _material
	_screen.texture = _viewport.get_texture()
	_apply_height(H_BASE)
	visible = false

## Follow a point in the world (the unit's chest). `half_width_world` is half the sprite's width in
## world units; the panel keeps that far (plus GAP pixels) from the sprite.
func track(camera: Camera3D, anchor: Callable, half_width_world: float) -> void:
	_camera = camera
	_anchor = anchor
	_half_world = half_width_world

func show_panel() -> void:
	_active = true
	_place()

func hide_panel() -> void:
	_active = false
	visible = false

func is_active() -> bool:
	return _active

func current_side() -> PanelSide:
	return _side

func set_view(view: Dictionary) -> void:
	_portrait.set_view(view)
	_name.text = view["name"]
	_team.text = view["team"]
	_team.add_theme_color_override("font_color", view["accent"])
	if float(view["max_ap"]) > 0.0:
		_stats.text = "AP %s/%s  MV %d/%d" % [_num(view["ap"]), _num(view["max_ap"]), view["move"], view["max_move"]]
	else:
		_stats.text = ""

## fc = UnitView.forecast(); an empty dictionary removes the forecast block.
func set_forecast(fc: Dictionary) -> void:
	if fc.is_empty():
		_forecast.visible = false
		_apply_height(H_BASE)
		return
	_forecast.visible = true
	var tier := " T%d" % int(fc["tier"]) if int(fc["tier"]) > 1 else ""
	_stats.text = "%s%s" % [String(fc["ability"]).to_upper(), tier]
	_fc_hit.text = "%s %s  CRIT %s" % [fc["chance_label"], _pct(int(fc["hit"])), _pct(int(fc["crit"]))]
	_fc_dmg.text = "DMG %d" % int(fc["dmg_min"]) if int(fc["dmg_min"]) == int(fc["dmg_max"]) else "DMG %d-%d" % [int(fc["dmg_min"]), int(fc["dmg_max"])]
	var drop := int(fc["hp_now"]) - int(fc["hp_after"])
	_fc_hp.text = "HP %d > %d (-%d)" % [int(fc["hp_now"]), int(fc["hp_after"]), drop] if int(fc["hp_now"]) > 0 else "HP --"
	var foot: Array[String] = []
	if String(fc["foot"]) != "":
		foot.append(String(fc["foot"]))
	if int(fc["extra_targets"]) > 0:
		foot.append("+%d MORE" % int(fc["extra_targets"]))
	_fc_foot.text = " ".join(foot)
	_apply_height(H_FORECAST)

## Screen rectangle of the panel quad (panel plus the headroom above it).
func screen_rect() -> Rect2:
	return Rect2(position, size)

func _process(_delta: float) -> void:
	if _active:
		_place()

func _apply_height(h: int) -> void:
	_height = h
	_viewport.size = Vector2i(FLAT_W, h)
	size = Vector2(FLAT_W, h + LIFT)
	_screen.size = size
	_material.set_shader_parameter("panel_size", Vector2(FLAT_W, h))
	_material.set_shader_parameter("lift", float(LIFT))
	_material.set_shader_parameter("taper", taper)

func _place() -> void:
	if _camera == null or not _anchor.is_valid():
		return
	var world: Vector3 = _anchor.call()
	if _camera.is_position_behind(world):
		visible = false
		return
	visible = true
	var p := _camera.unproject_position(world)
	var half := absf((_camera.unproject_position(world + _camera.global_transform.basis.x * _half_world) - p).x)
	var vp := get_viewport_rect().size
	var left_x := p.x - half - GAP - FLAT_W
	var right_x := p.x + half + GAP
	var side := preferred_side
	if side == PanelSide.LEFT and left_x < MARGIN:
		side = PanelSide.RIGHT
	elif side == PanelSide.RIGHT and right_x + FLAT_W > vp.x - MARGIN:
		side = PanelSide.LEFT
	var x := left_x if side == PanelSide.LEFT else right_x
	var y := p.y - (LIFT + _height * 0.5)
	x = clampf(x, MARGIN, maxf(vp.x - FLAT_W - MARGIN, MARGIN))
	y = clampf(y, MARGIN, maxf(vp.y - size.y - extra_below - MARGIN, MARGIN))
	position = Vector2(roundf(x), roundf(y))
	if side != _side or not _side_applied:
		_side = side
		_side_applied = true
		# The edge next to the sprite is the one that recedes.
		_material.set_shader_parameter("far_is_right", side == PanelSide.LEFT)

static func _pct(v: int) -> String:
	return "--" if v < 0 else "%d%%" % v

static func _num(v: Variant) -> String:
	return String.num(float(v), 1).trim_suffix(".0")
```

**`ui/hud/stat_bar.gd`**

```gdscript
extends Control
## One flat HUD bar: caption | bar | "n/max". Hard pixel track, flat fill, no gradient, no outline.
## Solid when `segments` is 0, otherwise that many equal blocks. A same-unit change slides to the
## new value over `anim_seconds`; set_values(..., snap = true) jumps (used when the unit changes).

const Palette = preload("res://ui/theme/gbc_palette.gd")

const FONT := 16
const BAR_H := 16.0
## Fixed-width pixel font: 12 px per glyph at size 16.
const CAPTION_W := 5.0 * 12.0 + 8.0
const NUMS_W := 7.0 * 12.0 + 4.0
const SEG_GAP := 2.0

@export var caption := "HP"
@export var fill_color: Color = Palette.INK
@export var segments := 0
@export var anim_seconds := 0.25

var _target := 0
var _max := 0
var _shown := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, BAR_H + 4.0)
	set_process(false)

func set_values(value: int, max_value: int, snap: bool) -> void:
	_target = value
	_max = max_value
	if snap or anim_seconds <= 0.0:
		_shown = float(value)
		set_process(false)
	else:
		set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_shown = move_toward(_shown, float(_target), maxf(float(_max) * delta / maxf(anim_seconds, 0.01), 0.001))
	if is_equal_approx(_shown, float(_target)):
		set_process(false)
	queue_redraw()

func shown_value() -> float:
	return _shown

func _draw() -> void:
	var font := get_theme_default_font()
	var live := _max > 0
	var ink := Palette.INK if live else Palette.INK_LIGHT
	var y := floorf((size.y - BAR_H) * 0.5)
	var baseline := y + floorf((BAR_H + font.get_ascent(FONT) - font.get_descent(FONT)) * 0.5)
	draw_string(font, Vector2(0.0, baseline), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	draw_string(font, Vector2(size.x - NUMS_W, baseline), "%d/%d" % [_target, _max], HORIZONTAL_ALIGNMENT_RIGHT, NUMS_W - 4.0, FONT, ink)
	var rect := Rect2(CAPTION_W, y, maxf(size.x - CAPTION_W - NUMS_W, 8.0), BAR_H)
	draw_rect(rect, ink)
	var inner := rect.grow(-2.0)
	draw_rect(inner, Palette.BG)
	if not live:
		return
	var ratio := clampf(_shown / float(_max), 0.0, 1.0)
	if segments <= 0:
		if ratio > 0.0:
			var w := maxf(2.0, floorf(inner.size.x * ratio / 2.0) * 2.0)
			draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), fill_color)
		return
	var seg_w := floorf((inner.size.x - SEG_GAP * float(segments - 1)) / float(segments))
	var total := seg_w * float(segments) + SEG_GAP * float(segments - 1)
	var x0 := inner.position.x + floorf((inner.size.x - total) * 0.5)
	var lit := ceili(ratio * float(segments) - 0.001)
	for i in lit:
		draw_rect(Rect2(x0 + float(i) * (seg_w + SEG_GAP), inner.position.y, seg_w, inner.size.y), fill_color)
```

**`ui/hud/diamond_portrait.gd`**

```gdscript
extends Control
## Diamond-framed portrait. Every shape is built from 1 px rows (no polygons, no arcs), so the
## edges are hard pixel staircases. The unit's front sprite frame is drawn at an integer 2x scale,
## clipped row by row to the inner diamond. Units without a sprite show their first letter.

const Palette = preload("res://ui/theme/gbc_palette.gd")

const SIZE := 72
const SPRITE_SCALE := 2
const FRAME_PX := 32
const LETTER_FONT := 32
## Diamond insets (px from the outer tip): INK outline, accent band, INK line, then the fill.
const INSET_ACCENT := 3
const INSET_LINE := 6
const INSET_FILL := 7

var _view: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(SIZE, SIZE)

func set_view(view: Dictionary) -> void:
	_view = view
	queue_redraw()

## Half width (px) of a diamond inset by `inset`, at the row whose centre is `dy` px from the middle.
static func half_width(inset: int, dy: float) -> float:
	return floorf(float(SIZE) * 0.5 - float(inset) - absf(dy))

func _diamond(inset: int, color: Color) -> void:
	for y in SIZE:
		var hw := half_width(inset, y + 0.5 - SIZE * 0.5)
		if hw > 0.0:
			draw_rect(Rect2(SIZE * 0.5 - hw, y, hw * 2.0, 1.0), color)

func _draw() -> void:
	if _view.is_empty():
		return
	var accent: Color = _view["accent"]
	_diamond(0, Palette.INK)
	_diamond(INSET_ACCENT, accent)
	_diamond(INSET_LINE, Palette.INK)
	_diamond(INSET_FILL, Palette.BG)
	var tex: Texture2D = _view["sprite_tex"]
	if tex == null:
		var font := get_theme_default_font()
		var text: String = _view["letter"]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_FONT).x
		var base := floorf((SIZE + font.get_ascent(LETTER_FONT) - font.get_descent(LETTER_FONT)) * 0.5)
		draw_string(font, Vector2(floorf((SIZE - w) * 0.5), base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_FONT, Palette.INK)
		return
	var src: Rect2 = _view["sprite_rect"]
	var origin := (SIZE - FRAME_PX * SPRITE_SCALE) / 2
	for row in FRAME_PX:
		var dest_y := origin + row * SPRITE_SCALE
		# Clip each source row to the inner diamond, symmetric around the sprite centre.
		var hw := half_width(INSET_FILL, dest_y + SPRITE_SCALE * 0.5 - SIZE * 0.5)
		var src_half := int(floorf(hw / SPRITE_SCALE))
		if src_half <= 0:
			continue
		var half_frame := FRAME_PX / 2
		draw_texture_rect_region(tex,
			Rect2(origin + (half_frame - src_half) * SPRITE_SCALE, dest_y, src_half * 2 * SPRITE_SCALE, SPRITE_SCALE),
			Rect2(src.position.x + half_frame - src_half, src.position.y + row, src_half * 2, 1))
```

**`ui/hud/hover_preview.gd`**

```gdscript
extends PanelContainer
## Bottom-right hover preview: exactly three bars (HP, Magic Shield, Armor), with a ring meter for
## BREAK left of the Magic Shield bar and one for SHRED left of the Armor bar. No other text.
## It can be LOCKED to one unit (during an attack); while locked, hover cannot change it.
## Palette: ink / ink-light / bg / panel plus the side accent (HP stays ink so the accent is
## free for the shield bar and its Break ring).

const Palette = preload("res://ui/theme/gbc_palette.gd")
const CircleMeter = preload("res://ui/hud/circle_meter.gd")
const StatBar = preload("res://ui/hud/stat_bar.gd")

@onready var _hp: StatBar = %HpBar
@onready var _shield: StatBar = %ShieldBar
@onready var _armor: StatBar = %ArmorBar
@onready var _break: CircleMeter = %BreakMeter
@onready var _shred: CircleMeter = %ShredMeter

var _locked := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_armor.fill_color = Palette.INK_LIGHT
	_shred.fill_color = Palette.INK_LIGHT
	visible = false

## Hover shows `view`. Ignored while locked. `same_unit` = the same unit as before (bars slide
## instead of snapping).
func show_view(view: Dictionary, same_unit: bool = false) -> void:
	if _locked:
		return
	_apply(view, same_unit)

## The mouse left every unit. Ignored while locked.
func clear() -> void:
	if _locked:
		return
	visible = false

func lock(view: Dictionary) -> void:
	_locked = true
	_apply(view, false)

## Fresh numbers for the locked unit (bars slide to them).
func update_locked(view: Dictionary) -> void:
	if _locked:
		_apply(view, true)

func unlock() -> void:
	_locked = false
	visible = false

func is_locked() -> bool:
	return _locked

func _apply(view: Dictionary, same_unit: bool) -> void:
	visible = true
	var accent: Color = view["accent"]
	_shield.fill_color = accent
	_break.fill_color = accent
	var snap := not same_unit
	_hp.set_values(view["hp"], view["max_hp"], snap)
	_shield.set_values(view["shield"], view["max_shield"], snap)
	_armor.set_values(view["armor"], view["max_armor"], snap)
	_break.set_value(view["break"], view["max_stacks"])
	_shred.set_value(view["shred"], view["max_stacks"])
```

**`ui/hud/battle_log.gd`**

```gdscript
extends PanelContainer
## Pokemon-style dialog box for the bottom-center slot: 2-3 visible lines, typewriter text, and a
## blinking ▼ while a finished line waits to be advanced.
##
## Lines are queued with push_line(). Each line types out, waits (a press advances at once; with
## wait_for_input off it also advances by itself after auto_advance_seconds), then the next line
## starts. The newest lines stay on the page; the page clears when the queue runs dry and
## `finished` fires exactly once per burst of lines. is_busy() is true from the first push until then.

signal finished

const ARROW := "\u25bc"
## Visible lines are set by the box height in the scene (3 lines of the 16 px font plus the frame).
@export var chars_per_second := 60.0
## true = every line waits for a press (strict Pokemon). false = lines advance on their own.
@export var wait_for_input := false
@export var auto_advance_seconds := 0.7
@export var arrow_blink_seconds := 0.35

@onready var _text: RichTextLabel = %Text
@onready var _arrow: Label = %Arrow

var _queue: Array[String] = []
var _page: Array[String] = []
var _type_from := 0
var _progress := 0.0
var _typing := false
var _waiting := false
var _wait_left := 0.0
var _blink := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.text = ARROW
	_arrow.visible = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.scroll_following = true
	_text.get_v_scroll_bar().modulate.a = 0.0
	_text.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func push_line(text: String) -> void:
	_queue.append(text)
	if not _typing and not _waiting:
		_start_next()

func is_busy() -> bool:
	return _typing or _waiting or not _queue.is_empty()

## A press while the box is showing text. Finishes typing, or advances a waiting line.
## Returns true when the press was used.
func advance_input() -> bool:
	if _typing:
		_finish_typing()
		return true
	if _waiting:
		_advance()
		return true
	return false

func arrow_visible() -> bool:
	return _arrow.visible

func visible_text() -> String:
	return _text.get_parsed_text()

func _start_next() -> void:
	_page.append(_queue.pop_front())
	while _page.size() > 3:
		_page.pop_front()
	_text.clear()
	for i in _page.size():
		if i > 0:
			_text.newline()
		if i == _page.size() - 1:
			_type_from = _text.get_total_character_count()
		_text.add_text(_page[i])
	_arrow.visible = false
	_progress = 0.0
	if chars_per_second <= 0.0:
		_finish_typing()
		return
	_typing = true
	_text.visible_characters = _type_from
	set_process(true)

func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	_waiting = true
	_wait_left = auto_advance_seconds
	_blink = 0.0
	_arrow.visible = true
	set_process(true)
	if not wait_for_input and auto_advance_seconds <= 0.0:
		_advance()

func _advance() -> void:
	_waiting = false
	_arrow.visible = false
	if not _queue.is_empty():
		_start_next()
		return
	_page.clear()
	_text.clear()
	set_process(false)
	finished.emit()

func _process(delta: float) -> void:
	if _typing:
		_progress += delta * chars_per_second
		var shown := _type_from + int(_progress)
		if shown >= _text.get_total_character_count():
			_finish_typing()
		else:
			_text.visible_characters = shown
	elif _waiting:
		_blink += delta
		if _blink >= arrow_blink_seconds:
			_blink = 0.0
			_arrow.visible = not _arrow.visible
		if not wait_for_input:
			_wait_left -= delta
			if _wait_left <= 0.0:
				_advance()
```

**`ui/hud/action_menu.gd`**

```gdscript
extends HBoxContainer
## Pokemon-style layered action menu for the bottom-center box. Three layers, one visible at a time:
##   ROOT         ATTACK / INVENTORY / MOVE / END TURN in a 2x2 grid with a ▶ cursor
##   ATTACK       WEAPON | SPELL tabs and the actions under the active tab (name + AP cost)
##   END_CONFIRM  "END TURN?" YES / NO
## The description box on the right shows the highlighted action's details (range, dice, type).
## Keyboard / controller: navigate() + accept(). Mouse: hover moves the cursor, click accepts.
## It only reports intent through signals; BattleUI decides what a choice means. Rows are plain
## Dictionaries from UnitView.actions(), so the menu never touches a Unit.

signal command_chosen(command: int)
signal action_chosen(action_id: int)
signal end_turn_answered(yes: bool)

enum Layer { ROOT, ATTACK, END_CONFIRM }
enum Command { ATTACK, INVENTORY, MOVE, END_TURN }
enum Tab { WEAPON, SPELL }

const Palette = preload("res://ui/theme/gbc_palette.gd")

const ROOT_LABELS: Array[String] = ["ATTACK", "INVENTORY", "MOVE", "END TURN"]
const ROOT_HINTS: Array[String] = ["Use a weapon or a spell.", "Open the equipment window.", "Walk to a tile.", "Finish this unit's turn."]
const VISIBLE_ROWS := 3
## Fixed-width font: 12 px per glyph at size 16. Row text = cursor(2) + name(14) + cost(9).
const NAME_CHARS := 14
const COST_CHARS := 9

@onready var _root_grid: GridContainer = %RootGrid
@onready var _attack_layer: VBoxContainer = %AttackLayer
@onready var _end_layer: VBoxContainer = %EndLayer
@onready var _tab_buttons: HBoxContainer = %Tabs
@onready var _list: VBoxContainer = %List
@onready var _more: Label = %More
@onready var _description: Label = %Description

var layer: Layer = Layer.ROOT
var frozen := false
var root_cursor := 0
var tab: Tab = Tab.WEAPON
var list_cursor := 0
var end_cursor := 1   # NO is the safe default

var _root_enabled: Array[bool] = [true, true, true, true]
var _entries: Array[Dictionary] = []
var _shown: Array[Dictionary] = []
var _top := 0
var _root_buttons: Array[Button] = []
var _row_buttons: Array[Button] = []
var _tab_btns: Array[Button] = []
var _end_btns: Array[Button] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in ROOT_LABELS.size():
		var b := _flat_button()
		_root_grid.add_child(b)
		_root_buttons.append(b)
		b.mouse_entered.connect(_on_root_hover.bind(i))
		b.pressed.connect(_on_root_pressed.bind(i))
	for i in 2:
		var t := _flat_button()
		t.text = ["WEAPON", "SPELL"][i]
		_tab_buttons.add_child(t)
		_tab_btns.append(t)
		t.mouse_entered.connect(_on_tab_hover.bind(i))
		t.pressed.connect(_on_tab_pressed.bind(i))
	for i in VISIBLE_ROWS:
		var r := _flat_button()
		_list.add_child(r)
		_row_buttons.append(r)
		r.mouse_entered.connect(_on_row_hover.bind(i))
		r.pressed.connect(_on_row_pressed.bind(i))
	for i in 2:
		var e := _flat_button()
		e.text = ["YES", "NO"][i]
		%EndButtons.add_child(e)
		_end_btns.append(e)
		e.mouse_entered.connect(_on_end_hover.bind(i))
		e.pressed.connect(_on_end_pressed.bind(i))
	_redraw()

# --- Called by BattleUI -------------------------------------------------------

func show_root(enabled: Array[bool]) -> void:
	layer = Layer.ROOT
	_root_enabled = enabled
	_redraw()

## rows = UnitView.actions(unit, can_act). Keeps the tab and cursor when the same layer is refreshed.
func show_attack(rows: Array[Dictionary], keep_cursor: bool = false) -> void:
	layer = Layer.ATTACK
	_entries = rows
	if not keep_cursor:
		tab = Tab.WEAPON
		list_cursor = 0
		_top = 0
		# Open on the tab that has something in it.
		if _rows_for(Tab.WEAPON).is_empty() and not _rows_for(Tab.SPELL).is_empty():
			tab = Tab.SPELL
	_redraw()

func show_end_confirm() -> void:
	layer = Layer.END_CONFIRM
	end_cursor = 1
	_redraw()

## A frozen menu stays drawn (cursor included) but ignores input; used while aiming and confirming.
func set_frozen(value: bool) -> void:
	frozen = value
	_redraw()

## Which ability the cursor is on (-1 when none). Used by BattleUI for the description.
func highlighted_action() -> int:
	if layer != Layer.ATTACK or _shown.is_empty():
		return -1
	return int(_shown[clampi(list_cursor, 0, _shown.size() - 1)]["id"])

## Moves the cursor. dir: (-1,0) left, (1,0) right, (0,-1) up, (0,1) down. Returns true when handled.
func navigate(dir: Vector2i) -> bool:
	if frozen:
		return false
	match layer:
		Layer.ROOT:
			var col := root_cursor % 2
			var row := root_cursor >> 1
			col = clampi(col + dir.x, 0, 1)
			row = clampi(row + dir.y, 0, 1)
			root_cursor = row * 2 + col
		Layer.ATTACK:
			if dir.x != 0:
				tab = Tab.SPELL if dir.x > 0 else Tab.WEAPON
				list_cursor = 0
				_top = 0
			else:
				list_cursor = clampi(list_cursor + dir.y, 0, maxi(_rows_for(tab).size() - 1, 0))
		Layer.END_CONFIRM:
			end_cursor = clampi(end_cursor + dir.x, 0, 1)
	_redraw()
	return true

## Accept on the highlighted entry. Returns true when it did something.
func accept() -> bool:
	if frozen:
		return false
	match layer:
		Layer.ROOT:
			if _root_enabled[root_cursor]:
				command_chosen.emit(root_cursor)
				return true
		Layer.ATTACK:
			var rows := _rows_for(tab)
			if not rows.is_empty() and bool(rows[list_cursor]["usable"]):
				action_chosen.emit(int(rows[list_cursor]["id"]))
				return true
		Layer.END_CONFIRM:
			end_turn_answered.emit(end_cursor == 0)
			return true
	return false

# --- Drawing ------------------------------------------------------------------

func _rows_for(t: Tab) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _entries:
		if bool(r["spell"]) == (t == Tab.SPELL):
			out.append(r)
	return out

func _redraw() -> void:
	if not is_node_ready():
		return
	_root_grid.visible = layer == Layer.ROOT
	_attack_layer.visible = layer == Layer.ATTACK
	_end_layer.visible = layer == Layer.END_CONFIRM
	match layer:
		Layer.ROOT:
			for i in ROOT_LABELS.size():
				_style(_root_buttons[i], ROOT_LABELS[i], i == root_cursor, _root_enabled[i])
			_description.text = ROOT_HINTS[root_cursor]
		Layer.ATTACK:
			for i in _tab_btns.size():
				_tab_btns[i].text = "%s%s" % ["\u25b6" if i == tab else " ", ["WEAPON", "SPELL"][i]]
				_style_raw(_tab_btns[i], i == tab, true)
			_shown = _rows_for(tab)
			list_cursor = clampi(list_cursor, 0, maxi(_shown.size() - 1, 0))
			if list_cursor < _top:
				_top = list_cursor
			elif list_cursor >= _top + VISIBLE_ROWS:
				_top = list_cursor - VISIBLE_ROWS + 1
			for i in VISIBLE_ROWS:
				var idx := _top + i
				var b := _row_buttons[i]
				b.visible = idx < _shown.size() or (i == 0 and _shown.is_empty())
				if idx < _shown.size():
					var r := _shown[idx]
					var line := "%s%s" % [String(r["name"]).substr(0, NAME_CHARS).rpad(NAME_CHARS), String(r["cost"]).lpad(COST_CHARS)]
					_style(b, line, idx == list_cursor, bool(r["usable"]))
				elif i == 0:
					_style(b, "(none)", false, false)
			_more.text = "\u25bc" if _top + VISIBLE_ROWS < _shown.size() else " "
			_description.text = String(_shown[list_cursor]["detail"]) if not _shown.is_empty() else "No actions here."
		Layer.END_CONFIRM:
			for i in _end_btns.size():
				_style(_end_btns[i], ["YES", "NO"][i], i == end_cursor, true)
			_description.text = "End this unit's turn?"

func _style(b: Button, text: String, selected: bool, enabled: bool) -> void:
	b.text = "%s%s" % ["\u25b6 " if selected else "  ", text]
	_style_raw(b, false, enabled)

func _style_raw(b: Button, inverse: bool, enabled: bool) -> void:
	b.add_theme_color_override("font_color", Palette.PANEL if inverse else (Palette.INK if enabled else Palette.INK_LIGHT))
	b.add_theme_color_override("font_hover_color", Palette.PANEL if inverse else (Palette.INK if enabled else Palette.INK_LIGHT))
	b.add_theme_color_override("font_pressed_color", Palette.PANEL if inverse else (Palette.INK if enabled else Palette.INK_LIGHT))
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.INK if inverse else Color(0, 0, 0, 0)
	box.set_content_margin_all(2)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, box)

func _flat_button() -> Button:
	var b := Button.new()
	b.flat = false
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

# --- Mouse --------------------------------------------------------------------

func _on_root_hover(i: int) -> void:
	if not frozen and layer == Layer.ROOT:
		root_cursor = i
		_redraw()

func _on_root_pressed(i: int) -> void:
	if not frozen and layer == Layer.ROOT:
		root_cursor = i
		accept()

func _on_tab_hover(_i: int) -> void:
	pass

func _on_tab_pressed(i: int) -> void:
	if not frozen and layer == Layer.ATTACK:
		tab = i as Tab
		list_cursor = 0
		_top = 0
		_redraw()

func _on_row_hover(i: int) -> void:
	if not frozen and layer == Layer.ATTACK and _top + i < _shown.size():
		list_cursor = _top + i
		_redraw()

func _on_row_pressed(i: int) -> void:
	if not frozen and layer == Layer.ATTACK and _top + i < _shown.size():
		list_cursor = _top + i
		accept()

func _on_end_hover(i: int) -> void:
	if not frozen and layer == Layer.END_CONFIRM:
		end_cursor = i
		_redraw()

func _on_end_pressed(i: int) -> void:
	if not frozen and layer == Layer.END_CONFIRM:
		end_cursor = i
		accept()
```

**`ui/hud/target_panel.gd`**

```gdscript
extends Control
## Target panel: the unit panel again, from the ENEMY's side. It is the same pseudo-3D panel
## (ui/hud/unit_panel_3d.tscn), anchored to the target's sprite on the opposite side from the
## current unit's panel, and carries the attack preview (hit %, crit %, damage range, projected
## HP) plus CONFIRM and CANCEL.
## The buttons are ordinary, unskewed Controls placed under the panel, so what the mouse can
## click is exactly what is drawn. Keyboard / controller: navigate() + accept().

signal confirmed
signal cancelled

const UnitPanel3D = preload("res://ui/hud/unit_panel_3d.gd")

const BUTTON_ROW_H := 48
const BUTTON_GAP := 4

@onready var _panel: UnitPanel3D = %Panel
@onready var _buttons: HBoxContainer = %Buttons
@onready var _confirm: Button = %Confirm
@onready var _cancel: Button = %Cancel

var selected := 0   # 0 = CONFIRM, 1 = CANCEL
var _open := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.preferred_side = UnitPanel3D.PanelSide.RIGHT
	_panel.extra_below = BUTTON_ROW_H
	_confirm.pressed.connect(func() -> void: _choose(0))
	_cancel.pressed.connect(func() -> void: _choose(1))
	_confirm.mouse_entered.connect(func() -> void: _select(0))
	_cancel.mouse_entered.connect(func() -> void: _select(1))
	_buttons.visible = false
	set_process(false)

## view = UnitView.build(target) (or UnitView.tile), forecast = UnitView.forecast().
func open(view: Dictionary, forecast: Dictionary, camera: Camera3D, anchor: Callable, half_width_world: float) -> void:
	_panel.set_view(view)
	_panel.set_forecast(forecast)
	_panel.track(camera, anchor, half_width_world)
	_panel.show_panel()
	_open = true
	_buttons.visible = true
	_select(0)
	set_process(true)

## Keeps the panel where it is and refreshes the numbers (the target's stats changed).
func refresh(view: Dictionary, forecast: Dictionary) -> void:
	if _open:
		_panel.set_view(view)
		_panel.set_forecast(forecast)

func close() -> void:
	_open = false
	_panel.hide_panel()
	_buttons.visible = false
	set_process(false)

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
	_mark(_confirm, i == 0)
	_mark(_cancel, i == 1)

## The selected button wears the theme's thick "hover" frame.
func _mark(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", b.get_theme_stylebox("hover"))
	else:
		b.remove_theme_stylebox_override("normal")

func _choose(i: int) -> void:
	if not _open:
		return
	if i == 0:
		confirmed.emit()
	else:
		cancelled.emit()

func _process(_delta: float) -> void:
	_buttons.visible = _panel.visible and _open
	var r := _panel.screen_rect()
	_buttons.position = Vector2(roundf(r.position.x + (r.size.x - _buttons.size.x) * 0.5), roundf(r.end.y + BUTTON_GAP))
```

**`shaders/pseudo3d_panel.gdshader`**

```glsl
shader_type canvas_item;
// Fakes a flat panel turned away from the camera, in 2D, with no filtering.
//
// The panel is first drawn flat into a SubViewport. This shader draws that texture onto a quad
// that is panel_size wide and (panel_size.y + lift) tall. Moving along x, the panel loses `taper`
// of its height and rises by `lift` pixels at the far edge, so it reads as a card in perspective.
// Every output pixel is mapped back to ONE source pixel (floor, no blending) and pixels outside the
// panel are discarded, so edges are hard staircases: no anti-aliasing, no smoothing.
// Set the node's texture_filter to Nearest as well.
//
// Forward map for a source pixel (sx, sy), with t = x / W (mirrored when the far edge is the left):
//   k  = 1 - taper * t                      height scale at this column
//   oy = (lift + H/2 - lift * t) + (sy - H/2) * k
// Inverted below so each OUTPUT pixel picks its source pixel.

uniform vec2 panel_size = vec2(320.0, 112.0);
uniform float lift = 16.0;
uniform float taper : hint_range(0.0, 0.5) = 0.16;
uniform bool far_is_right = true;

void fragment() {
	vec2 quad = vec2(panel_size.x, panel_size.y + lift);
	vec2 o = floor(UV * quad) + 0.5;
	float t = o.x / panel_size.x;
	if (!far_is_right) {
		t = 1.0 - t;
	}
	float k = 1.0 - taper * t;
	float center_y = lift + panel_size.y * 0.5 - lift * t;
	float sy = panel_size.y * 0.5 + (o.y - center_y) / k;
	if (sy < 0.0 || sy >= panel_size.y) {
		discard;
	}
	vec2 src = vec2(floor(o.x), floor(sy)) + 0.5;
	COLOR = texture(TEXTURE, src / panel_size);
}
```

## 6. Wiring

Only `scripts/battle/battle_view.gd` and `scenes/battle.tscn` changed. `battle.gd`, `rules.gd`, `unit.gd` and every combat file are untouched. The old `ActionBar`, `CombatLog`, `ActiveUnitPanel`, `InspectPanel` and `TargetPreviewPanel` files are still in the project, now unused.

**Facts in (Battle -> UI)**, in `BattleView._ready()`:

```gdscript
hud.setup(stage.camera, _hud_anchor, Stage3D.PIXEL_SIZE * float(UnitSprites.FRAME) * 0.5)
battle.log_message.connect(hud.log_line_pushed.emit)              # log_line_pushed(text)
battle.battle_ended.connect(func(_won): hud.battle_finished.emit())
battle.state_changed.connect(_on_battle_state_changed)            # MOVING -> WAIT_INPUT emits hud.move_finished
equipment_window.closed.connect(hud.inventory_closed.emit)
# _refresh_hud() (deferred, skipped while the director is animating) calls:
hud.set_context(cur, can_act, can_end_turn)                       # current unit + who may act
for u in battle.units: hud.unit_stats_changed.emit(u)             # unit_stats_changed(unit)
# _run_confirmed_attack(): after use_ability and `await battle.presentation_finished`:
hud.attack_resolved.emit()                                        # attack_resolved()
# mouse hover:
hud.set_hover_unit(_unit_at(cell))
```

**Intent out (UI -> Battle)**:

```gdscript
hud.action_chosen.connect(_on_action_chosen)       # id = index into unit.abilities -> battle.enter_targeting(...)
hud.target_confirmed.connect(_on_target_confirmed) # -> battle.use_ability(...) (or the spell session commit)
hud.move_requested.connect(_on_move_requested)     # battle stays in WAIT_INPUT; map clicks move only while hud.state == MOVE
hud.end_turn_requested.connect(_on_end_pressed)    # -> battle.end_turn()
hud.inventory_requested.connect(func(): _open_equipment(battle.current))
hud.aim_back_requested.connect(_aim_back)          # undo a spell aim step, else battle.cancel_targeting() + hud.aim_cancelled()
hud.confirm_cancelled.connect(_on_confirm_cancelled)
```

In `_unhandled_input`, `hud.handle_input(event)` runs first; if it returns true the event is consumed. Nothing reaches `Battle.use_ability` until CONFIRM.

**Connecting your unit data**: edit `ui/hud/unit_view.gd` only. `build(unit)` maps `hp / max_hp`, `magic_shield / max_magic_shield`, `physical_armor / max_physical_armor`, `shield_break_stacks`, `armor_shred_stacks`, `ap`, `movement`. `actions(unit, can_act)` builds the menu rows from `unit.abilities` (there is no ability id in your `Ability` resource, so `action_id` is the index; swap it if you add one). `forecast(...)` reads `AttackForecast.build()` rows; its projected-HP math copies the soak order from `Unit.take_damage` for the average roll.

**Placeholders and project-specific choices**
- `action_id` = index into `unit.abilities` (see above).
- `_hud_anchor()` in battle_view follows `stage.holder_of(u)` plus the chest offset; the half sprite width comes from `UnitSprites.FRAME * Stage3D.PIXEL_SIZE`.
- `project.godot` is not changed. See "Not verified" for integer scaling.

## 7. Test checklist (pass / fail)

Automated in `tests/test_battle_ui.gd` (run: `godot --headless -s tests/test_battle_ui.gd`, 48 checks, 0 failed). Items marked **manual** were checked on screenshots but not asserted in code.

| # | Check | Result |
|---|---|---|
| 1.1 | Log text appears in the bottom-center box, not at left | pass (screenshot) |
| 1.2 | Text types out one character at a time and a ▼ shows while a line waits | **manual only**: the typing path runs in the attack test and a typing-in-progress frame is in the screenshots, but the test does not assert the ▼ or the character count |
| 1.3 | At most 3 lines visible (box height = 3 lines) | **manual only**: set by the box height, not asserted; I only saw one or two lines on screen |
| 1.4 | While lines play, the log is visible and the menu hidden | pass |
| 1.5 | When the log finishes, the menu returns | pass |
| 2.1 | Root menu is a 2x2 grid: ATTACK, INVENTORY / MOVE, END TURN with a ▶ cursor | pass |
| 2.2 | Arrow keys (ui_*) move the cursor; accept chooses | pass |
| 2.3 | ATTACK opens WEAPON / SPELL tabs; left/right switches | pass |
| 2.4 | Every entry shows its AP cost | pass |
| 2.5 | The highlighted entry's range, dice and type show in the description box | pass |
| 2.6 | INVENTORY opens the equipment window; closing it returns to the root | pass |
| 2.7 | MOVE enters move mode and emits `move_requested` | pass |
| 2.8 | END TURN asks YES / NO; NO ends nothing; YES emits `end_turn_requested` | pass |
| 2.9 | Back goes up exactly one layer (attack -> root, move -> root, end-turn confirm -> root) | pass |
| 2.10 | Mouse hover and click on menu rows | **not verified** with a real mouse (signal paths only) |
| 2.11 | Gamepad | **not verified** with hardware; `ui_*` actions were driven with `InputEventAction` |
| 3.1 | Unit panel sits left of the selected unit's sprite | pass |
| 3.2 | It follows the sprite when the camera turns | pass |
| 3.3 | Diamond portrait, name, team tag present | pass (screenshot) |
| 3.4 | Skew uses whole-pixel mapping and nearest filtering | pass |
| 4.1 | Hover shows exactly 3 bars and 2 rings | pass |
| 4.2 | Break ring is left of Magic Shield; Shred ring is left of Armor; values match the unit | pass |
| 4.3 | No hit %, crit %, dice or other text on hover | pass |
| 5.1 | Choosing an action enters target selection | pass |
| 5.2 | Choosing a target opens the target panel on the enemy sprite | pass |
| 5.3 | Target panel shows hit %, crit %, damage range, projected HP, CONFIRM, CANCEL | pass |
| 5.4 | CANCEL button and Esc return to target selection with AP unchanged | pass |
| 5.5 | CONFIRM runs the attack and spends AP | pass |
| 6.1 | From CONFIRM, the hover preview is locked to the target | pass |
| 6.2 | Hovering another unit does not change it | pass |
| 6.3 | It stays locked while the log is playing, and unlocks when the log finishes | pass |
| 7.1 | Rendered hover panel uses 4 shades + 1 accent (`#f8f8f8 #181820 #c8d0c0 #787880` + `#e03830`) | pass (pixel audit of the screenshot) |
| 7.2 | Ring pixels are opaque or clear only (no anti-aliasing) | pass |
| 7.3 | Pixel font, nearest filtering | pass |
| 7.4 | Integer pixel scaling at your 1280x720 window override | **fail / not verified**, see below |

### Not verified

- **Integer scaling.** `project.godot` has a 1920x1080 base with a 1280x720 window override, a 0.667 scale, which is not an integer. I only rendered at 1920x1080. To get integer scaling set `display/window/stretch/scale_mode="integer"` and either use a 1920x1080 window or a smaller base size. I did not change your display settings.
- Real mouse clicks on the menu buttons and the CONFIRM / CANCEL buttons (the signals were driven directly), and gamepad hardware.
- Interaction between the pending-confirm state and enemy opportunity-attack prompts during MOVE beyond what `test_combat_director.gd` soak already covers (it bypasses the HUD).
- Tile-locked spells aimed at an empty tile show a "TILE x,y" panel with the forecast and no unit bars; I rendered units only.
