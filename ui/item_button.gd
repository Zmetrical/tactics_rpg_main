extends Button
## A bag row: just the item name. Kind (one-handed, ring, ...), properties and the ability it grants
## are in the hover tooltip card, the same card style the hotbar's gear slots use.

const AbilityText = preload("res://ui/ability_text.gd")
const Item = preload("res://scripts/inventory/item.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const TooltipCard = preload("res://ui/hud/tooltip_card.gd")

var _tip := {}

func setup(item: Item) -> void:
	text = item.display_name
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tip = tip_for(item)
	tooltip_text = item.display_name

static func tip_for(item: Item) -> Dictionary:
	var sections: Array[Dictionary] = []
	if item.defense_summary() != "":
		sections.append({"heading": "PROPERTIES", "marker": Palette.INK_LIGHT, "lines": [item.defense_summary()]})
	if item.requirement_summary() != "":
		sections.append({"heading": "REQUIRES", "marker": Palette.INK_LIGHT, "lines": [item.requirement_summary()]})
	if item.ability != null:
		sections.append({"heading": "GRANTS", "marker": Palette.ACCENT,
			"lines": ["%s (%s AP)" % [item.ability.display_name, AbilityText.ap_str(item.ability.ap_cost)]]})
	return {
		"title": item.display_name,
		"subtitle": item.kind_label().to_upper(),
		"body": item.description,
		"sections": sections,
	}

func _make_custom_tooltip(_for_text: String) -> Object:
	return TooltipCard.build(_tip)
