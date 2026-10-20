extends RefCounted
## Builds the styleboxes the hotbar uses, so every box matches the unit panel (ui/theme/gbc_frame.png: the
## double-line frame) and the flat theme buttons. Colours come from gbc_palette.gd.

const Palette = preload("res://ui/theme/gbc_palette.gd")
const FRAME_TEXTURE: Texture2D = preload("res://ui/theme/gbc_frame.png")

## Thickness of the frame's line stack (outer line, gap, inner line). A tab sits this far over the box's
## top border so the border is open underneath it.
const FRAME_PX := 6
const FRAME_SIZE := 26
const FRAME_CORNER := 12
## Side content margin of every box and tab. Shared so tab edges line up with the box below.
const MARGIN_X := 10.0

## The unit panel's frame, with a tighter content margin than the theme's 16 / 12.
static func frame(margin_x: float = MARGIN_X, margin_y: float = 10.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = FRAME_TEXTURE
	sb.texture_margin_left = FRAME_CORNER
	sb.texture_margin_right = FRAME_CORNER
	sb.texture_margin_top = FRAME_CORNER
	sb.texture_margin_bottom = FRAME_CORNER
	sb.content_margin_left = margin_x
	sb.content_margin_right = margin_x
	sb.content_margin_top = margin_y
	sb.content_margin_bottom = margin_y
	return sb

## The same frame with no bottom edge: the top half of the frame texture plus two straight rows, so the
## side lines run off the bottom. Sits on top of a box and reads as one of its tabs. The bottom content
## margin includes the FRAME_PX the tab overlaps the box by.
static func tab(margin_x: float = MARGIN_X, margin_top: float = 8.0, margin_bottom: float = 8.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = FRAME_TEXTURE
	sb.region_rect = Rect2(0.0, 0.0, float(FRAME_SIZE), float(FRAME_CORNER + 2))
	sb.texture_margin_left = FRAME_CORNER
	sb.texture_margin_right = FRAME_CORNER
	sb.texture_margin_top = FRAME_CORNER
	sb.texture_margin_bottom = 0.0
	sb.content_margin_left = margin_x
	sb.content_margin_right = margin_x
	sb.content_margin_top = margin_top
	sb.content_margin_bottom = margin_bottom
	return sb

## A flat box like the theme's buttons: square corners, solid border, no bevel. `margin` = content margin.
static func box(face: Color = Palette.PANEL, edge: Color = Palette.INK, edge_w: int = 2, margin: float = 0.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = face
	b.border_color = edge
	b.set_border_width_all(edge_w)
	if margin > 0.0:
		b.set_content_margin_all(margin)
	return b

## Button states, same as the theme: normal, hover (thick border), pressed (ink fill), disabled (grey).
static func style_button(b: Button, edge_w: int = 2) -> void:
	b.add_theme_stylebox_override("normal", box(Palette.PANEL, Palette.INK, edge_w, 4.0))
	b.add_theme_stylebox_override("hover", box(Palette.PANEL, Palette.INK, 4, 4.0))
	b.add_theme_stylebox_override("hover_pressed", box(Palette.INK, Palette.INK, 4, 4.0))
	b.add_theme_stylebox_override("pressed", box(Palette.INK, Palette.INK, edge_w, 4.0))
	b.add_theme_stylebox_override("disabled", box(Palette.PANEL, Palette.INK_LIGHT, 2, 4.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
