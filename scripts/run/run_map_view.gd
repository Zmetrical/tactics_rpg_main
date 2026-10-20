extends Node3D
## Renders RunState.map as the flat overworld map on the block terrain: roads are clean one-cell strips
## (merged boxes built in overworld_decor.gd), rooms are plain coloured square slabs with a type label above
## them, the party is a small blue cube. No run rules here: reachable nodes come from RunMap links, state
## changes go through RunState / RunFlow.
## World coordinates are the overworld layout's: layout x -> X, layout y -> Z, height -> Y.
const MapGenerator = preload("res://scripts/run/map_generator.gd")
const RunMap = preload("res://scripts/run/run_map.gd")
const HudStyle = preload("res://ui/hud/hud_style.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const HudTheme: Theme = preload("res://ui/theme/tactics_theme.tres")
const MapTopBar = preload("res://scripts/run/map_top_bar.gd")
const OverworldLayoutScript = preload("res://scripts/run/overworld_layout.gd")
const OverworldTerrain = preload("res://scripts/run/overworld_terrain.gd")
const OverworldDecor = preload("res://scripts/run/overworld_decor.gd")
const OverworldStyle = preload("res://data/run/overworld_style.gd")
const Stage3D = preload("res://scripts/battle/stage_3d.gd")   # read-only: the battle's camera and PS1 constants
const Ps1Post = preload("res://scripts/battle/ps1_post.gd")
const MapPlate = preload("res://scripts/run/map_plate.gd")
const MapPixels = preload("res://data/run/map_pixels.gd")
const MapFurniture = preload("res://scripts/run/map_furniture.gd")
const CampaignText = preload("res://data/run/campaign_text.gd")
const CARD_SCENE: PackedScene = preload("res://scenes/run/encounter_card.tscn")
## Id of the start pseudo-room.
const START_ID := OverworldLayoutScript.START_ID
# Camera: the battle's (Stage3D.CAM_FOV / CAM_PITCH / CAM_START_YAW, Q/E 90 degree snaps, wheel zoom 0.9).
# The map is laid out along X, so its first view is one snap (-90) away from the battle's start yaw: layers
# run up-right on screen (start bottom-left, boss top-right). Q/E still turn it in the same steps.
const START_YAW_OFFSET := -90.0
const CAMERA_MARGIN := 5.0       # world units kept free around the framed markers
const PAN_MARGIN := 3.0          # the camera centre may leave the marker bounds by this much
const PAN_PITCH_SCALE := 0.643   # sin(40 degrees): a screen pixel up is 1/this ground units
const HOME_TIME := 0.25          # Space glides back to the framed view in this many seconds
const FOCUS_TIME := 0.4          # focus_target() (map open, F) glides to the current + reachable rooms in this many seconds
const FOCUS_MARGIN := 3.0        # world units kept free around the framed rooms (tighter than CAMERA_MARGIN)
const PAN_KEY_SPEED := 0.6       # WASD pan: ground units per second per unit of camera distance (scales with zoom)
const PAN_KEY_FAST := 2.0        # Shift held: WASD speed multiplier
## Sun like the battle's (fixed in the world, no shadows: the map is far bigger than the shadow range).
const SUN_COLOR := Color(1.0, 0.92, 0.78)
const SUN_ENERGY := 1.25
const SUN_ROTATION := Vector3(-50.0, -35.0, 0.0)
## Party token: a small cube whose centre rides this high (its bottom clears the slab and the road strips).
const TOKEN_SIZE := 0.5
const TOKEN_LIFT := 0.5
const TOKEN_COLOR := Color("#3a5fd0")
const TOKEN_SPEED := 12.0   # world units per second
## Room slabs: flat squares of the room's footprint, this high, with a darker side.
const SLAB_HEIGHT := 0.25
const SIDE_DARKEN := 0.35
## Top colours by RunMap.NodeType: BATTLE, ELITE, CAMPFIRE, SHOP, BOSS; and the start platform.
const TYPE_TOPS: Array[Color] = [
	Color("#a05050"), Color("#7b5ea7"), Color("#b87333"), Color("#4a8a5a"), Color("#b09a4a"),
]
const START_TOP := Color("#9aa88a")
const BATTLE_REACH_TOP := Color("#e07a7a")   # the other types blink towards base.lightened(REACH_LIGHTEN)
const REACH_LIGHTEN := 0.25
const VISITED_DARKEN := 0.2
const BLINK_SPEED := 2.2                     # radians per second: a slow blink
## Road strips (built by OverworldDecor.build); only the top colour changes with the state.
const ROAD_REACH_TOP := Color("#f5e6a8")
const ROAD_VISITED_TOP := Color("#a8a493")
## Room labels: the HUD font, no outline, a little above the slab.
const TYPE_NAMES: Array[String] = ["Battle", "Elite", "Campfire", "Shop", "Boss"]
const LABEL_FONT_SIZE := 16
const LABEL_PIXEL_SIZE := 0.03
const LABEL_LIFT := 1.4
## Picking box: invisible, the room footprint this high.
const PICK_HEIGHT := 1.0
## The name plate hangs this many pixels under the top bar.
const PLATE_GAP := 8.0
## The region plate sits this many pixels from the left edge, shows for REGION_HOLD seconds, then fades over REGION_FADE.
const REGION_PLATE_X := 16.0
## Seed plate (top right, same row as the other plates) and compass plate (bottom left): pixels from the screen edge.
const SEED_PLATE_X := 16.0
const COMPASS_MARGIN := Vector2(16.0, 16.0)
const COMPASS_PX := 64.0        # the 16 x 16 sprite drawn at 4x
## True map north as (x, z) on the ground: layers run west to east along +X (the boss end is east), so north is -Z.
const MAP_NORTH := Vector2(0.0, -1.0)
const REGION_HOLD := 2.0
const REGION_FADE := 0.6
## _hover_id when the cursor is over no room (START_ID is -1).
const NO_HOVER := -2
## Debug, survives scene reloads: node clicks return straight to the map instead of entering the node.
static var _skip_enabled := false
## Ids walked in the current run. Reset when RunState.map is a different map.
static var _visited: Array[int] = []
static var _visited_map: RunMap = null
## Yaw the player left the camera at, survives scene reloads (battle -> map) so the view doesn't spin back to the start yaw.
static var _last_yaw := NAN
@onready var camera: Camera3D = $CameraRig/Camera
@onready var _rig: Node3D = $CameraRig
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var top_bar: MapTopBar = $UI/TopBar
@onready var skip_button: Button = $UI/TopBar/Row/SkipButton
var map: RunMap
var layout: OverworldLayoutScript.OverworldLayout
var token: MeshInstance3D
var _points: Array[Vector3] = []
var _height_fn := Callable()
var _roads := {}        # Vector2i(from_id, to_id) -> Array[Vector2i] corridor cells, door to door
var _road_tops := {}    # Vector2i -> StandardMaterial3D (the top surface of that road's mesh)
var plate: MapPlate
var region_plate: MapPlate
var seed_plate: MapPlate
var compass_plate: MapPlate
var _terrain: OverworldTerrain.Terrain
var _card: Control          # the encounter card, open while the token waits at a room
var _walk_start := Vector3.ZERO   # where the token stood before the current walk (TURN BACK returns here)
var _hover_id := NO_HOVER
var _token_target := NO_HOVER
var _plate_text := ""
var _token_id := START_ID
# Camera state (see "camera" below).
var yaw_degrees := Stage3D.CAM_START_YAW + START_YAW_OFFSET:
	set(value):
		yaw_degrees = value
		if _rig != null:
			_rig.rotation_degrees.y = value
var yaw_target := Stage3D.CAM_START_YAW + START_YAW_OFFSET
var _yaw_tween: Tween
var _home_tween: Tween
var _distance := 60.0       # current camera distance from the rig
var _fit_distance := 60.0   # distance that frames every marker (Space returns here)
var _rig_home := Vector3.ZERO
var _pan_min := Vector2.ZERO
var _pan_max := Vector2.ZERO
var _panning := false
var _moved := false         # the player panned or zoomed: a resize must not undo it
var _focused := false       # the last camera command was focus_target(): a resize re-frames that, not the whole slab
## id -> {top: StandardMaterial3D, base: Color, lit: Color}; reachable rooms only get blinked in _process.
var _marks := {}
var _reachable := {}    # id -> true
var _cur_from := START_ID
var _moving := false
var _time := 0.0
func _ready() -> void:
	if not RunState.active:
		RunState.new_run(randi())  # scene launched on its own
	if RunState.map == null:
		RunState.map = MapGenerator.generate(RunState.rng)
	map = RunState.map
	if map != _visited_map:
		_visited.clear()
		_visited_map = map
		_last_yaw = NAN   # a new run starts at the start yaw
	if not is_nan(_last_yaw):
		yaw_target = _last_yaw
		yaw_degrees = _last_yaw
	layout = OverworldLayoutScript.build(map, RunState.seed)
	for road in layout.roads:
		_roads[Vector2i(road["from_id"], road["to_id"])] = road["cells"]
	_build_look()
	# Terrain and decoration are always shown in full.
	var terrain := OverworldTerrain.build(layout, RunState.seed)
	add_child(terrain)
	_terrain = terrain
	if OverworldVoxel.PARITY_VOXEL_TERRAIN:
		_mount_voxel_terrain(terrain)
	# The camera frames the land, walls included: the corners of the bounding box of the land cells (not of the grid).
	# Default framing, Space (fit whole slab) and the WASD / pan clamps all read _points, so they follow it.
	var land_rect := _land_bounds(terrain)
	var slab_min := Vector3(land_rect.position.x, float((terrain.get_meta("min") as Vector3).y), land_rect.position.y)
	var slab_max := Vector3(land_rect.end.x, float((terrain.get_meta("max") as Vector3).y), land_rect.end.y)
	print("camera: land bounding box x[%.1f .. %.1f] z[%.1f .. %.1f], %d x %d cells (grid %d x %d)" % [
			slab_min.x, slab_max.x, slab_min.z, slab_max.z, roundi(land_rect.size.x), roundi(land_rect.size.y), terrain.nx, terrain.nz])
	for cx in [slab_min.x, slab_max.x]:
		for cy in [slab_min.y, slab_max.y]:
			for cz in [slab_min.z, slab_max.z]:
				_add_point(Vector3(cx, cy, cz))
	_height_fn = OverworldDecor.height_fn_from_terrain(terrain)
	var decor := OverworldDecor.build(layout, _height_fn, RunState.seed)
	add_child(decor)
	_collect_roads(decor)
	var cur = RunState.current_node
	var from_id: int = START_ID if cur == null else int(cur)
	_cur_from = from_id
	var options: Array = map.layers[0] if cur == null else map.nodes[int(cur)].next_ids
	for id in options:
		# Only a node whose road exists can be chosen.
		if _has_road(from_id, id):
			_reachable[id] = true
	# Mist: drifting clouds far from the reachable rooms (see map_furniture.gd).
	var furniture := MapFurniture.new()
	furniture.name = "MapFurniture"
	add_child(furniture)
	furniture.build_mist(layout, _reachable.keys(), slab_min, slab_max, _height_fn, RunState.seed, Callable(terrain, "is_land"))
	for n in map.nodes:
		_build_marker(n.id, n.type)
	_build_marker(START_ID, -1)
	_build_token(cur)
	_refresh_states()
	_fit_camera(true)
	get_viewport().size_changed.connect(_fit_camera)
	top_bar.add_theme_stylebox_override("panel", HudStyle.frame())
	top_bar.resized.connect(_fit_camera)   # the bar is tall now and only gets its size after layout
	plate = MapPlate.new()
	top_bar.get_parent().add_child(plate)
	region_plate = MapPlate.new()
	region_plate.pin_left(REGION_PLATE_X)
	top_bar.get_parent().add_child(region_plate)
	seed_plate = MapPlate.new()
	seed_plate.pin_corner(Control.PRESET_TOP_RIGHT, Vector2(SEED_PLATE_X, 0.0))
	top_bar.get_parent().add_child(seed_plate)
	seed_plate.set_text("SEED %d" % RunState.seed)
	compass_plate = MapPlate.new()
	compass_plate.pin_corner(Control.PRESET_BOTTOM_LEFT, COMPASS_MARGIN)
	top_bar.get_parent().add_child(compass_plate)
	compass_plate.make_dial(MapPixels.sprite("compass"), COMPASS_PX)
	top_bar.resized.connect(_place_plate)
	_place_plate()
	top_bar.refresh()
	skip_button.pressed.connect(_on_skip_pressed)
	_update_skip_text()
	focus_target(false)   # map open (the scene reloads after every arrival): start already framed, no glide from the whole slab
func _process(delta: float) -> void:
	_time += delta
	_key_pan(delta)
	# Reachable rooms blink slowly between their normal and their lighter top.
	var k := 0.5 + 0.5 * sin(_time * BLINK_SPEED)
	for id in _reachable:
		var m: Dictionary = _marks[id]
		(m["top"] as StandardMaterial3D).albedo_color = (m["base"] as Color).lerp(m["lit"], k)
	_poll_hover()
	_update_plate()
	compass_plate.set_dial_angle(_compass_degrees())
# --- world helpers -----------------------------------------------------------------------
func _ground(p: Vector2) -> float:
	return maxf(float(_height_fn.call(p)), 0.0) if _height_fn.is_valid() else 0.0
## Centre of a room's slab at ground level (the footprint centre is half-way between cells for even sides).
func _room_center(id: int) -> Vector3:
	var p: Vector2 = layout.node_pos[id]
	return Vector3(p.x, _ground(p), p.y)
## Outer edge, in world x / z, of the bounding box of the land cells' blocks (Rect2: position = min corner, size in cells).
## Falls back to the whole grid when the terrain has no land.
static func _land_bounds(t: OverworldTerrain.Terrain) -> Rect2:
	var lo := Vector2i(t.nx, t.nz)
	var hi := Vector2i(-1, -1)
	for iz in t.nz:
		for ix in t.nx:
			if t.land[iz * t.nx + ix] == 1:
				lo = Vector2i(mini(lo.x, ix), mini(lo.y, iz))
				hi = Vector2i(maxi(hi.x, ix), maxi(hi.y, iz))
	if hi.x < 0:
		return Rect2(float(t.x0) - 0.5, float(t.z0) - 0.5, float(t.nx), float(t.nz))
	return Rect2(Vector2(t.x0 + lo.x, t.z0 + lo.y) - Vector2(0.5, 0.5), Vector2(hi - lo + Vector2i.ONE))
## Step 1c: swaps the terrain's Slab mesh for VoxelWorld + chunk mesher (same cells, heights, colours). Terrain data and meta stay.
func _mount_voxel_terrain(terrain: OverworldTerrain.Terrain) -> void:
	var t0 := Time.get_ticks_usec()
	var vt := OverworldVoxelTerrain.build(terrain)
	var view := VoxelChunkView.new()
	view.name = "VoxelSlab"
	view.position = vt.origin
	view.mesher.cull_floor = true
	view.mesher.face_color_fn = vt.face_color
	terrain.add_child(view)
	view.setup(vt.world)
	var slab := terrain.get_node_or_null("Slab")
	if slab != null:
		terrain.remove_child(slab)
		slab.queue_free()
	print("voxel terrain: %d x %d x %d voxels, fill %.1f ms, total %.1f ms, hash %s" % [
			vt.world.size_x, vt.world.max_y, vt.world.size_z, vt.build_ms, (Time.get_ticks_usec() - t0) / 1000.0, vt.world.hash()])
func _add_point(p: Vector3) -> void:
	_points.append(p)
# --- building ----------------------------------------------------------------------------
## Remembers the top material of every road mesh (surface 0) so _refresh_roads can recolour it.
func _collect_roads(decor: Node) -> void:
	var holder := decor.get_node_or_null("Roads")
	for key in _roads:
		var mi: MeshInstance3D = null
		if holder != null:
			mi = holder.get_node_or_null("road_%d_%d" % [key.x, key.y]) as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			push_warning("run_map_view: no strip for road %d -> %d" % [key.x, key.y])
			continue
		_road_tops[key] = mi.mesh.surface_get_material(0)
func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.disable_receive_shadows = true
	return m
## Resting top colour of a room by state: visited rooms (not reachable ones) are darker.
func _state_top(id: int, base: Color) -> Color:
	if _visited.has(id) and not _reachable.has(id):
		return base.darkened(VISITED_DARKEN)
	return base
## Slab + label (+ invisible pick box) for a room; type -1 is the start platform (no pick box).
func _build_marker(id: int, type: int) -> void:
	var is_start := type < 0
	var rect: Rect2i = layout.rooms[id]
	var size := Vector2(rect.size)
	var base_col: Color = START_TOP if is_start else TYPE_TOPS[type]
	var lit: Color = BATTLE_REACH_TOP if type == RunMap.NodeType.BATTLE else base_col.lightened(REACH_LIGHTEN)
	var top_col := _state_top(id, base_col)
	var root := Node3D.new()
	root.name = "Marker_%d" % id
	root.position = _room_center(id)
	add_child(root)
	var b := OverworldDecor.new_boxes()
	OverworldDecor.add_box(b, Vector3(-size.x * 0.5, 0.0, -size.y * 0.5), Vector3(size.x * 0.5, SLAB_HEIGHT, size.y * 0.5))
	var top_mat := _flat_material(top_col)
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	slab.mesh = OverworldDecor.commit_boxes(b, top_mat, _flat_material(top_col.darkened(SIDE_DARKEN)))
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(slab)
	var label := Label3D.new()
	label.name = "Label"
	label.text = "Start" if is_start else TYPE_NAMES[type]
	label.font = HudTheme.default_font
	label.font_size = LABEL_FONT_SIZE
	label.pixel_size = LABEL_PIXEL_SIZE
	label.outline_size = 0
	label.modulate = Palette.INK
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.shaded = false
	label.double_sided = true
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = Vector3(0.0, SLAB_HEIGHT + LABEL_LIFT, 0.0)
	root.add_child(label)
	if not is_start:
		var body := StaticBody3D.new()
		body.set_meta("node_id", id)
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, PICK_HEIGHT, size.y)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.debug_color = Color(0.0, 0.0, 0.0, 0.0)   # never drawn, not even with "Visible Collision Shapes" on
		body.add_child(cs)
		body.position = Vector3(0.0, PICK_HEIGHT * 0.5, 0.0)
		root.add_child(body)
		_marks[id] = {"top": top_mat, "base": top_col, "lit": lit}
	var c := root.position
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_add_point(c + Vector3(corner.x * size.x * 0.5, 0.0, corner.y * size.y * 0.5))
	_add_point(c + Vector3(0.0, SLAB_HEIGHT + LABEL_LIFT + 1.0, 0.0))   # the camera frame keeps room for the label
