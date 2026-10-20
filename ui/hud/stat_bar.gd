extends Control
## One flat HUD bar: caption | bar | "n/max". Hard pixel track, flat fill, no gradient, no outline.
## Solid when `segments` is 0, otherwise that many equal blocks. A same-unit change slides to the
## new value over `anim_seconds`; set_values(..., snap = true) jumps (used when the unit changes).

const Palette = preload("res://ui/theme/gbc_palette.gd")

const FONT := 16
const BAR_H := 16.0
## Fixed-width pixel font: 12 px per glyph at size 16.
const CAPTION_W := 5.0 * 12.0 + 8.0
const NUMS_W := 7.0 * 12.0 + 4.0
const SEG_GAP := 2.0

@export var caption := "HP"
@export var fill_color: Color = Palette.INK
@export var segments := 0
@export var anim_seconds := 0.25

var _target := 0
var _max := 0
var _shown := 0.0
## Points an attack would take off this bar, drawn dark gray at the end of the fill. 0 = no preview.
var _preview := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, BAR_H + 4.0)
	set_process(false)

func set_values(value: int, max_value: int, snap: bool) -> void:
	_target = value
	_max = max_value
	if snap or anim_seconds <= 0.0:
		_shown = float(value)
		set_process(false)
	else:
		set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_shown = move_toward(_shown, float(_target), maxf(float(_max) * delta / maxf(anim_seconds, 0.01), 0.001))
	if is_equal_approx(_shown, float(_target)):
		set_process(false)
	queue_redraw()

## amount <= 0 clears the preview.
func set_preview(amount: int) -> void:
	amount = maxi(amount, 0)
	if amount == _preview:
		return
	_preview = amount
	queue_redraw()

func shown_value() -> float:
	return _shown

func _draw() -> void:
	var font := get_theme_default_font()
	var live := _max > 0
	var ink := Palette.INK if live else Palette.INK_LIGHT
	var y := floorf((size.y - BAR_H) * 0.5)
	var baseline := y + floorf((BAR_H + font.get_ascent(FONT) - font.get_descent(FONT)) * 0.5)
	draw_string(font, Vector2(0.0, baseline), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	draw_string(font, Vector2(size.x - NUMS_W, baseline), "%d/%d" % [_target, _max], HORIZONTAL_ALIGNMENT_RIGHT, NUMS_W - 4.0, FONT, ink)
	var rect := Rect2(CAPTION_W, y, maxf(size.x - CAPTION_W - NUMS_W, 8.0), BAR_H)
	draw_rect(rect, ink)
	var inner := rect.grow(-2.0)
	draw_rect(inner, Palette.BG)
	if not live:
		return
	var ratio := clampf(_shown / float(_max), 0.0, 1.0)
	var kept_ratio := clampf((_shown - float(_preview)) / float(_max), 0.0, 1.0)
	if segments <= 0:
		if ratio > 0.0:
			var w := maxf(2.0, floorf(inner.size.x * ratio / 2.0) * 2.0)
			var kept_w := 0.0 if kept_ratio <= 0.0 else minf(w, maxf(2.0, floorf(inner.size.x * kept_ratio / 2.0) * 2.0))
			if _preview <= 0:
				kept_w = w
			if kept_w > 0.0:
				draw_rect(Rect2(inner.position, Vector2(kept_w, inner.size.y)), fill_color)
			if w > kept_w:
				draw_rect(Rect2(inner.position + Vector2(kept_w, 0.0), Vector2(w - kept_w, inner.size.y)), Palette.SPENT_PREVIEW)
		return
	var seg_w := floorf((inner.size.x - SEG_GAP * float(segments - 1)) / float(segments))
	var total := seg_w * float(segments) + SEG_GAP * float(segments - 1)
	var x0 := inner.position.x + floorf((inner.size.x - total) * 0.5)
	var lit := ceili(ratio * float(segments) - 0.001)
	var kept := lit if _preview <= 0 else ceili(kept_ratio * float(segments) - 0.001)
	for i in lit:
		var face: Color = fill_color if i < kept else Palette.SPENT_PREVIEW
		draw_rect(Rect2(x0 + float(i) * (seg_w + SEG_GAP), inner.position.y, seg_w, inner.size.y), face)
