extends RefCounted
## Which side a unit is on, in HUD terms. Colours come from the GBC palette; sides are also told
## apart by a two-tone swap (dark tile / light tile) wherever a portrait is drawn.

const Palette = preload("res://ui/theme/gbc_palette.gd")
const Unit = preload("res://scripts/battle/unit.gd")

const PLAYER := Palette.ACCENT
const ENEMY := Palette.HP_RED
## Portrait backdrop when no unit is shown.
const NEUTRAL := Palette.BG
## Full-screen backdrop behind modal windows.
const DIM := Color(Palette.INK, 0.5)

static func color_for(side: int) -> Color:
	return PLAYER if side == Unit.Side.PLAYER else ENEMY

static func side_name(side: int) -> String:
	return "Player" if side == Unit.Side.PLAYER else "Enemy"