func _build_token(cur) -> void:
	token = MeshInstance3D.new()
	token.name = "PartyToken"
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * TOKEN_SIZE
	token.mesh = cube
	token.material_override = _flat_material(TOKEN_COLOR)
	token.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(token)
	_token_id = START_ID if cur == null else int(cur)
	token.position = _room_center(_token_id) + Vector3(0.0, TOKEN_LIFT, 0.0)
# --- look: PS1 pass, background, sun ------------------------------------------------------
## The battle's render: PS1 post pass (same height, colour levels and dither as the battle's constants), the
## sea colour as the flat background, the battle's sun and ambient. The UI CanvasLayer sits above the pass.
func _build_look() -> void:
	_rig.rotation_degrees = Vector3(Stage3D.CAM_PITCH, yaw_degrees, 0.0)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = Stage3D.CAM_FOV
	camera.near = 0.5
	var post := Ps1Post.new()
	post.virtual_height = Stage3D.PS1_HEIGHT
	post.color_levels = Stage3D.PS1_COLOR_LEVELS
	post.dither_strength = Stage3D.PS1_DITHER
	add_child(post)
	var sea := OverworldStyle.sea_color()
	var env := world_env.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = sea
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.64, 0.80)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = sea   # fog fades to the sea colour, so the horizon never shows an edge
	env.fog_density = 0.006
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.rotation_degrees = SUN_ROTATION
	sun.shadow_enabled = false
