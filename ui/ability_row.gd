extends HBoxContainer
## One line in the equipment window's ability list: name on the left, AP cost on the right.
## Everything else (range, radius, charge, save, damage, tiers) is in the hover tooltip card,
## the same card the hotbar shows. Spells use the accent colour, weapon attacks the ink colour.
## Greyed when the unit can't pay for the ability right now.

const Ability = preload("res://scripts/battle/ability.gd")
const AbilityText = preload("res://ui/ability_text.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const TooltipCard = preload("res://ui/hud/tooltip_card.gd")
const Unit = preload("res://scripts/battle/unit.gd")

var _tip := {}

func setup(u: Unit, a: Ability) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_constant_override("separation", 8)
	_tip = AbilityText.tooltip(u, a)
	tooltip_text = a.display_name   # any non-empty text turns the tooltip on; _make_custom_tooltip draws the card
	var ready := u.can_use(a)
	var color: Color = Palette.INK_LIGHT
	if ready:
		color = Palette.ACCENT if AbilityText.is_spell(a) else Palette.INK
	var name_label := _label(a.display_name, color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	add_child(name_label)
	var cost := _label(AbilityText.cost_name(a), Palette.INK_LIGHT)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(cost)

func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	return l

func _make_custom_tooltip(_for_text: String) -> Object:
	return TooltipCard.build(_tip)
