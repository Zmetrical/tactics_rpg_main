extends Control
## Fire Emblem-style unit panel: diamond portrait, name, team tag, AP / MV, and the three vitals
## bars (HP, Magic Barrier, Armor) with the Fracture / Shred rings. The SAME panel is used for the
## current unit, the hovered unit and the attack target, player or enemy. Faked in 2D, no 3D nodes:
##   1. the flat panel lives in a SubViewport (Viewport/Flat) and is drawn normally by Controls;
##   2. Screen shows that viewport through shaders/pseudo3d_panel.gdshader, which tapers and
##      lifts one edge (pixel for pixel, no filtering);
##   3. every frame the panel is placed beside the tracked unit's sprite on screen, using the
##      stage camera. Right of the sprite for the current unit (left for hover / target); near a screen edge it stays on its side, against the edge, and moves above the sprite if it would cover it.
## Display only: it ignores the mouse. Data comes in as UnitView dictionaries.

const Palette = preload("res://ui/theme/gbc_palette.gd")
const DiamondPortrait = preload("res://ui/hud/diamond_portrait.gd")
const StatBar = preload("res://ui/hud/stat_bar.gd")
const CircleMeter = preload("res://ui/hud/circle_meter.gd")

enum PanelSide { LEFT, RIGHT }
enum SideMode { FIXED, MAP_CENTER, OPPOSITE }

const FLAT_W := 320
## Header (72) + three bar rows + padding.
const H_BASE := 208
## Pixels the far edge rises (also the quad's headroom). Must match the shader's `lift`.
const LIFT := 16
## Gap between the sprite's edge and the panel, and the keep-clear margin at the screen edge.
const GAP := 10
const MARGIN := 8
const SIDE_HYSTERESIS := 24.0   # pixels; stops the panel flipping back and forth while the camera turns

@export var preferred_side: PanelSide = PanelSide.LEFT
## FIXED: always preferred_side.
## MAP_CENTER: side follows where the map centre is on screen, so it changes as the camera rotates.
## OPPOSITE: always the side the `opposite_of` panel is NOT on.
@export var side_mode: SideMode = SideMode.FIXED
## MAP_CENTER only. true = the panel sits on the side facing the map centre.
## false = on the outer side, over the empty space around the map, so it covers fewer tiles.
@export var toward_center := false
## true = never hop to the other side of the sprite when the preferred side is off screen (that
## is what dropped the panel into the middle of the map). The panel stays against the screen edge
## and, if that would cover the sprite, moves above it (or below when there is no room above).
@export var stay_on_side := true
## true = the parent places the panel (a container or a fixed position), it never tracks a unit.
## show_panel() just makes it visible, and the card is drawn flat (no tilt, no headroom). The battle leaves this false.
@export var docked := false
@export_range(0.0, 0.5) var taper := 0.16
## Pixels kept clear under the panel, on top of any footer (which is already part of the panel's size).
@export var extra_below := 0

@onready var _screen: TextureRect = %Screen
@onready var _viewport: SubViewport = %Viewport
@onready var _flat: PanelContainer = %Flat
@onready var _portrait: DiamondPortrait = %Portrait
@onready var _name: Label = %NameLabel
@onready var _team: Label = %TeamTag
@onready var _stats: Label = %Stats
@onready var _hp: StatBar = %HpBar
@onready var _barrier: StatBar = %BarrierBar
@onready var _armor: StatBar = %ArmorBar
@onready var _fracture: CircleMeter = %FractureMeter
@onready var _shred: CircleMeter = %ShredMeter

var _camera: Camera3D = null
var _anchor := Callable()
var _half_world := 1.0
var _active := false
var _height := H_BASE   # the card's own height
var _footer_h := 0   # transparent strip under the card, inside the same flat viewport (see set_footer)
var _far_is_right := true
var _side: PanelSide = PanelSide.LEFT
var _material: ShaderMaterial = null
var _side_applied := false
var map_center := Callable()   # () -> Vector3, world position of the map centre
var opposite_of: Control = null   # a UnitPanel3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = (_screen.material as ShaderMaterial).duplicate() as ShaderMaterial
	_screen.material = _material
	_screen.texture = _viewport.get_texture()
	_armor.fill_color = Palette.INK_LIGHT
	_shred.fill_color = Palette.INK_LIGHT
	_apply_height(H_BASE)
	visible = false