# --- camera: the battle's rig (perspective, pitch, Q/E yaw snaps, wheel zoom) + pan and Space -----------
## Frames every marker (Look 7 auto-framing) below the top bar: the distance at which the farthest marker
## just fits the perspective frustum, and the rig centre that puts the map in the part of the screen the bar
## leaves free. `reset` (or no player camera move yet) also moves the camera there.
func _fit_camera(reset := false) -> void:
	if _points.is_empty() or _rig == null:
		return
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for p in _points:
		mn = mn.min(p)
		mx = mx.max(p)
	_pan_min = Vector2(mn.x, mn.z) - Vector2(PAN_MARGIN, PAN_MARGIN)
	_pan_max = Vector2(mx.x, mx.z) + Vector2(PAN_MARGIN, PAN_MARGIN)
	var f := _frame(_points, CAMERA_MARGIN)
	var d: float = f["distance"]
	_fit_distance = d
	_rig_home = _frame_rig(f, d)
	camera.far = maxf(200.0, d * 3.0)
	if reset or not _moved:
		if _focused and not reset:
			# A resize (the top bar gets its size after layout) keeps the focused view instead of the whole slab.
			_apply_focus("refit", _home_tween != null and _home_tween.is_running())
			return
		_distance = d
		_rig.position = _rig_home
		camera.position = Vector3(0.0, 0.0, _distance)
