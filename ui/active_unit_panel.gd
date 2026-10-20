class_name ActiveUnitPanel
extends PanelContainer
## Bottom-left panel for the unit whose turn it is. Read-only view of a Unit.

const SideTint = preload("res://ui/side_tint.gd")
const AbilityText = preload("res://ui/ability_text.gd")
const Tuning = preload("res://scripts/battle/combat_tuning.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const UnitPortrait = preload("res://ui/unit_portrait.gd")
const VitalsBar = preload("res://ui/vitals_bar.gd")

@export var hp_tween_seconds: float = 0.25
## Alpha of the AP readout when the unit cannot afford even a Base attack.
@export_range(0.0, 1.0) var spent_alpha: float = 0.5

@onready var _portrait: UnitPortrait = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _side_tag: Label = %SideTag
@onready var _vitals: VitalsBar = %Vitals
@onready var _ap: Label = %Ap
@onready var _move: Label = %Move
@onready var _costs: Label = %Costs

var _unit: Unit = null

func _ready() -> void:
	_vitals.anim_seconds = hp_tween_seconds

func update_unit(unit: Unit) -> void:
	visible = unit != null
	if unit == null:
		_unit = null
		return
	_unit = unit
	_portrait.set_unit(unit)
	_name_label.text = unit.unit_name
	_side_tag.text = SideTint.side_name(unit.side).to_upper()
	_side_tag.add_theme_color_override("font_color", SideTint.color_for(unit.side))
	_vitals.set_unit(unit)
	_ap.text = "AP %s/%s" % [AbilityText.ap_str(unit.ap), AbilityText.ap_str(unit.max_ap)]
	_ap.modulate.a = 1.0 if unit.can_afford(Tuning.AP_ATTACK_COST) else spent_alpha
	_move.text = "MOVE %d/%d" % [unit.movement, unit.move_range]
	_costs.text = _costs_text()

## What one attack or spell costs, so the player can plan the turn: Base / Tier 2 / Tier 3, plus regen per turn.
func _costs_text() -> String:
	return "COST %s/%s/%s AP +%s/TURN" % [
		AbilityText.ap_str(Tuning.AP_ATTACK_COST),
		AbilityText.ap_str(Tuning.AP_ATTACK_COST + Tuning.AP_TIER2_SURCHARGE),
		AbilityText.ap_str(Tuning.AP_ATTACK_COST + Tuning.AP_TIER3_SURCHARGE),
		AbilityText.ap_str(Tuning.AP_REGEN)]