## Follow a point in the world (the unit's chest). `half_width_world` is half the sprite's width in
## world units; the panel keeps that far (plus GAP pixels) from the sprite.
func track(camera: Camera3D, anchor: Callable, half_width_world: float) -> void:
	_camera = camera
	_anchor = anchor
	_half_world = half_width_world

func show_panel() -> void:
	_active = true
	if docked:
		visible = true
		return
	_place()

func hide_panel() -> void:
	_active = false
	visible = false

func is_active() -> bool:
	return _active

func current_side() -> PanelSide:
	return _side

## `same_unit` = the same unit as the last view (bars slide instead of snapping).
func set_view(view: Dictionary, same_unit: bool = false) -> void:
	_portrait.set_view(view)
	_name.text = view["name"]
	_team.text = view["team"]
	_team.add_theme_color_override("font_color", view["accent"])
	if float(view["max_ap"]) > 0.0:
		_stats.text = "AP %s/%s  MV %d/%d" % [_num(view["ap"]), _num(view["max_ap"]), view["move"], view["max_move"]]
		if int(view.get("skills_max", 0)) > 0:
			_stats.text += "  SK %d/%d" % [view["skills_used"], view["skills_max"]]
	else:
		_stats.text = ""
	var accent: Color = view["accent"]
	_barrier.fill_color = accent
	_fracture.fill_color = accent
	var snap := not same_unit
	_hp.set_values(view["hp"], view["max_hp"], snap)
	_barrier.set_values(view["barrier"], view["max_barrier"], snap)
	_armor.set_values(view["armor"], view["max_armor"], snap)
	_fracture.set_value(view["fracture"], view["max_stacks"])
	_shred.set_value(view["shred"], view["max_stacks"])

## Marks what an attack would take off the bars (UnitView.forecast(): to_hp / to_barrier / to_armor). {} clears.
func set_preview(forecast: Dictionary) -> void:
	_hp.set_preview(int(forecast.get("to_hp", 0)))
	_barrier.set_preview(int(forecast.get("to_barrier", 0)))
	_armor.set_preview(int(forecast.get("to_armor", 0)))

## Hangs `node` under the card INSIDE the flat viewport, so the tilt shader bends it together with the card
## (the target panel's CONFIRM / CANCEL). `height` is the strip it needs under the card; the card keeps its own
## height. Controls in there cannot take the mouse: use to_flat() to find out what a screen point is over.
## The caller positions the node (viewport coordinates: y = H_BASE is the top of the strip).
func set_footer(node: Control, height: int) -> void:
	_footer_h = height
	node.reparent(_viewport, false)
	node.theme = _flat.theme   # the viewport breaks theme inheritance
	_apply_height(H_BASE)

## The shader's own math, run backwards: the point of the flat viewport that is drawn at `quad_pos` (relative to
## this panel's top-left). Vector2(-1, -1) when nothing of the card is drawn there.
func to_flat(quad_pos: Vector2) -> Vector2:
	var total := float(_height + _footer_h)
	var o := Vector2(floorf(quad_pos.x), floorf(quad_pos.y)) + Vector2(0.5, 0.5)
	if o.x < 0.0 or o.x >= float(FLAT_W):
		return Vector2(-1.0, -1.0)
	var t := o.x / float(FLAT_W)
	if not _far_is_right:
		t = 1.0 - t
	var k := 1.0 - _taper_now() * t
	var center_y := _lift_px() + total * 0.5 - _lift_px() * t
	var sy := total * 0.5 + (o.y - center_y) / k
	if sy < 0.0 or sy >= total:
		return Vector2(-1.0, -1.0)
	return Vector2(floorf(o.x), floorf(sy))