## Framing maths shared by the whole-slab fit and focus_target(): the distance at which `pts` (with `margin`
## world units around them) just fit the perspective frustum below the top bar, centred on their bounding box.
## Returns {center, distance (unclamped), up, shift}; _frame_rig() turns it into the rig position.
func _frame(pts: Array[Vector3], margin: float) -> Dictionary:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var center := (mn + mx) * 0.5
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var bar := top_bar.size.y + 16.0
	var free := maxf(vp.y - bar, 1.0) / maxf(vp.y, 1.0)   # share of the height below the bar
	var tan_v := tan(deg_to_rad(Stage3D.CAM_FOV) * 0.5)
	var tan_h := tan_v * aspect
	var cam_basis := Basis.from_euler(Vector3(deg_to_rad(Stage3D.CAM_PITCH), deg_to_rad(yaw_target), 0.0), EULER_ORDER_YXZ)
	var d := 0.0
	for p in pts:
		var rel := p - center
		var depth := rel.dot(cam_basis.z)   # towards the camera
		d = maxf(d, (absf(rel.dot(cam_basis.x)) + margin) / tan_h + depth)
		d = maxf(d, (absf(rel.dot(cam_basis.y)) + margin) / (tan_v * free) + depth)
	return {"center": center, "distance": d, "up": cam_basis.y, "shift": tan_v * (1.0 - free)}
