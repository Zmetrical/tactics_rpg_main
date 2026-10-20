class_name CommandMenu
extends PanelContainer
## Bottom-center vertical menu: one entry per ability, then End Turn.
## Emits intent only; battle_view decides what it means.

signal ability_pressed(ability: Ability)
signal end_turn_pressed

const Ability = preload("res://scripts/battle/ability.gd")
const AbilityText = preload("res://ui/ability_text.gd")
const Unit = preload("res://scripts/battle/unit.gd")

## Prefix on the entry that is currently targeting.
@export var active_marker: String = "> "

@onready var _hint: Label = %Hint
@onready var _entries: VBoxContainer = %Entries
@onready var _end_turn: Button = %EndTurn

var _unit: Unit = null
var _buttons: Array[Button] = []

func _ready() -> void:
	_end_turn.pressed.connect(func() -> void: end_turn_pressed.emit())

## can_act: it is the player's turn, the unit is not mid-cast and not walking.
## targeting: the ability currently being aimed, or null.
func update_commands(unit: Unit, can_act: bool, targeting: Ability, can_end_turn: bool) -> void:
	if unit != _unit or (unit != null and _buttons.size() != unit.abilities.size()):
		_rebuild(unit)
	_unit = unit
	_hint.visible = can_act and targeting == null
	_end_turn.disabled = not can_end_turn
	if unit == null:
		return
	for i in _buttons.size():
		var a: Ability = unit.abilities[i]
		_buttons[i].text = _entry_text(unit, a, a == targeting)
		_buttons[i].disabled = not can_act or not unit.can_use(a)

func _rebuild(unit: Unit) -> void:
	for b in _buttons:
		_entries.remove_child(b)
		b.queue_free()
	_buttons.clear()
	if unit == null:
		return
	for a: Ability in unit.abilities:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: ability_pressed.emit(a))
		_entries.add_child(b)
		_buttons.append(b)

func _entry_text(unit: Unit, a: Ability, is_targeting: bool) -> String:
	var lines: Array[String] = [
		"%s%s   [%s]" % [active_marker if is_targeting else "", a.display_name, AbilityText.cost_name(a)],
		"%s | %s" % [AbilityText.resource_text(unit, a), AbilityText.shape_text(a)],
	]
	var charge := AbilityText.charge_text(a)
	if charge != "":
		lines.append(charge)
	return "\n".join(lines)
