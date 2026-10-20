extends RefCounted
## Game Boy Color-style palette: the only place HUD colours are defined.
## The theme (tactics_theme.tres) mirrors INK / PANEL / INK_LIGHT; keep them in sync if you change them.
##
## Eight core tokens, plus three meter colours so Magic Barrier / Armor Shred / Fracture
## stay tellable apart from the health bar.

# --- core ---
## Screen background / empty track behind a bar.
const BG := Color("c8d0c0")
## Panel and text-box fill.
const PANEL := Color("f8f8f8")
## Text, borders, and the "selected" fill.
const INK := Color("181820")
## Secondary text, disabled borders, physical armor fill.
const INK_LIGHT := Color("787880")
const HP_GREEN := Color("38b840")
const HP_YELLOW := Color("f8c820")
const HP_RED := Color("e03830")
## Player side, aiming outline, magic barrier.
const ACCENT := Color("3868d8")

# --- meters ---
const MAGIC_BARRIER := ACCENT
const PHYSICAL_ARMOR := INK_LIGHT
const ARMOR_SHRED := Color("e88028")
const FRACTURE := Color("8858d8")
## Dark gray for every "this would be spent / lost" preview: movement tiles, AP, and the damage an attack would deal.
const SPENT_PREVIEW := Color("505058")
## Filled part of a bar that is switched off (bar locked: text playing, window open, not the player's input).
const DISABLED_FILL := Color("a8acb0")
const MOVE_PREVIEW := SPENT_PREVIEW

## HP bar turns yellow at or below this share of max, red at or below the next.
const HP_YELLOW_AT := 0.5
const HP_RED_AT := 0.2

## Pokemon-style health colour: green above half, yellow down to a fifth, red below that.
static func hp_color(ratio: float) -> Color:
	if ratio <= HP_RED_AT:
		return HP_RED
	if ratio <= HP_YELLOW_AT:
		return HP_YELLOW
	return HP_GREEN
