extends HBoxContainer
## One pending cast: caster, spell, ticks left. Call set_entry() after the node is in the tree.

const SideTint = preload("res://ui/side_tint.gd")
const Unit = preload("res://scripts/battle/unit.gd")

@onready var _caster: Label = %Caster
@onready var _spell: Label = %Spell
@onready var _ticks: Label = %Ticks

func set_entry(caster: Unit, spell: String, ticks_left: int) -> void:
	_caster.text = caster.unit_name
	_caster.add_theme_color_override("font_color", SideTint.color_for(caster.side))
	_spell.text = spell
	_ticks.text = "%d tick%s" % [ticks_left, "" if ticks_left == 1 else "s"]
