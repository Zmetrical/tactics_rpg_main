extends Control
## Diamond-framed portrait. Every shape is built from 1 px rows (no polygons, no arcs), so the
## edges are hard pixel staircases. The unit's front sprite frame is drawn at an integer 2x scale,
## clipped row by row to the inner diamond. Units without a sprite show their first letter.

const Palette = preload("res://ui/theme/gbc_palette.gd")

const SIZE := 72
const SPRITE_SCALE := 2
const FRAME_PX := 32
const LETTER_FONT := 32
## Diamond insets (px from the outer tip): INK outline, accent band, INK line, then the fill.
const INSET_ACCENT := 3
const INSET_LINE := 6
const INSET_FILL := 7

var _view: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(SIZE, SIZE)

func set_view(view: Dictionary) -> void:
	_view = view
	queue_redraw()

## Half width (px) of a diamond inset by `inset`, at the row whose centre is `dy` px from the middle.
static func half_width(inset: int, dy: float) -> float:
	return floorf(float(SIZE) * 0.5 - float(inset) - absf(dy))

func _diamond(inset: int, color: Color) -> void:
	for y in SIZE:
		var hw := half_width(inset, y + 0.5 - SIZE * 0.5)
		if hw > 0.0:
			draw_rect(Rect2(SIZE * 0.5 - hw, y, hw * 2.0, 1.0), color)

func _draw() -> void:
	if _view.is_empty():
		return
	var accent: Color = _view["accent"]
	_diamond(0, Palette.INK)
	_diamond(INSET_ACCENT, accent)
	_diamond(INSET_LINE, Palette.INK)
	_diamond(INSET_FILL, Palette.BG)
	var tex: Texture2D = _view["sprite_tex"]
	if tex == null:
		var font := get_theme_default_font()
		var text: String = _view["letter"]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_FONT).x
		var base := floorf((SIZE + font.get_ascent(LETTER_FONT) - font.get_descent(LETTER_FONT)) * 0.5)
		draw_string(font, Vector2(floorf((SIZE - w) * 0.5), base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_FONT, Palette.INK)
		return
	var src: Rect2 = _view["sprite_rect"]
	var origin := (SIZE - FRAME_PX * SPRITE_SCALE) / 2
	for row in FRAME_PX:
		var dest_y := origin + row * SPRITE_SCALE
		# Clip each source row to the inner diamond, symmetric around the sprite centre.
		var hw := half_width(INSET_FILL, dest_y + SPRITE_SCALE * 0.5 - SIZE * 0.5)
		var src_half := int(floorf(hw / SPRITE_SCALE))
		if src_half <= 0:
			continue
		var half_frame := FRAME_PX / 2
		draw_texture_rect_region(tex,
			Rect2(origin + (half_frame - src_half) * SPRITE_SCALE, dest_y, src_half * 2 * SPRITE_SCALE, SPRITE_SCALE),
			Rect2(src.position.x + half_frame - src_half, src.position.y + row, src_half * 2, 1))