## Rig position for a frame() at camera distance `d`: it looks above the centre so the framed points sit below the bar.
func _frame_rig(f: Dictionary, d: float) -> Vector3:
	return (f["center"] as Vector3) + (f["up"] as Vector3) * (d * float(f["shift"]))
## direction: +1 or -1, one 90 degree step like the battle's Q / E.
func snap_yaw(direction: int) -> void:
	yaw_target += 90.0 * direction
	_last_yaw = yaw_target
	if _yaw_tween != null:
		_yaw_tween.kill()
	_yaw_tween = create_tween()
	_yaw_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_yaw_tween.tween_property(self, "yaw_degrees", yaw_target, Stage3D.CAM_YAW_TIME)
	_moved = true
func zoom(factor: float) -> void:
	_distance = clampf(_distance * factor, Stage3D.CAM_MIN_DIST, maxf(Stage3D.CAM_MAX_DIST, _fit_distance * 1.05))
	camera.position.z = _distance
	_moved = true
## Space: glide back to the framed view (position and distance; the yaw stays where Q/E left it).
func recenter() -> void:
	if _home_tween != null:
		_home_tween.kill()
	_focused = false
	_moved = true   # _fit_camera() only updates the home values here; the glide below does the moving
	_fit_camera()
	_home_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_home_tween.tween_property(_rig, "position", _rig_home, HOME_TIME)
	_home_tween.tween_property(camera, "position:z", _fit_distance, HOME_TIME)
	_distance = _fit_distance
	_moved = false