## Screen rectangle of the panel quad (panel plus the headroom above it).
func screen_rect() -> Rect2:
	return Rect2(position, size)

var _placed_world := Vector3.INF
var _placed_cam := Transform3D()
var _placed_vp := Vector2.ZERO

func _process(_delta: float) -> void:
	if not _active or docked:
		return
	# Re-place only when the anchor, the camera or the window changed: a still camera costs nothing.
	if _camera != null and _anchor.is_valid():
		var world: Vector3 = _anchor.call()
		var cam := _camera.global_transform
		var vp := get_viewport_rect().size
		if world == _placed_world and cam == _placed_cam and vp == _placed_vp:
			return
		_placed_world = world
		_placed_cam = cam
		_placed_vp = vp
	_place()

func _apply_height(h: int) -> void:
	_height = h
	var total := h + _footer_h
	_viewport.size = Vector2i(FLAT_W, total)
	_flat.offset_bottom = -float(_footer_h)   # the card stays h tall; the footer strip below it stays transparent
	size = Vector2(FLAT_W, total + _lift_px())
	_screen.size = size
	_material.set_shader_parameter("panel_size", Vector2(FLAT_W, total))
	_material.set_shader_parameter("lift", _lift_px())
	_material.set_shader_parameter("taper", _taper_now())

## Docked panels are flat: no rising edge, no taper.
func _lift_px() -> float:
	return 0.0 if docked else float(LIFT)

func _taper_now() -> float:
	return 0.0 if docked else taper

func _place() -> void:
	if _camera == null or not _anchor.is_valid():
		return
	var world: Vector3 = _anchor.call()
	if _camera.is_position_behind(world):
		visible = false
		return
	visible = true
	var p := _camera.unproject_position(world)
	var half := absf((_camera.unproject_position(world + _camera.global_transform.basis.x * _half_world) - p).x)
	var vp := get_viewport_rect().size
	var left_x := p.x - half - GAP - FLAT_W
	var right_x := p.x + half + GAP
	var side := _choose_side(p)
	if not stay_on_side:
		if side == PanelSide.LEFT and left_x < MARGIN:
			side = PanelSide.RIGHT
		elif side == PanelSide.RIGHT and right_x + FLAT_W > vp.x - MARGIN:
			side = PanelSide.LEFT
	var x := left_x if side == PanelSide.LEFT else right_x
	var y := p.y - (LIFT + _height * 0.5)
	x = clampf(x, MARGIN, maxf(vp.x - FLAT_W - MARGIN, MARGIN))
	# Pushed against the screen edge it may now sit on the sprite: lift it clear (the sprite is square,
	# so its half height is about its half width).
	if x < p.x + half and x + FLAT_W > p.x - half:
		var above := p.y - half - GAP - size.y
		y = above if above >= MARGIN else p.y + half + GAP
	y = clampf(y, MARGIN, maxf(vp.y - size.y - extra_below - MARGIN, MARGIN))
	position = Vector2(roundf(x), roundf(y))
	if side != _side or not _side_applied:
		_side = side
		_side_applied = true
		# The edge next to the sprite is the one that recedes.
		_far_is_right = side == PanelSide.LEFT
		_material.set_shader_parameter("far_is_right", _far_is_right)

func _choose_side(p: Vector2) -> PanelSide:
	match side_mode:
		SideMode.MAP_CENTER:
			if map_center.is_valid():
				var dx: float = _camera.unproject_position(map_center.call()).x - p.x
				if absf(dx) > SIDE_HYSTERESIS or not _side_applied:
					var centre_is_right := dx > 0.0
					if toward_center:
						return PanelSide.RIGHT if centre_is_right else PanelSide.LEFT
					return PanelSide.LEFT if centre_is_right else PanelSide.RIGHT
				return _side   # near the centre line: keep the current side
		SideMode.OPPOSITE:
			if opposite_of != null:
				return PanelSide.LEFT if opposite_of.current_side() == PanelSide.RIGHT else PanelSide.RIGHT
	return preferred_side

static func _num(v: Variant) -> String:
	return String.num(float(v), 1).trim_suffix(".0")
