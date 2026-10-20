extends PanelContainer
## One chip in the turn order bar: marker, placeholder portrait, name.
## Call set_entry() after the node is in the tree.

const Unit = preload("res://scripts/battle/unit.gd")
const UnitPortrait = preload("res://ui/unit_portrait.gd")

const Palette = preload("res://ui/theme/gbc_palette.gd")

const RELEASE_COLOR := Palette.ACCENT

@onready var _marker: Label = %Marker
@onready var _portrait: UnitPortrait = %Portrait
@onready var _name_label: Label = %NameLabel

func set_entry(unit: Unit, marker_text: String) -> void:
	# "NOW" gets the Pokemon "next" arrow so the current unit is obvious at a glance.
	_marker.text = "\u25bcNOW" if marker_text == "NOW" else marker_text
	_portrait.set_unit(unit)
	_name_label.text = unit.unit_name

## A charged spell going off: the caster's portrait, the spell name, and an accent-coloured RELEASE marker
## so it reads differently from a normal turn.
func set_release(caster: Unit, spell: String) -> void:
	_marker.text = "RELEASE"
	_marker.add_theme_color_override("font_color", RELEASE_COLOR)
	_portrait.set_unit(caster)
	_name_label.text = spell