## Glides to the room the token is on plus every reachable room (F, map open). Keeps the yaw, keeps the map under
## the top bar, respects the wheel's zoom limits. With no reachable rooms (run over) it frames the token's room only.
func focus_target(animate := true) -> void:
	_focused = true
	_moved = false
	_apply_focus("focus_target" if animate else "map open", animate)
## The focus frame: {distance (clamped to the zoom limits), rig, box_min, box_max, ids}.
func _focus_frame() -> Dictionary:
	var ids: Array[int] = [_token_id]
	for id in _reachable:
		if id != _token_id:
			ids.append(id)
	var pts: Array[Vector3] = []
	var box_min := Vector3(INF, INF, INF)
	var box_max := Vector3(-INF, -INF, -INF)
	for id in ids:
		var c := _room_center(id)
		var rect: Rect2i = layout.rooms[id]
		var half := Vector2(rect.size) * 0.5
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner := c + Vector3(sx * half.x, 0.0, sz * half.y)
				pts.append(corner)
				box_min = box_min.min(corner)
				box_max = box_max.max(corner)
		pts.append(c + Vector3(0.0, SLAB_HEIGHT + LABEL_LIFT + 1.0, 0.0))   # keep room for the label
	var f := _frame(pts, FOCUS_MARGIN)
	var hi := maxf(Stage3D.CAM_MAX_DIST, _fit_distance * 1.05)   # same limits as zoom()
	var d := clampf(float(f["distance"]), Stage3D.CAM_MIN_DIST, hi)
	return {"distance": d, "rig": _frame_rig(f, d), "box_min": box_min, "box_max": box_max, "ids": ids}
func _apply_focus(tag: String, animate: bool) -> void:
	if _points.is_empty() or _rig == null or layout == null:
		return
	var f := _focus_frame()
	var d: float = f["distance"]
	var rig_pos: Vector3 = f["rig"]
	if _home_tween != null:
		_home_tween.kill()
	_distance = d
	if animate:
		_home_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_home_tween.tween_property(_rig, "position", rig_pos, FOCUS_TIME)
		_home_tween.tween_property(camera, "position:z", d, FOCUS_TIME)
	else:
		_rig.position = rig_pos
		camera.position = Vector3(0.0, 0.0, d)
	var bmin: Vector3 = f["box_min"]
	var bmax: Vector3 = f["box_max"]
	print("%s: rooms %s box x[%.1f .. %.1f] y[%.1f .. %.1f] z[%.1f .. %.1f] zoom %.2f (limits %.1f .. %.1f, whole slab %.2f)" % [
		tag, f["ids"], bmin.x, bmax.x, bmin.y, bmax.y, bmin.z, bmax.z, d,
		Stage3D.CAM_MIN_DIST, maxf(Stage3D.CAM_MAX_DIST, _fit_distance * 1.05), _fit_distance])
