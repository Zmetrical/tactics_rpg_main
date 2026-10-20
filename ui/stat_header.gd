extends Label
## A stat header cell (STR, AC, ...) that shows a TooltipCard when hovered.
## Set `tip` to the data StatTooltip.tip() returns. Godot only asks for a custom tooltip when tooltip_text is
## not empty, so the owner gives it the stat's name as a fallback (shown as plain text while `tip` is empty).

const TooltipCard = preload("res://ui/hud/tooltip_card.gd")

var tip: Dictionary = {}

func _make_custom_tooltip(_for_text: String) -> Object:
	if tip.is_empty():
		return null
	return TooltipCard.build(tip)
