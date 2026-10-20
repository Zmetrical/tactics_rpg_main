extends Control
## The separator between hotbar sections, flat ink only: a 2 px groove capped at both ends with an ink
## diamond (white centre), plus an accent stud in the middle when it is long enough.
## Vertical by default; set `vertical = false` for a horizontal one. Display only.

const Palette = preload("res://ui/theme/gbc_palette.gd")

const THICK := 7.0

@export var vertical := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(THICK, 0.0) if vertical else Vector2(0.0, THICK)
	if vertical:
		size_flags_vertical = Control.SIZE_FILL
	else:
		size_flags_horizontal = Control.SIZE_FILL

func _draw() -> void:
	# Everything is drawn as if vertical (x across, y along); a horizontal divider is that, transposed.
	var along := size.y if vertical else size.x
	var across := size.x if vertical else size.y
	if not vertical:
		draw_set_transform_matrix(Transform2D(Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2.ZERO))
	var cx := floorf(across * 0.5)
	var r := 3.0 if along < 60.0 else 4.0
	var cap := r * 2.0 + 1.0
	if along > cap * 2.0:
		draw_rect(Rect2(cx - 1.0, cap, 2.0, along - cap * 2.0), Palette.INK)
		if along >= 60.0:
			_diamond(Vector2(cx, along * 0.5), 3.0, Palette.ACCENT, Palette.PANEL)
	_diamond(Vector2(cx, r + 0.5), r, Palette.INK, Palette.PANEL)
	_diamond(Vector2(cx, along - r - 0.5), r, Palette.INK, Palette.PANEL)

func _diamond(center: Vector2, radius: float, outer: Color, core: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0)]), outer)
	var inner := radius - 2.0
	if inner > 0.0:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0.0, -inner), center + Vector2(inner, 0.0),
			center + Vector2(0.0, inner), center + Vector2(-inner, 0.0)]), core)
	else:
		draw_rect(Rect2(center - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), core)
