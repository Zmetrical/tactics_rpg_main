extends ColorRect
## Placeholder portrait: a two-tone square with the unit's first letter.
## Player = dark tile, light letter. Enemy = light tile, dark letter (a tone swap, not a hue).
## Call set_unit() after the node is in the tree.

const Palette = preload("res://ui/theme/gbc_palette.gd")
const Unit = preload("res://scripts/battle/unit.gd")

## False keeps the tile in the light tone for both sides (the big backdrop behind the paper doll).
@export var tone_swap: bool = true

@onready var _letter: Label = $Letter

func set_unit(unit: Unit) -> void:
	var player := tone_swap and unit.side == Unit.Side.PLAYER
	color = Palette.INK if player else Palette.BG
	_letter.add_theme_color_override("font_color", Palette.PANEL if player else Palette.INK)
	_letter.text = unit.unit_name.substr(0, 1).to_upper()
