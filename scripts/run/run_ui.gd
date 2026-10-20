extends RefCounted
## Pieces shared by the run screens so they look like the battle HUD (ui/hud/hud_style.gd, gbc_palette.gd).

const Palette = preload("res://ui/theme/gbc_palette.gd")
const HudDivider = preload("res://ui/hud/hud_divider.gd")

## Indexed by Loot rarity (common, uncommon, rare). Dark enough to read on the white panels.
const RARITY_COLORS: Array[Color] = [Palette.INK, Palette.HP_GREEN, Palette.ACCENT]

## A flat ink-bordered card, the theme's InnerPanel (same box the equipment window uses).
static func card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InnerPanel"
	return panel

static func label(parent: Node, text: String, color: Color = Palette.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

## The horizontal ornate divider the hotbar uses between sections.
static func divider() -> Control:
	var d := HudDivider.new()
	d.vertical = false
	return d
