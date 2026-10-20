extends CanvasLayer
## PS1 render look for the 3D view: low internal resolution, hard pixel edges (no anti-aliasing),
## 15-bit colour with ordered dithering. See shaders/ps1_post.gdshader for what each knob does.
##
## World pass: layer 0, above the 3D world and the tilt-shift (layer -1), below the HUD (layer 1+).
## HUD pass: a second instance on a high layer, so it covers the HUD and toast too.
## Order matters: the blur has to happen BEFORE the pixelation, otherwise it would smear the chunky
## pixels back together.

const SHADER := preload("res://shaders/ps1_post.gdshader")

## Vertical resolution of the look. 270 = 1080p / 4, which is about one screen pixel block per
## terrain texel at the default zoom. Lower = chunkier (240 is the PS1's own).
@export_range(120.0, 540.0, 1.0) var virtual_height := 270.0:
	set(value):
		virtual_height = value
		_push("virtual_height", value)
## Steps per colour channel. 32 = PS1 15-bit colour. 16 or 8 for a harsher look.
@export_range(2.0, 64.0, 1.0) var color_levels := 32.0:
	set(value):
		color_levels = value
		_push("color_levels", value)
## 0 = plain posterize, 1 = PS1 amount of dither, 2 = rough.
@export_range(0.0, 2.0, 0.05) var dither_strength := 0.55:
	set(value):
		dither_strength = value
		_push("dither_strength", value)
## Colour grade (applied before the dither). Raise brightness if it looks dark.
@export_range(0.5, 2.0, 0.01) var brightness := 1.15:
	set(value):
		brightness = value
		_push("brightness", value)
@export_range(0.5, 2.0, 0.01) var contrast := 1.05:
	set(value):
		contrast = value
		_push("contrast", value)
@export_range(0.0, 2.0, 0.01) var saturation := 1.2:
	set(value):
		saturation = value
		_push("saturation", value)
## Turns the whole pass off (the F2 key in the battle does this) for an A/B look.
@export var enabled := true:
	set(value):
		enabled = value
		visible = value

var _material: ShaderMaterial

func _init() -> void:
	name = "PS1Post"
	layer = 0

func _ready() -> void:
	var rect := ColorRect.new()
	rect.name = "Pass"
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	rect.material = _material
	_push("virtual_height", virtual_height)
	_push("color_levels", color_levels)
	_push("dither_strength", dither_strength)
	_push("brightness", brightness)
	_push("contrast", contrast)
	_push("saturation", saturation)
	visible = enabled

func _push(param: String, value: float) -> void:
	if _material != null:
		_material.set_shader_parameter(param, value)
