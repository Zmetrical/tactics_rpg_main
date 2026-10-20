extends Control
## Ring meter with a number in the middle (Fracture / Shred, 0-7).
##
## The ring is painted pixel by pixel into a small Image and shown with nearest-neighbour
## filtering at an integer scale, so the edge is a hard pixel staircase: no anti-aliasing, no
## draw_arc. The fill runs clockwise from 12 o'clock. Image is rebuilt only when a value changes.

const Palette = preload("res://ui/theme/gbc_palette.gd")

## Image size in meter pixels, and the integer scale it is drawn at (one meter pixel = 2 screen px,
## the same as the pixel font's 2x).
const IMG := 20
const SCALE := 2
## Distance bands from the centre, in meter pixels: [0,HOLE) panel, [HOLE,TRACK) border,
## [TRACK,EDGE) fill band (2 px), [EDGE,RADIUS) border.
const HOLE := 6.0
const TRACK := 7.0
const EDGE := 9.0
const RADIUS := 10.0
const FONT := 16

@export var fill_color: Color = Palette.INK:
	set(value):
		fill_color = value
		_rebuild()

var value := 0
var max_value := 7
var _tex: ImageTexture = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(IMG * SCALE, IMG * SCALE)
	_rebuild()

func set_value(new_value: int, new_max: int) -> void:
	if new_value == value and new_max == max_value and _tex != null:
		return
	value = new_value
	max_value = maxi(new_max, 1)
	_rebuild()

## Pixels lit in the fill band for the current value (used by the tests).
func filled_pixels() -> int:
	var img := _image()
	var n := 0
	for y in IMG:
		for x in IMG:
			if img.get_pixel(x, y) == fill_color and _band(x, y) == 2:
				n += 1
	return n

func _band(x: int, y: int) -> int:
	var d := Vector2(x + 0.5 - IMG * 0.5, y + 0.5 - IMG * 0.5).length()
	if d >= RADIUS:
		return 0
	if d >= EDGE:
		return 1
	if d >= TRACK:
		return 2
	if d >= HOLE:
		return 1
	return 3

func _image() -> Image:
	var img := Image.create(IMG, IMG, false, Image.FORMAT_RGBA8)
	var ratio := clampf(float(value) / float(max_value), 0.0, 1.0)
	for y in IMG:
		for x in IMG:
			var c := Color(0, 0, 0, 0)
			match _band(x, y):
				1:
					c = Palette.INK
				2:
					# Clockwise from 12 o'clock.
					var dx := x + 0.5 - IMG * 0.5
					var dy := y + 0.5 - IMG * 0.5
					var turn := fposmod(atan2(dx, -dy), TAU) / TAU
					c = fill_color if turn < ratio else Palette.BG
				3:
					c = Palette.PANEL
			img.set_pixel(x, y, c)
	return img

func _rebuild() -> void:
	_tex = ImageTexture.create_from_image(_image())
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(IMG * SCALE, IMG * SCALE)), false)
	var font := get_theme_default_font()
	var text := str(value)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
	var base := floorf((IMG * SCALE + font.get_ascent(FONT) - font.get_descent(FONT)) * 0.5)
	draw_string(font, Vector2(floorf((IMG * SCALE - w) * 0.5), base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, Palette.INK)
