extends Control
## Game Boy Color-style vitals for one unit, drawn in a single Control (no child nodes):
##
##   BARRIER [segmented bar] n/ max      magic barrier, 10 segments
##   ARMOR [segmented bar]  n/ max      physical armor, 10 segments
##   HP:   [solid bar]      n/ max      health: green > 50%, yellow > 20%, red below
##   SHRED [pips]           n/7         armor shred stack meter
##   FRACT [pips]           n/7         fracture stack meter
##
## Flat, hard-edged pixel drawing: a black 2px track, flat fills, no gradients, no text outline.
## One pip per stack earned. The NEXT pip fills partway to show progress toward the next 12%
## threshold; that partial progress is wiped when the unit's turn starts.
## Display only. Call set_unit() whenever the unit may have changed.

const Tuning = preload("res://scripts/battle/combat_tuning.gd")
const Unit = preload("res://scripts/battle/unit.gd")

const Palette = preload("res://ui/theme/gbc_palette.gd")

const GAP := 4.0
## The pixel font is drawn at exactly one size (its native 2x), so text stays crisp.
const FONT := 16
## Segments in the Magic Barrier / Physical Armor bars.
const SEGMENTS := 10

## Compact drops the numbers and thins every row (for small spaces).
@export var compact: bool = false:
	set(value):
		compact = value
		update_minimum_size()
		queue_redraw()
## Seconds a bar takes to slide to a new value when the SAME unit is shown again.
@export var anim_seconds: float = 0.25

var _unit: Unit = null
var _d_hp: float = 0.0
var _d_physical_armor: float = 0.0
var _d_magic_barrier: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func set_unit(unit: Unit) -> void:
	var same := unit != null and unit == _unit
	_unit = unit
	if unit == null:
		set_process(false)
	elif same and anim_seconds > 0.0:
		set_process(true)
	else:
		# A different unit snaps; only the same unit slides.
		_d_hp = float(unit.hp)
		_d_physical_armor = float(unit.physical_armor)
		_d_magic_barrier = float(unit.magic_barrier)
		set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	if _unit == null:
		set_process(false)
		return
	var step := delta / maxf(anim_seconds, 0.01)
	_d_hp = move_toward(_d_hp, float(_unit.hp), maxf(float(_unit.max_hp) * step, 0.001))
	_d_physical_armor = move_toward(_d_physical_armor, float(_unit.physical_armor), maxf(float(_unit.max_physical_armor) * step, 0.001))
	_d_magic_barrier = move_toward(_d_magic_barrier, float(_unit.magic_barrier), maxf(float(_unit.max_magic_barrier) * step, 0.001))
	if is_equal_approx(_d_hp, float(_unit.hp)) and is_equal_approx(_d_physical_armor, float(_unit.physical_armor)) and is_equal_approx(_d_magic_barrier, float(_unit.magic_barrier)):
		set_process(false)
	queue_redraw()

# --- layout -------------------------------------------------------------------

func _row_h() -> float:
	return 6.0 if compact else 16.0

func _health_h() -> float:
	return 8.0 if compact else 16.0

func _get_minimum_size() -> Vector2:
	return Vector2(0.0, _row_h() * 4.0 + _health_h() + GAP * 4.0)

# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if _unit == null:
		return
	var cols := _columns()
	var y := 0.0
	_draw_segmented(y, cols, "BARRIER", _d_magic_barrier, float(_unit.max_magic_barrier), Palette.MAGIC_BARRIER,
			"%d/ %d" % [_unit.magic_barrier, _unit.max_magic_barrier])
	y += _row_h() + GAP
	_draw_segmented(y, cols, "ARMOR", _d_physical_armor, float(_unit.max_physical_armor), Palette.PHYSICAL_ARMOR,
			"%d/ %d" % [_unit.physical_armor, _unit.max_physical_armor])
	y += _row_h() + GAP
	var hp_ratio := _d_hp / float(_unit.max_hp) if _unit.max_hp > 0 else 0.0
	_draw_solid(y, cols, "HP:", hp_ratio, Palette.hp_color(hp_ratio), _unit.max_hp > 0,
			"%d/ %d" % [_unit.hp, _unit.max_hp])
	y += _health_h() + GAP
	_draw_stack_row(y, cols)