## WASD / F are camera keys for the free map only: not while the encounter card, the equipment window or a text field is open.
func _keys_blocked() -> bool:
	if top_bar.is_window_open():
		return true
	if _card != null and _card.is_visible_in_tree():
		return true
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
## Held W / A / S / D: pan on the ground plane relative to the camera yaw (W = away from the camera on screen),
## speed scales with the zoom distance, Shift = double. The rig stays inside the slab bounds plus PAN_MARGIN.
func _key_pan(delta: float) -> void:
	if _rig == null or _keys_blocked():
		return
	var dir := Vector2.ZERO   # x: screen right, y: screen up (away from the camera)
	if Input.is_key_pressed(KEY_W):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_S):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if dir == Vector2.ZERO:
		return
	if _home_tween != null and _home_tween.is_running():
		_home_tween.kill()               # the player takes over from a glide
		_distance = camera.position.z
	var right := _rig.basis.x
	right.y = 0.0
	var fwd := -_rig.basis.z
	fwd.y = 0.0
	dir = dir.normalized()
	var speed := _distance * PAN_KEY_SPEED * (PAN_KEY_FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var pos := _rig.position
	pos += (right.normalized() * dir.x + fwd.normalized() * dir.y) * speed * delta
	pos.x = clampf(pos.x, _pan_min.x, _pan_max.x)
	pos.z = clampf(pos.z, _pan_min.y, _pan_max.y)
	_rig.position = pos
	_moved = true
## Middle / right drag: the ground follows the cursor.
func _pan(relative: Vector2) -> void:
	var vp_h := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var per_px := 2.0 * _distance * tan(deg_to_rad(Stage3D.CAM_FOV) * 0.5) / vp_h
	var right := _rig.basis.x
	right.y = 0.0
	var fwd := -_rig.basis.z
	fwd.y = 0.0
	var pos := _rig.position
	pos -= right.normalized() * relative.x * per_px
	pos += fwd.normalized() * relative.y * per_px / PAN_PITCH_SCALE
	pos.x = clampf(pos.x, _pan_min.x, _pan_max.x)
	pos.z = clampf(pos.z, _pan_min.y, _pan_max.y)
	_rig.position = pos
	_moved = true
## Road and room looks by state; runs when the map is built (the scene reloads after every arrival).
## Reachable rooms blink in _process, visited ones are darker (see _state_top).
func _refresh_states() -> void:
	_refresh_roads()
## Road tops: the road from the current room to a reachable room is light yellow, walked roads are gray, the
## rest keep the stone top. Sides never change. Roads are not clickable.
func _refresh_roads() -> void:
	var traveled := {}
	var prev := START_ID
	for id in _visited:
		traveled[Vector2i(prev, id)] = true
		prev = id
	for key in _road_tops:
		var mat: StandardMaterial3D = _road_tops[key]
		if key.x == _cur_from and _reachable.has(key.y):
			mat.albedo_color = ROAD_REACH_TOP
		elif traveled.has(key):
			mat.albedo_color = ROAD_VISITED_TOP
		else:
			mat.albedo_color = OverworldDecor.ROAD_TOP
## Degrees clockwise from screen-up at which MAP_NORTH appears for the current camera yaw (the dial's rotation).
## Camera yaw y turns the view: screen-right on the ground is (cos y, -sin y), screen-up is (-sin y, -cos y).
## With north = -Z this is yaw itself: 0 = north up, the start view (-45) = north up-left.
func _compass_degrees() -> float:
	var yaw := deg_to_rad(yaw_degrees)
	var right := Vector2(cos(yaw), -sin(yaw))
	var up := Vector2(-sin(yaw), -cos(yaw))
	return rad_to_deg(atan2(MAP_NORTH.dot(right), MAP_NORTH.dot(up)))
# --- name plate --------------------------------------------------------------------------
func _place_plate() -> void:
	if plate != null:
		plate.place(top_bar.position.y + top_bar.size.y + PLATE_GAP)
	if region_plate != null:
		region_plate.place(top_bar.position.y + top_bar.size.y + PLATE_GAP)
	if seed_plate != null:
		seed_plate.place(top_bar.position.y + top_bar.size.y + PLATE_GAP)
## The room under the cursor, or NO_HOVER (over the UI, over nothing, while walking or with the window open).
func _poll_hover() -> void:
	_hover_id = NO_HOVER
	if _moving or top_bar.is_window_open() or _panning:
		return
	var vp := get_viewport()
	if vp.gui_get_hovered_control() != null:
		return
	var pos := vp.get_mouse_position()
	if not vp.get_visible_rect().has_point(pos):
		return
	var from := camera.project_ray_origin(pos)
	var to := from + camera.project_ray_normal(pos) * camera.far
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return
	_hover_id = int((hit["collider"] as Node).get_meta("node_id", NO_HOVER))
func _room_name(id: int) -> String:
	return "START" if id == START_ID else TYPE_NAMES[map.nodes[id].type].to_upper()
## "ROOM: SHOP" for the hovered room (or the one the token walks to), else "NEXT: BATTLE / SHOP" for the
## reachable rooms, else nothing.
func _plate_message() -> String:
	if top_bar.is_window_open():
		return ""
	var shown := _token_target if _moving else _hover_id
	if shown != NO_HOVER:
		return "ROOM: %s" % _room_name(shown)
	var names := PackedStringArray()
	for id in _reachable:
		var n := _room_name(id)
		if not names.has(n):
			names.append(n)
	if names.is_empty():
		return ""
	return "NEXT: %s" % " / ".join(names)
func _update_plate() -> void:
	var text := _plate_message()
	if text != _plate_text:
		_plate_text = text
		plate.set_text(text)
# --- input and travel --------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if top_bar.is_window_open():
		return
	# Camera: the battle's keys and wheel, plus pan and Space. Works while the token walks.
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_Q:
				snap_yaw(1)
			KEY_E:
				snap_yaw(-1)
			KEY_SPACE:
				recenter()
			KEY_F:
				if not _keys_blocked():
					focus_target()
		return
	if event is InputEventMouseMotion and _panning:
		_pan(event.relative)
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE or button.button_index == MOUSE_BUTTON_RIGHT:
			_panning = button.pressed
			return
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(Stage3D.ZOOM_FACTOR)
			return
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.0 / Stage3D.ZOOM_FACTOR)
			return
	if _moving:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var from := camera.project_ray_origin(event.position)
		var to := from + camera.project_ray_normal(event.position) * camera.far
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
		if hit.is_empty():
			return
		var body := hit["collider"] as Node
		var id: int = body.get_meta("node_id", -1)
		if _reachable.has(id):
			_travel_to(id)
func _has_road(from_id: int, to_id: int) -> bool:
	return _roads.has(Vector2i(from_id, to_id))
