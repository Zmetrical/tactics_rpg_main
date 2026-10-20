extends Control
## The action point bar, top left of the hotbar. One block per whole AP, each split in two halves so
## a half point (the 1.5 AP base cost and the tier costs) is visible. Filled halves = AP the unit has.
## Flat GBC look: ink-outlined pips, white when empty, green when filled. All pips are the same size.
## Display only. Hover shows a tooltip.

const Palette = preload("res://ui/theme/gbc_palette.gd")

## About 30% taller than the movement bar.
const HEIGHT := 26.0
## Pixels between two whole AP blocks (the first few gaps may get 1 px extra so the row fills the bar).
const BLOCK_GAP := 4
## Border thickness of a pip. The two halves of one AP share their middle border.
const BORDER := 2

var value := 0.0
var max_value := 0.0
## AP the hovered / aimed ability would spend, or 0 for no preview. Drawn dark gray on the halves it would empty.
var preview := 0.0
## False greys the whole bar out (hotbar locked). No preview is drawn while disabled.
var enabled := true

func _ready() -> void:
	custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_tooltip()

func set_values(p_value: float, p_max: float) -> void:
	if is_equal_approx(p_value, value) and is_equal_approx(p_max, max_value):
		return
	value = p_value
	max_value = p_max
	_refresh_tooltip()
	queue_redraw()

func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	queue_redraw()

## cost <= 0 clears the preview.
func set_preview(cost: float) -> void:
	var c := clampf(cost, 0.0, value)
	if is_equal_approx(c, preview):
		return
	preview = c
	queue_redraw()

func _refresh_tooltip() -> void:
	tooltip_text = "Action points: %s of %s.\nWeapon attacks and spells spend AP." % [_fmt(value), _fmt(max_value)]

func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, floorf(v)) else "%.1f" % v

func _draw() -> void:
	var blocks := int(ceilf(max_value))
	if blocks <= 0:
		return
	var width := int(size.x)
	var height := int(size.y)
	# Whole-pixel sizes so every pip is identical: a block is two halves sharing one border.
	var block_w := (width - BLOCK_GAP * (blocks - 1)) / blocks
	var half_w := (block_w + BORDER) / 2
	block_w = half_w * 2 - BORDER
	var spare := width - block_w * blocks - BLOCK_GAP * (blocks - 1)
	var extra_each := spare / maxi(blocks - 1, 1)
	var extra_rest := spare - extra_each * maxi(blocks - 1, 1)
	var x := 0
	for b in blocks:
		for h in 2:
			var rect := Rect2(float(x + h * (half_w - BORDER)), 0.0, float(half_w), float(height))
			var threshold := float(b) + float(h) * 0.5 + 0.5 - 0.001
			var lit := value >= threshold
			var kept := not enabled or value - preview >= threshold
			var face: Color = Palette.PANEL
			if lit:
				face = Palette.HP_GREEN if kept else Palette.SPENT_PREVIEW
				if not enabled:
					face = Palette.DISABLED_FILL
			draw_rect(rect, Palette.INK if enabled else Palette.INK_LIGHT)
			draw_rect(rect.grow(-float(BORDER)), face)
		x += block_w + BLOCK_GAP + extra_each + (1 if b < extra_rest else 0)