## Shared column widths so every row lines up: label | bar | numbers.
func _columns() -> Dictionary:
	if compact:
		return {"label": 0.0, "nums": 0.0}
	var font := get_theme_default_font()
	var label_w := 0.0
	for t in ["BARRIER", "ARMOR", "HP:", "SHRED", "FRACT"]:
		label_w = maxf(label_w, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x)
	var nums_w := 0.0
	for pair in [[_unit.max_magic_barrier, _unit.max_magic_barrier], [_unit.max_physical_armor, _unit.max_physical_armor], [_unit.max_hp, _unit.max_hp]]:
		nums_w = maxf(nums_w, font.get_string_size("%d/ %d" % pair, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x)
	nums_w = maxf(nums_w, font.get_string_size("%d/%d" % [Tuning.MAX_STACKS, Tuning.MAX_STACKS], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x)
	return {"label": ceilf(label_w) + 8.0, "nums": ceilf(nums_w) + 8.0}

func _bar_rect(y: float, h: float, cols: Dictionary) -> Rect2:
	var x0: float = cols["label"]
	return Rect2(x0, y, maxf(size.x - x0 - float(cols["nums"]), 8.0), h)

## Black 2px track with the empty colour inside. Returns the inner (fillable) rect.
func _draw_track(rect: Rect2, live: bool) -> Rect2:
	draw_rect(rect, Palette.INK if live else Palette.INK_LIGHT)
	var inner := rect.grow(-2.0)
	draw_rect(inner, Palette.BG)
	return inner

## HP-style bar: one flat fill, whole-pixel width, at least 2px while anything is left.
func _draw_solid(y: float, cols: Dictionary, title: String, ratio: float, color: Color, live: bool, text: String) -> void:
	var rect := _bar_rect(y, _health_h(), cols)
	var inner := _draw_track(rect, live)
	if live and ratio > 0.0:
		var w := maxf(2.0, floorf(inner.size.x * clampf(ratio, 0.0, 1.0) / 2.0) * 2.0)
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), color)
	_draw_row_text(y, _health_h(), cols, title, text, live)

## Armor / barrier bar: SEGMENTS equal blocks, a block lights up once any of its share is left.
func _draw_segmented(y: float, cols: Dictionary, title: String, value: float, max_value: float, color: Color, text: String) -> void:
	var live := max_value > 0.0
	var h := _row_h()
	var rect := _bar_rect(y, h, cols)
	# Compact rows are only 6px tall, so the track is the full row; otherwise inset the 12px bar.
	if not compact:
		rect = Rect2(rect.position.x, y + 2.0, rect.size.x, h - 4.0)
	var inner := _draw_track(rect, live)
	if live:
		var gap := 2.0
		var seg_w := floorf((inner.size.x - gap * float(SEGMENTS - 1)) / float(SEGMENTS))
		var total := seg_w * float(SEGMENTS) + gap * float(SEGMENTS - 1)
		var x0 := inner.position.x + floorf((inner.size.x - total) * 0.5)
		var lit := ceili(clampf(value / max_value, 0.0, 1.0) * float(SEGMENTS) - 0.001)
		for i in lit:
			draw_rect(Rect2(x0 + float(i) * (seg_w + gap), inner.position.y, seg_w, inner.size.y), color)
	_draw_row_text(y, h, cols, title, text, live)

func _draw_stack_row(y: float, cols: Dictionary) -> void:
	var threshold := float(_unit.max_hp) * Tuning.THRESHOLD_FRACTION
	var armor_shred_progress := _unit.physical_impact_pool / threshold if threshold > 0.0 else 0.0
	var fracture_progress := _unit.magic_impact_pool / threshold if threshold > 0.0 else 0.0
	_draw_stacks(y, cols, "SHRED", Palette.ARMOR_SHRED, _unit.armor_shred_stacks, armor_shred_progress)
	_draw_stacks(y + _row_h() + GAP, cols, "FRACT", Palette.FRACTURE, _unit.fracture_stacks, fracture_progress)

## One full-width row: title | MAX_STACKS equal pips | "n/max".
func _draw_stacks(y: float, cols: Dictionary, title: String, color: Color, stacks: int, progress: float) -> void:
	var h := _row_h()
	var pips := Tuning.MAX_STACKS
	_draw_row_text(y, h, cols, title, "%d/%d" % [stacks, pips], stacks > 0)
	var pip_gap := 2.0
	var rect := _bar_rect(y, h, cols)
	var pip_y := y if compact else y + 2.0
	var pip_h := h if compact else h - 4.0
	var pip_w := floorf((rect.size.x - pip_gap * float(pips - 1)) / float(pips))
	var total := pip_w * float(pips) + pip_gap * float(pips - 1)
	var start := rect.position.x + floorf((rect.size.x - total) * 0.5)
	for i in pips:
		var pip := Rect2(start + float(i) * (pip_w + pip_gap), pip_y, pip_w, pip_h)
		var inner := _draw_track(pip, true)
		if i < stacks:
			draw_rect(inner, color)
		elif i == stacks and progress > 0.0:
			# The pip being earned: partial fill = impact pool / threshold. Cleared at the unit's turn start.
			draw_rect(Rect2(inner.position, Vector2(floorf(inner.size.x * clampf(progress, 0.0, 1.0)), inner.size.y)), color)

## Title on the left, numbers on the right, both on the row's baseline. Compact rows have no text.
func _draw_row_text(y: float, h: float, cols: Dictionary, title: String, text: String, live: bool) -> void:
	if compact:
		return
	var font := get_theme_default_font()
	var baseline := y + floorf((h + font.get_ascent(FONT) - font.get_descent(FONT)) * 0.5)
	var color := Palette.INK if live else Palette.INK_LIGHT
	draw_string(font, Vector2(0.0, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, color)
	var nums_w: float = cols["nums"]
	draw_string(font, Vector2(size.x - nums_w, baseline), text, HORIZONTAL_ALIGNMENT_RIGHT, nums_w - 4.0, FONT, color)
