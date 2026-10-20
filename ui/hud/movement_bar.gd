extends Control
## The movement bar, top of the hotbar next to the AP bar: one segment per tile of movement, filled
## for the tiles the current unit still has. Display only. Hover shows a tooltip. No number label: the segments and the tooltip say it.
##
## Hover a reachable tile on the map and set_preview(cost) marks the segments that walking there would
## spend. Nothing is spent until the player clicks; the bar then drops by the whole cost at once.

const Palette = preload("res://ui/theme/gbc_palette.gd")

## About 30% shorter than the AP bar.
const HEIGHT := 14.0

var value := 0
var max_value := 0
## Tiles the hovered destination would cost, or 0 for no preview.
var preview := 0
## False greys the whole bar out (hotbar locked). No preview is drawn while disabled.
var enabled := true

func _ready() -> void:
	custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_tooltip()

func set_values(p_value: int, p_max: int) -> void:
	if p_value == value and p_max == max_value:
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
func set_preview(cost: int) -> void:
	var c := clampi(cost, 0, value) if enabled else 0
	if c == preview:
		return
	preview = c
	queue_redraw()

func _refresh_tooltip() -> void:
	tooltip_text = "Movement: %d of %d tiles left.\nClick a blue tile on the map to walk there." % [value, max_value]

func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, size)
	var edge: Color = Palette.INK if enabled else Palette.INK_LIGHT
	draw_rect(outer, edge)
	var inner := outer.grow(-2.0)
	draw_rect(inner, Palette.PANEL)
	if max_value > 0 and inner.size.x > 0.0:
		var seg := inner.size.x / float(max_value)
		var kept := value - preview
		draw_rect(Rect2(inner.position, Vector2(seg * float(kept), inner.size.y)), Palette.ACCENT if enabled else Palette.DISABLED_FILL)
		if preview > 0:
			# The tiles this walk would spend.
			draw_rect(Rect2(inner.position + Vector2(seg * float(kept), 0.0), Vector2(seg * float(preview), inner.size.y)), Palette.MOVE_PREVIEW)
		for i in range(1, max_value):
			var x := inner.position.x + seg * float(i)
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), edge, 2.0)
