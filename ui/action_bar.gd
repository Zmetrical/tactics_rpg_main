class_name ActionBar
extends HBoxContainer
## Bottom-center action bar, Baldur's Gate style: weapon actions, spell actions, a short
## description box that also holds the Tier / Lock controls while aiming, and the Equipment (I) button.
## Emits intent only; battle_view decides what a press means. Same API as the old command menu.

signal ability_pressed(ability: Ability)
signal end_turn_pressed
signal equipment_pressed
## Tier button pressed while aiming a tiered spell (same as keys 1 / 2 / 3).
signal tier_selected(tier: int)
## Lock Tile / Unit button pressed while aiming a charged spell: false = the tile, true = the unit.
signal lock_mode_changed(lock_on_unit: bool)

const Ability = preload("res://scripts/battle/ability.gd")
const AbilityText = preload("res://ui/ability_text.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const AbilitySlotScript = preload("res://ui/ability_slot.gd")

## Squares always shown per group, so the bar keeps its size. More abilities add rows.
const MIN_WEAPON_SLOTS := 6
const MIN_SPELL_SLOTS := 8
const HINT := "Click a tile to move, or pick an ability."

@onready var _weapon_grid: GridContainer = %WeaponGrid
@onready var _spell_grid: GridContainer = %SpellGrid
@onready var _end_turn: Button = %EndTurn
@onready var _description: Label = %Description
@onready var _aim_box: VBoxContainer = %AimBox
@onready var _tier_row: HBoxContainer = %TierRow
@onready var _tier1: Button = %Tier1
@onready var _tier2: Button = %Tier2
@onready var _tier3: Button = %Tier3
@onready var _lock_row: HBoxContainer = %LockRow
@onready var _lock_tile: Button = %LockTile
@onready var _lock_unit: Button = %LockUnit
@onready var _equipment: Button = %EquipmentButton

var _unit: Unit = null
var _shown: Array[Ability] = []
var _slots: Array[AbilitySlotScript] = []
var _hovered: Ability = null
var _targeting: Ability = null
var _can_act: bool = false
var _tier_buttons: Array[Button] = []
var _aim_tier: int = 1
var _aim_lock_unit: bool = false

func _ready() -> void:
	_tier_buttons = [_tier1, _tier2, _tier3]
	_end_turn.pressed.connect(func() -> void: end_turn_pressed.emit())
	_equipment.pressed.connect(func() -> void: equipment_pressed.emit())
	for i in _tier_buttons.size():
		var tier := i + 1
		_tier_buttons[i].pressed.connect(func() -> void: tier_selected.emit(tier))
	_lock_tile.pressed.connect(func() -> void: lock_mode_changed.emit(false))
	_lock_unit.pressed.connect(func() -> void: lock_mode_changed.emit(true))
	_refresh_description()
	_refresh_aim()

## can_act: it is the player's turn, the unit is not mid-cast and not walking.
## targeting: the ability currently being aimed, or null.
func update_commands(unit: Unit, can_act: bool, targeting: Ability, can_end_turn: bool) -> void:
	if unit != _unit or (unit != null and unit.abilities != _shown):
		_rebuild(unit)
	_unit = unit
	_can_act = can_act
	_targeting = targeting
	_end_turn.disabled = not can_end_turn
	if unit != null:
		for slot in _slots:
			slot.set_state(can_act and unit.can_use(slot.ability), slot.ability == targeting)
	_refresh_description()
	_refresh_aim()

## Current Tier / Lock choice for the ability being aimed. battle_view calls this whenever the
## preview refreshes, so the buttons always show what a click would do.
func set_aim(tier: int, lock_on_unit: bool) -> void:
	_aim_tier = tier
	_aim_lock_unit = lock_on_unit
	_refresh_aim()

## Tier row: only for spells with tiers. Lock row: only for charged spells. The whole box is
## hidden for plain attacks, so the bar stays quiet unless there is a choice to make.
func _refresh_aim() -> void:
	var a := _targeting
	if _unit == null or a == null:
		_aim_box.visible = false
		return
	var tiers := AbilityText.tier_count(a)
	_tier_row.visible = tiers > 1
	_lock_row.visible = a.is_charged()
	_aim_box.visible = _tier_row.visible or _lock_row.visible
	for i in _tier_buttons.size():
		var tier := i + 1
		var btn := _tier_buttons[i]
		btn.visible = tier <= tiers
		if tier > tiers:
			continue
		var cost := a.ap_cost_for_tier(tier)
		btn.text = "%d  %s AP" % [tier, AbilityText.ap_str(cost)]
		btn.set_pressed_no_signal(tier == _aim_tier)
		btn.disabled = tier != _aim_tier and not _unit.can_afford(cost)
	_lock_tile.set_pressed_no_signal(not _aim_lock_unit)
	_lock_unit.set_pressed_no_signal(_aim_lock_unit)

func _rebuild(unit: Unit) -> void:
	for grid: GridContainer in [_weapon_grid, _spell_grid]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	_slots.clear()
	_shown.clear()
	_hovered = null
	if unit == null:
		_pad(_weapon_grid, 0, MIN_WEAPON_SLOTS)
		_pad(_spell_grid, 0, MIN_SPELL_SLOTS)
		return
	_shown = unit.abilities.duplicate()
	var weapons := 0
	var spells := 0
	for a: Ability in unit.abilities:
		if AbilityText.is_spell(a):
			_add_slot(_spell_grid, a)
			spells += 1
		else:
			_add_slot(_weapon_grid, a)
			weapons += 1
	_pad(_weapon_grid, weapons, MIN_WEAPON_SLOTS)
	_pad(_spell_grid, spells, MIN_SPELL_SLOTS)

func _add_slot(grid: GridContainer, a: Ability) -> void:
	var slot := AbilitySlotScript.new()
	grid.add_child(slot)
	slot.setup(a)
	slot.pressed.connect(func() -> void: ability_pressed.emit(a))
	slot.mouse_entered.connect(func() -> void:
		_hovered = a
		_refresh_description())
	slot.mouse_exited.connect(func() -> void:
		if _hovered == a:
			_hovered = null
			_refresh_description())
	_slots.append(slot)

## Fill the group out to its minimum, then to a whole last row.
func _pad(grid: GridContainer, used: int, minimum: int) -> void:
	var total := maxi(used, minimum)
	total = int(ceil(float(total) / float(grid.columns))) * grid.columns
	for _i in total - used:
		var empty := AbilitySlotScript.new()
		grid.add_child(empty)
		empty.setup(null)

func _refresh_description() -> void:
	var shown: Ability = _hovered if _hovered != null else _targeting
	if _unit == null:
		_description.text = ""
	elif shown != null:
		_description.text = AbilityText.brief(shown)
	elif _can_act:
		_description.text = HINT
	else:
		_description.text = "Hover an ability to read about it."
