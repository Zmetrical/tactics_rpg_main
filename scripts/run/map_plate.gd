extends PanelContainer
## The map's name plate: a framed label at the top centre, like the battle's "BIOME: PLAINS" plate.
## frame_box.gd is a StyleBox (it cannot sit in the scene tree), so this small PanelContainer wraps it:
## the flat 1-bit ink border with its inner ring, the HUD theme's font, no shadow. Display only.
##
## run_map_view.gd adds it to its UI layer, calls place(y) under the top bar and set_text() whenever the
## hovered / reachable room changes. An empty text hides it.
## A second instance is the region plate: pin_left() puts it in the top left corner and show_timed() shows a name
## for a few seconds, then fades it out. pin_corner() pins a plate to any screen corner (the seed plate, the compass),
## make_dial() turns a plate into a framed picture that set_dial_angle() rotates (the compass).

const FrameBox = preload("res://ui/hud/frame_box.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const HudTheme: Theme = preload("res://ui/theme/tactics_theme.tres")

const MARGIN_X := 16.0
const MARGIN_Y := 8.0

var _label: Label
var _fade: Tween
var _dial: TextureRect

func _init() -> void:
	theme = HudTheme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := FrameBox.new()
	box.face = Palette.PANEL
	box.edge = Palette.INK
	box.edge_w = 2
	box.ring = true
	box.ring_color = Palette.INK
	box.set_content_margin(SIDE_LEFT, MARGIN_X)
	box.set_content_margin(SIDE_RIGHT, MARGIN_X)
	box.set_content_margin(SIDE_TOP, MARGIN_Y)
	box.set_content_margin(SIDE_BOTTOM, MARGIN_Y)
	add_theme_stylebox_override("panel", box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

## Shows `text` (already upper case); "" hides the plate.
func set_text(text: String) -> void:
	_stop_fade()
	_label.text = text
	visible = text != ""
	reset_size()

## Pins the plate to the top left corner, `x` pixels from the left edge (instead of the top centre). Call once,
## before place().
func pin_left(x: float) -> void:
	pin_corner(Control.PRESET_TOP_LEFT, Vector2(x, 0.0))

## Pins the plate to a screen corner: `preset` is PRESET_TOP_LEFT, PRESET_TOP_RIGHT, PRESET_BOTTOM_LEFT or
## PRESET_BOTTOM_RIGHT, `margin` the pixels to keep from both edges. The plate grows away from that corner.
## place(y) afterwards moves a top plate down to y.
func pin_corner(preset: Control.LayoutPreset, margin: Vector2) -> void:
	var at_right := preset == Control.PRESET_TOP_RIGHT or preset == Control.PRESET_BOTTOM_RIGHT
	var at_bottom := preset == Control.PRESET_BOTTOM_LEFT or preset == Control.PRESET_BOTTOM_RIGHT
	set_anchors_preset(preset)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN if at_right else Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN if at_bottom else Control.GROW_DIRECTION_END
	offset_left = -margin.x if at_right else margin.x
	offset_right = offset_left
	offset_top = -margin.y if at_bottom else margin.y
	offset_bottom = offset_top
	reset_size()

## Turns the plate into a dial: `tex` (nearest filtered, `px` x `px` pixels) replaces the label inside the same frame.
func make_dial(tex: Texture2D, px: float) -> void:
	_label.visible = false
	_dial = TextureRect.new()
	_dial.texture = tex
	_dial.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dial.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dial.stretch_mode = TextureRect.STRETCH_SCALE
	_dial.custom_minimum_size = Vector2(px, px)
	_dial.pivot_offset = Vector2(px, px) * 0.5
	_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dial)
	visible = true
	reset_size()

## Turns the dial picture clockwise by `degrees` around its centre.
func set_dial_angle(degrees: float) -> void:
	if _dial != null:
		_dial.rotation_degrees = degrees

## Shows `text` at full strength for `hold` seconds, then fades it out over `fade` seconds and hides it.
## A new call restarts the timer; "" hides the plate at once.
func show_timed(text: String, hold: float = 2.0, fade: float = 0.6) -> void:
	set_text(text)
	if text == "":
		return
	_fade = create_tween()
	_fade.tween_interval(hold)
	_fade.tween_property(self, "modulate:a", 0.0, fade)
	_fade.tween_callback(hide)

func _stop_fade() -> void:
	if _fade != null:
		_fade.kill()
		_fade = null
	modulate.a = 1.0

## Top edge of the plate, in UI pixels.
func place(y: float) -> void:
	offset_top = y
	offset_bottom = y
	reset_size()