## Where the token walks for the edge from_id -> id, from the from-room's centre: out to the door, along the
## corridor cells (only the corners are kept; the walk is a straight line between them), in to the target's
## centre. Every leg is axis-aligned.
func _travel_points(from_id: int, id: int) -> Array[Vector3]:
	var cells: Array[Vector2i] = _roads[Vector2i(from_id, id)]
	var pts: Array[Vector3] = []
	var c_from := _room_center(from_id)
	var c_to := _room_center(id)
	if cells.size() >= 2:
		pts.append(_elbow(c_from, cells[0], cells[1] - cells[0]))
		for i in cells.size():
			if i == 0 or i == cells.size() - 1 or cells[i + 1] - cells[i] != cells[i] - cells[i - 1]:
				pts.append(_cell_point(cells[i]))
		var n := cells.size()
		pts.append(_elbow(c_to, cells[n - 1], cells[n - 1] - cells[n - 2]))
	pts.append(Vector3(c_to.x, c_to.y + TOKEN_LIFT, c_to.z))
	return pts
func _cell_point(c: Vector2i) -> Vector3:
	return Vector3(c.x, _ground(Vector2(c)) + TOKEN_LIFT, c.y)
## The point on the room's centre line that lines up with the door cell, so the walk to the door turns once.
## `dir` is the corridor's direction through that door.
func _elbow(center: Vector3, door: Vector2i, dir: Vector2i) -> Vector3:
	if dir.x != 0:
		return Vector3(center.x, center.y + TOKEN_LIFT, door.y)
	return Vector3(door.x, center.y + TOKEN_LIFT, center.z)
func _travel_to(id: int) -> void:
	var cur = RunState.current_node
	var from_id: int = START_ID if cur == null else int(cur)
	if not _has_road(from_id, id):
		return   # no road, no travel (the token never jumps)
	_moving = true
	_token_target = id
	_walk_start = token.position
	var tween := create_tween()
	var last := token.position
	for p in _travel_points(from_id, id):
		var d := last.distance_to(p)
		if d < 0.001:
			continue
		tween.tween_property(token, "position", p, d / TOKEN_SPEED)
		last = p
	tween.tween_callback(_arrive.bind(id))
## The token has reached room `id`: the story card opens. Nothing is spent until PRESS ON.
func _arrive(id: int) -> void:
	if _card == null:
		_card = CARD_SCENE.instantiate()
		$UI.add_child(_card)
		_card.press_on.connect(_on_press_on)
		_card.turn_back.connect(_on_turn_back)
	# Region plate: only when the room lies in a differently named region than the room the token came from.
	var region := _region_name(id)
	if region != "" and region != _region_name(_cur_from):
		region_plate.show_timed(region, REGION_HOLD, REGION_FADE)
	var story := _story(id)
	_card.show_card(story["title"], story["text"], story["outcome"])
## The named region under the centre of room `id` (see OverworldTerrain.region_name_at), "" when it has none.
func _region_name(id: int) -> String:
	if not layout.rooms.has(id):
		return ""
	var fp: Rect2i = layout.rooms[id]
	return _terrain.region_name_at(fp.position + fp.size / 2)
## {title, text, outcome} for room `id`: CampaignText.pick() with the biome under the room's centre cell and an
## rng seeded from the run seed and the room id, so the same seed and room always read the same.
func _story(id: int) -> Dictionary:
	var fp: Rect2i = layout.rooms[id]
	var biome := OverworldStyle.BIOME_NAMES[_terrain.biome_at(fp.position + fp.size / 2)]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([RunState.seed, id])
	return CampaignText.pick(TYPE_NAMES[map.nodes[id].type].to_lower(), biome, rng)
## PRESS ON: enter the room as before.
func _on_press_on() -> void:
	var id := _token_target
	_card.hide()
	RunState.current_node = id
	_visited.append(id)
	RunFlow.go(_state_for(map.nodes[id]))
## TURN BACK: the token walks the same way back; the room stays unspent and reachable.
func _on_turn_back() -> void:
	_card.hide()
	var cur = RunState.current_node
	var from_id: int = START_ID if cur == null else int(cur)
	var pts := _travel_points(from_id, _token_target)
	pts.reverse()
	pts.append(_walk_start)
	var tween := create_tween()
	var last := token.position
	for p in pts:
		var d := last.distance_to(p)
		if d < 0.001:
			continue
		tween.tween_property(token, "position", p, d / TOKEN_SPEED)
		last = p
	tween.tween_callback(_back_home)
func _back_home() -> void:
	_moving = false
	_token_target = NO_HOVER
func _state_for(n: RunMap.MapNode) -> String:
	if _skip_enabled:
		return "victory" if n.type == RunMap.NodeType.BOSS else "map"
	match n.type:
		RunMap.NodeType.CAMPFIRE:
			return "campfire"
		RunMap.NodeType.SHOP:
			return "shop"
	return "battle"  # battle, elite, boss
func _on_skip_pressed() -> void:
	_skip_enabled = not _skip_enabled
	_update_skip_text()
func _update_skip_text() -> void:
	skip_button.text = "Skip node: %s" % ("ON" if _skip_enabled else "OFF")
