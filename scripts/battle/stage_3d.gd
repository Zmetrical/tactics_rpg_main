extends Node3D
## The 3D world only: terrain, unit sprites, highlights, camera rig, light, tilt-shift.
## No rules and no UI. battle_view.gd feeds it a Grid and Units and tells it what to show.

const Grid = preload("res://scripts/battle/grid.gd")
const TerrainTiles = preload("res://scripts/battle/terrain_tiles.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const UnitSprites = preload("res://scripts/battle/unit_sprites.gd")

# --- Coordinates -------------------------------------------------------------
const STEP := 0.5            # world units per height level (the one place this lives)
const WALL_LEVEL := 2        # walls are stored and drawn two levels high
const NO_CELL := Vector2i(-99, -99)
const BASE_DEPTH := STEP     # blocks reach this far below y = 0 so height-0 tiles have volume

# --- Terrain -----------------------------------------------------------------
## Block ids match GridMap items 0-4 in the map scenes. Which tile draws each one is decided in
## terrain_tiles.gd.
enum Block { H0, H1, H2, H3, WALL }

# --- Units -------------------------------------------------------------------
## One sprite pixel = one terrain texel (a 16 px tile is 1 world unit), so characters and ground share
## the same pixel density. Which character draws which unit is in unit_sprites.gd.
const PIXEL_SIZE := 1.0 / 16.0
const HOP_TIME := 0.09       # whole step, must stay <= 0.1 s
const HOP_HEIGHT := 0.12
## A hop never advances by more than this per rendered frame, so it always spans at least three frames. A long frame
## (clearing the blue tiles on the first step of a walk) used to swallow a whole hop and the unit skipped a tile.
const HOP_MAX_DT := HOP_TIME / 3.0
const ARRIVE_GRACE := 0.12   # after the last hop, how long before the unit goes back to its standing frame
const BLOB_SIZE := 0.8
const BLOB_LIFT := 0.015
const HIGHLIGHT_SIZE := 0.94
const HIGHLIGHT_LIFT := 0.01

# --- Camera ------------------------------------------------------------------
const CAM_FOV := 30.0
const CAM_PITCH := -40.0
const CAM_START_YAW := 45.0
const CAM_MIN_DIST := 12.0
const CAM_MAX_DIST := 60.0
const CAM_YAW_TIME := 0.18
const ZOOM_FACTOR := 0.9
const PIVOT_HEIGHT := 0.5
const CAM_FOCUS_MIN_DIST := 8.0   # combat push-in never gets closer than this
const SHAKE_REFERENCE_DIST := 30.0  # shake strengths are tuned at this distance and scale with it
const CAM_EDGE_MARGIN := 3.0   # tiles the camera centre may stay inside the map edge (0 = can reach the edge)

# --- PS1 look (3D world only; the UI sits on a higher layer and stays sharp) --
## The 3D picture is point-sampled down to this many rows, so every edge is a hard stair-step like a
## PS1 frame buffer. Lower = chunkier (180 very rough, 240 classic, 360 mild). 0 turns the look off.
const PS1_HEIGHT := 280.0
## Colour steps per channel (32 = the PS1's 15-bit colour). 256 = no banding.
const PS1_COLOR_LEVELS := 32.0
## 0..1 strength of the ordered dither that hides the banding (the PS1 dither pattern).
const PS1_DITHER := 0.6
## Unit sprites skip the PS1 filter and stay at full resolution. Needs a hidden second render of the
## scene (a flat white/black mask of the units); set false to filter everything again.
const PS1_UNITS_SHARP := true
## Shows the mask instead of the game, to check it lines up with the units (white = unit).
const PS1_DEBUG_MASK := false
## The mask is drawn on visual layer 2 by its own camera; the main camera only sees layer 1.
const MAIN_LAYER_BIT := 1
const MASK_LAYER_BIT := 2
## The mask is rendered at this fraction of the window size. 0.5 = a quarter of the pixels; edges of the
## full-resolution unit cut-out move by at most 1 px at 1080p. Set 1.0 for the old pixel-exact mask.
const MASK_SCALE := 0.5
## Unit sprites sit on their own visual layer (4). The sun ignores that layer, so terrain shadows and the
## sun's direction can no longer darken a unit when the camera turns. Instead a light that rides on the
## camera lights units, so they look the same from all four angles.
const SPRITE_LAYER_BIT := 4
const SPRITE_LIGHT_ENERGY := 0.7

const TILT_SHIFT_SHADER := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float focus_center = 0.52;      // screen-space y of the sharp band (0 top, 1 bottom)
uniform float focus_half_height = 0.16; // half the band's height
uniform float falloff = 0.30;           // distance past the band until full blur
uniform float max_blur_px = 2.5;
uniform float ps1_height = 360.0;        // rows of the fake low-res frame buffer; 0 = off
uniform float color_levels = 32.0;       // colour steps per channel
uniform float dither_strength = 1.0;
uniform sampler2D unit_mask : filter_nearest, repeat_disable;   // white where a unit is visible
uniform bool use_unit_mask = false;
uniform bool debug_mask = false;

// 4x4 ordered (Bayer) dither, the pattern the PS1 GPU used.
const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 low_cell = vec2(0.0);
	bool pixelate = ps1_height > 0.0;
	if (pixelate && use_unit_mask && textureLod(unit_mask, SCREEN_UV, 0.0).r > 0.5) {
		pixelate = false;   // this pixel belongs to a unit: leave it at full resolution
	}
	if (pixelate) {
		// Snap to the centre of a low-res pixel: hard, aliased stair-steps, no smoothing.
		float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 res = vec2(ps1_height * aspect, ps1_height);
		low_cell = floor(uv * res);
		uv = (low_cell + 0.5) / res;
		// The snapped sample point landed on a unit: use this pixel's own colour instead, so
		// unit colours do not leak into a fringe of chunky blocks around the unit.
		if (use_unit_mask && textureLod(unit_mask, uv, 0.0).r > 0.5) {
			pixelate = false;
			uv = SCREEN_UV;
		}
	}
	float away = max(abs(uv.y - focus_center) - focus_half_height, 0.0);
	float amount = smoothstep(0.0, falloff, away);
	vec3 col;
	if (amount < 0.02) {
		// In the sharp band: one tap instead of 25 (most of the screen on a typical view).
		col = textureLod(screen_tex, uv, 0.0).rgb;
	} else {
		// 3x3 Gaussian-ish kernel at a wider step. The picture is posterised to ps1_height rows right
		// after, so the missing taps are not visible.
		vec2 step_uv = SCREEN_PIXEL_SIZE * max_blur_px * amount * 1.75;
		vec3 sum = textureLod(screen_tex, uv, 0.0).rgb * 4.0;
		sum += textureLod(screen_tex, uv + vec2(step_uv.x, 0.0), 0.0).rgb * 2.0;
		sum += textureLod(screen_tex, uv - vec2(step_uv.x, 0.0), 0.0).rgb * 2.0;
		sum += textureLod(screen_tex, uv + vec2(0.0, step_uv.y), 0.0).rgb * 2.0;
		sum += textureLod(screen_tex, uv - vec2(0.0, step_uv.y), 0.0).rgb * 2.0;
		sum += textureLod(screen_tex, uv + step_uv, 0.0).rgb;
		sum += textureLod(screen_tex, uv - step_uv, 0.0).rgb;
		sum += textureLod(screen_tex, uv + vec2(step_uv.x, -step_uv.y), 0.0).rgb;
		sum += textureLod(screen_tex, uv + vec2(-step_uv.x, step_uv.y), 0.0).rgb;
		col = sum / 16.0;
	}
	if (pixelate) {
		ivec2 c = ivec2(low_cell) % 4;
		float d = (BAYER[c.y * 4 + c.x] + 0.5) / 16.0 - 0.5;   // -0.5 .. 0.5
		float steps = max(color_levels - 1.0, 1.0);
		col = floor(col * steps + 0.5 + d * dither_strength) / steps;
	}
	if (debug_mask) {
		col = vec3(textureLod(unit_mask, SCREEN_UV, 0.0).r);
	}
	COLOR = vec4(col, 1.0);
}
"""

var camera: Camera3D
var terrain: GridMap
## Unbounded on purpose (45, 135, 225 ...) so the tween never takes the long way round.
var yaw_degrees := CAM_START_YAW:
	set(value):
		yaw_degrees = value
		if _rig != null:
			_rig.rotation_degrees.y = value
var yaw_target := CAM_START_YAW

var _rig: Node3D
var _map_size := Vector2i.ZERO
var _rig_home := Vector3.ZERO     # where the rig rests when no combat focus is active
var _cam_tween: Tween
var _shake_tween: Tween
var _distance := 30.0
var _grid: Grid
var _yaw_tween: Tween
var _holders: Dictionary = {}   # Unit -> Node3D at the tile top
var _sprites: Dictionary = {}   # Unit -> Sprite3D
var _labels: Dictionary = {}    # Unit -> Label3D
var _hop: Dictionary = {}       # Unit -> {"from": Vector3, "to": Vector3, "t": float} the hop being played
var _hop_queue: Dictionary = {} # Unit -> Array[Vector3] hops still waiting (one per step the game has taken)
var _stand_in: Dictionary = {}  # Unit -> seconds until the unit goes back to its standing frame
var _file_names: Dictionary = {}   # Unit -> unit .tres file name (key into UnitSprites.CHARACTERS)
var _frame_h: Dictionary = {}   # Unit -> height of the sprite frame in world units
var _body_h: Dictionary = {}    # Unit -> height of the drawn character in world units
var _facing: Dictionary = {}    # Unit -> Vector2 world x/z direction it looks in (none = shows the front)
var _step_frame: Dictionary = {}   # Unit -> frame currently shown (0..2)
var _step_parity: Dictionary = {}  # Unit -> which walking step comes next
var _shown_rect: Dictionary = {}   # Unit -> Rect2 currently on the sprite (skip redundant updates)
var _placeholders: Dictionary = {}  # Unit.Side -> ImageTexture
var _blob_mesh: PlaneMesh
var _mask_vp: SubViewport          # hidden render of the units (white) over the terrain (black)
var _mask_cam: Camera3D
var _mask_terrain: Node3D          # black, unlit copy of the terrain on the mask layer
var _mask_black: StandardMaterial3D
var _mask_meshes: Dictionary = {}  # block id -> BoxMesh
var _proxies: Dictionary = {}      # Unit -> white silhouette Sprite3D on the mask layer
var _silhouettes: Dictionary = {}  # Texture2D -> ImageTexture (all opaque pixels white)
var _ps1_mat: ShaderMaterial
var _last_cam_z := Vector3.INF
var _highlight_mesh: PlaneMesh
var _highlight_root: Node3D
var _highlight_pool: Array[MeshInstance3D] = []
var _props_root: Node3D = null
var _prop_shadows_root: Node3D = null
var _tile_layers_root: Node3D = null
var _cast_label_pool: Array[Label3D] = []

func _ready() -> void:
	_build_light_and_environment()
	_build_terrain_node()
	_build_camera_rig()
	_build_shared_meshes()
	_highlight_root = Node3D.new()
	_highlight_root.name = "Highlights"
	add_child(_highlight_root)
	if PS1_UNITS_SHARP and PS1_HEIGHT > 0.0:
		_build_unit_mask()
	_build_tilt_shift()

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_unit_mask):
		RenderingServer.frame_pre_draw.disconnect(_sync_unit_mask)

func _process(delta: float) -> void:
	_advance_hops(minf(delta, HOP_MAX_DT), delta)
	# The camera can be rotated at any time, so which side of a unit we see changes without the unit doing anything.
	# Only re-check when the camera has actually turned.
	if camera != null:
		var cam_z := camera.global_transform.basis.z
		if not cam_z.is_equal_approx(_last_cam_z):
			_last_cam_z = cam_z
			for u: Unit in _sprites.keys():
				_apply_frame(u)

# --- Coordinates and picking (static, no scene needed) -----------------------

static func cell_to_world(cell: Vector2i, level: int) -> Vector3:
	return Vector3(cell.x, level * STEP, cell.y)

## Height level of the surface you stand on / click: walls use their top at WALL_LEVEL.
static func surface_level(grid: Grid, cell: Vector2i) -> int:
	if grid.walls.has(cell):
		return WALL_LEVEL
	return grid.height_at(cell)

## Ray vs. the top plane of every cell. Nearest hit wins. Tile bounds are half-open so a ray
## on a shared edge belongs to exactly one tile. Holes are absent from grid.heights.
static func pick_cell(ray_origin: Vector3, ray_dir: Vector3, grid: Grid) -> Vector2i:
	var best := NO_CELL
	var best_t := INF
	if absf(ray_dir.y) < 0.000001:
		return best
	for cell: Vector2i in grid.heights.keys():
		var top_y := surface_level(grid, cell) * STEP
		var t := (top_y - ray_origin.y) / ray_dir.y
		if t < 0.0 or t >= best_t:
			continue
		var hit := ray_origin + ray_dir * t
		if hit.x >= cell.x - 0.5 and hit.x < cell.x + 0.5 and hit.z >= cell.y - 0.5 and hit.z < cell.y + 0.5:
			best_t = t
			best = cell
	return best

static func block_level(block: int) -> int:
	match block:
		Block.WALL:
			return WALL_LEVEL
		_:
			return block

# --- Map ---------------------------------------------------------------------

func build_map(grid: Grid, size: Vector2i) -> void:
	_grid = grid
	_map_size = size
	terrain.clear()
	for cell: Vector2i in grid.heights.keys():
		var block: int = Block.WALL
		if not grid.walls.has(cell):
			block = clampi(grid.height_at(cell), Block.H0, Block.H3)
		terrain.set_cell_item(Vector3i(cell.x, 0, cell.y), block)
	_build_mask_terrain(grid)
	_rig.position = Vector3((size.x - 1) * 0.5, PIVOT_HEIGHT, (size.y - 1) * 0.5)
	_rig_home = _rig.position
	_distance = clampf(maxf(size.x, size.y) * 1.8 + 4.0, CAM_MIN_DIST, CAM_MAX_DIST)
	camera.position = Vector3(0.0, 0.0, _distance)

## Re-creates the decoration from the map scene (see MapLoader.MapResult.props) with its authored transform.
func build_props(props: Array) -> void:
	if _props_root != null:
		_props_root.queue_free()
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)
	for p: Dictionary in props:
		var node := (p["scene"] as PackedScene).instantiate() as Node3D
		if node == null:
			continue
		node.transform = p["xform"]
		_props_root.add_child(node)

## Soft ground shadow under each GridProp (record key "drop_shadow"), shaped like its footprint. Same two
## tones as the units' blob (0.4 core, 0.2 edge) so props and units read as one style. One small texture
## and one flat quad per prop; the texture is rasterised from the footprint cells with a gaussian falloff
## so neighbouring cells merge into one shape instead of a row of discs.
const PROP_SHADOW_PX := 8          # texels per cell: chunky on purpose, like the unit blob
const PROP_SHADOW_SIGMA := 0.38    # falloff width around each footprint cell centre, in cells
const PROP_SHADOW_CORE := 0.45
const PROP_SHADOW_EDGE := 0.10

func build_prop_shadows(grid_props: Array, grid: Grid) -> void:
	if _prop_shadows_root != null:
		_prop_shadows_root.queue_free()
	_prop_shadows_root = Node3D.new()
	_prop_shadows_root.name = "PropShadows"
	add_child(_prop_shadows_root)
	for rec: Dictionary in grid_props:
		if not bool(rec.get("drop_shadow", false)):
			continue
		var cells: Array = rec["cells"]
		if cells.is_empty():
			continue
		var lo: Vector2i = cells[0]
		var hi: Vector2i = cells[0]
		var top := -INF
		for c: Vector2i in cells:
			lo = lo.min(c)
			hi = hi.max(c)
			top = maxf(top, cell_to_world(c, surface_level(grid, c)).y)
		# One empty cell of margin all round, so the soft edge has room.
		var span := hi - lo + Vector2i(3, 3)
		var quad := MeshInstance3D.new()
		quad.name = "Shadow_%s" % String(rec["name"])
		quad.mesh = _prop_shadow_mesh(span, _prop_shadow_texture(cells, lo, span))
		quad.position = Vector3(lo.x + span.x * 0.5 - 1.5, top + BLOB_LIFT, lo.y + span.y * 0.5 - 1.5)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_prop_shadows_root.add_child(quad)

func _prop_shadow_texture(cells: Array, lo: Vector2i, span: Vector2i) -> ImageTexture:
	var px := PROP_SHADOW_PX
	var img := Image.create(span.x * px, span.y * px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var two_sigma_sq := 2.0 * PROP_SHADOW_SIGMA * PROP_SHADOW_SIGMA
	for ix in img.get_width():
		for iy in img.get_height():
			# Pixel centre in grid-cell units (a cell's centre is its integer coordinate).
			var p := Vector2((ix + 0.5) / px - 1.5 + lo.x, (iy + 0.5) / px - 1.5 + lo.y)
			var density := 0.0
			for c: Vector2i in cells:
				var d2 := p.distance_squared_to(Vector2(c))
				if d2 < 4.0:
					density += exp(-d2 / two_sigma_sq)
			if density >= PROP_SHADOW_CORE:
				img.set_pixel(ix, iy, Color(0, 0, 0, 0.4))
			elif density >= PROP_SHADOW_EDGE:
				img.set_pixel(ix, iy, Color(0, 0, 0, 0.2))
	return ImageTexture.create_from_image(img)

## A flat quad centred on its node, with explicit UVs so the image maps x -> columns, z -> rows.
func _prop_shadow_mesh(span: Vector2i, tex: Texture2D) -> ArrayMesh:
	var hx := span.x * 0.5
	var hz := span.y * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mesh.surface_set_material(0, mat)
	return mesh

## TileMapLayer3D nodes painted in the map scene. The map scene is freed after loading (see MapLoader), so
## this instances it again and keeps only the TileMapLayer3D nodes. They rebuild their own meshes in _ready.
## Their shaders are unshaded, so sun, ambient light and shadows do not change their colour.
func build_tile_layers(scene_path: String) -> void:
	if _tile_layers_root != null:
		_tile_layers_root.queue_free()
	_tile_layers_root = Node3D.new()
	_tile_layers_root.name = "TileLayers"
	add_child(_tile_layers_root)
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var root := packed.instantiate()
	for child in root.get_children():
		var script := child.get_script() as Script
		if script == null or not script.resource_path.ends_with("tilemap_layer_3d.gd"):
			continue
		root.remove_child(child)
		_tile_layers_root.add_child(child)
	root.free()

func _build_terrain_node() -> void:
	terrain = GridMap.new()
	terrain.name = "Terrain"
	terrain.cell_size = Vector3(1.0, STEP, 1.0)
	terrain.cell_center_x = false
	terrain.cell_center_y = false
	terrain.cell_center_z = false
	terrain.mesh_library = _build_mesh_library()
	add_child(terrain)

## Tileset-textured blocks, from -BASE_DEPTH up to their top. Built by terrain_tiles.gd, which is
## also what data/maps/tile_library.tres is baked from, so the editor and the battle match.
func _build_mesh_library() -> MeshLibrary:
	return TerrainTiles.build_library(STEP, BASE_DEPTH, WALL_LEVEL)

# --- Units -------------------------------------------------------------------

func add_unit(u: Unit) -> void:
	var file_name := u.data.resource_path.get_file().get_basename()
	var tex := _unit_texture(u, file_name)
	var animated := UnitSprites.sheet_for(file_name) != null
	var frame_px := UnitSprites.FRAME if animated else tex.get_height()
	var sprite_h := frame_px * PIXEL_SIZE
	_file_names[u] = file_name if animated else ""
	_frame_h[u] = sprite_h
	_body_h[u] = (UnitSprites.body_height_px(file_name) if animated else frame_px) * PIXEL_SIZE
	_step_frame[u] = UnitSprites.IDLE_FRAME
	_step_parity[u] = 0

	var holder := Node3D.new()
	holder.position = cell_to_world(u.cell, u.height)
	add_child(holder)

	var blob := MeshInstance3D.new()
	blob.mesh = _blob_mesh
	blob.position = Vector3(0.0, BLOB_LIFT, 0.0)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(blob)

	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.pixel_size = PIXEL_SIZE
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = true
	sprite.layers = SPRITE_LAYER_BIT
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.double_sided = true
	sprite.region_enabled = animated   # the sheet holds many frames; show one 32x32 region of it
	# A billboarded sprite casts an odd, camera-dependent shadow; the blob does that job.
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.position = Vector3(0.0, sprite_h * 0.5, 0.0)  # bottom edge on the tile top
	holder.add_child(sprite)
	_add_mask_proxy(u, holder, sprite, tex)

	# HP is shown in the HUD panels, not above the unit. The node stays (hidden) because the
	# combat director feeds it the animation-timed HP and tests read it back.
	var label := Label3D.new()
	label.visible = false
	sprite.add_child(label)

	_holders[u] = holder
	_sprites[u] = sprite
	_labels[u] = label
	_apply_frame(u)
	update_hp(u)

## `hp_override` >= 0 shows that value instead of u.hp, so a queued animation can show the HP as
## it was at that moment of the fight rather than the already-final number.
func update_hp(u: Unit, hp_override: int = -1) -> void:
	var label: Label3D = _labels[u]
	label.text = "%d/%d" % [u.hp if hp_override < 0 else hp_override, u.max_hp]

## Hop to u.cell / u.height in HOP_TIME. Steps queue up and play one after the other.
func move_unit(u: Unit) -> void:
	# One hop per step the game takes, queued. They play strictly one after the other, so every tile of a walk is
	# visited even when the game takes steps faster than frames are drawn.
	var queue: Array = _hop_queue.get(u, [])
	queue.append(cell_to_world(u.cell, u.height))
	_hop_queue[u] = queue
	_stand_in.erase(u)
	if not _hop.has(u):
		_start_next_hop(u)

## Starts the next queued hop of `u` from wherever it stands now.
func _start_next_hop(u: Unit) -> void:
	var queue: Array = _hop_queue.get(u, [])
	if queue.is_empty():
		return
	var holder: Node3D = _holders[u]
	var target: Vector3 = queue.pop_front()
	var heading := Vector2(target.x - holder.position.x, target.z - holder.position.z)
	if heading.length() > 0.01:
		_facing[u] = heading.normalized()
	# Alternate the two walking frames on each step; the unit stands again when the last hop ends.
	_step_frame[u] = UnitSprites.STEP_FRAMES[int(_step_parity[u]) % UnitSprites.STEP_FRAMES.size()]
	_step_parity[u] = int(_step_parity[u]) + 1
	_apply_frame(u)
	_hop[u] = {"from": holder.position, "to": target, "t": 0.0}

## `dt` moves the hops (capped, see HOP_MAX_DT); `real_dt` runs the stand-up timer.
func _advance_hops(dt: float, real_dt: float) -> void:
	for u: Unit in _hop.keys():
		if not _holders.has(u):
			continue
		var holder: Node3D = _holders[u]
		var sprite: Sprite3D = _sprites[u]
		var rest_y: float = _frame_h[u] * 0.5
		var hop: Dictionary = _hop[u]
		hop["t"] = float(hop["t"]) + dt
		var p := clampf(float(hop["t"]) / HOP_TIME, 0.0, 1.0)
		holder.position = (hop["from"] as Vector3).lerp(hop["to"] as Vector3, p)
		sprite.position.y = rest_y + HOP_HEIGHT * sin(p * PI)
		if p >= 1.0:
			holder.position = hop["to"]
			sprite.position.y = rest_y
			_hop.erase(u)
			if (_hop_queue.get(u, []) as Array).is_empty():
				_stand_in[u] = ARRIVE_GRACE   # keeps the walk frame from flashing to the standing one between steps
			else:
				_start_next_hop(u)
	for u: Unit in _stand_in.keys():
		_stand_in[u] = float(_stand_in[u]) - real_dt
		if float(_stand_in[u]) <= 0.0:
			_stand_in.erase(u)
			_stand(u)

## Standing frame, still facing the way it last looked. Safe to call late: does nothing for a unit that was removed.
func _stand(u: Unit) -> void:
	if not _sprites.has(u):
		return
	_step_frame[u] = UnitSprites.IDLE_FRAME
	_apply_frame(u)

func hide_unit(u: Unit) -> void:
	_kill_tween(u)
	var holder: Node3D = _holders[u]
	holder.visible = false

func _kill_tween(u: Unit) -> void:
	_hop.erase(u)
	_hop_queue.erase(u)
	_stand_in.erase(u)

## The character sheet for this unit (see unit_sprites.gd), else the generated placeholder.
func _unit_texture(u: Unit, file_name: String) -> Texture2D:
	var sheet := UnitSprites.sheet_for(file_name)
	if sheet != null:
		return sheet
	if not _placeholders.has(u.side):
		var color := Color(0.25, 0.5, 0.95) if u.side == Unit.Side.PLAYER else Color(0.9, 0.3, 0.25)
		_placeholders[u.side] = _make_placeholder_texture(color)
	return _placeholders[u.side]

func _make_placeholder_texture(color: Color) -> ImageTexture:
	var w := 12
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in w:
		for y in h:
			var e := pow((x + 0.5 - w * 0.5) / (w * 0.5), 2.0) + pow((y + 0.5 - h * 0.5) / (h * 0.5), 2.0)
			if e <= 1.0:
				img.set_pixel(x, y, color.darkened(0.4) if e > 0.78 else color)
	return ImageTexture.create_from_image(img)

func _build_shared_meshes() -> void:
	var blob_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	blob_img.fill(Color(0, 0, 0, 0))
	for x in 16:
		for y in 16:
			var d := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length() / 8.0
			if d <= 0.6:
				blob_img.set_pixel(x, y, Color(0, 0, 0, 0.4))
			elif d <= 1.0:
				blob_img.set_pixel(x, y, Color(0, 0, 0, 0.2))
	var blob_mat := StandardMaterial3D.new()
	blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob_mat.albedo_texture = ImageTexture.create_from_image(blob_img)
	blob_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_blob_mesh = PlaneMesh.new()
	_blob_mesh.size = Vector2(BLOB_SIZE, BLOB_SIZE)
	_blob_mesh.material = blob_mat

	_highlight_mesh = PlaneMesh.new()
	_highlight_mesh.size = Vector2(HIGHLIGHT_SIZE, HIGHLIGHT_SIZE)

# --- Combat presentation hooks (used by combat_director.gd) -------------------
# The stage only exposes handles and camera moves; what plays on them lives in the director.

func has_unit(u: Unit) -> bool:
	return _holders.has(u)

func holder_of(u: Unit) -> Node3D:
	return _holders[u]

func sprite_of(u: Unit) -> Sprite3D:
	return _sprites[u]

## World position of the unit's feet when it is standing still on its tile.
func unit_rest(u: Unit) -> Vector3:
	return cell_to_world(u.cell, u.height)

## Local y of the sprite node while the unit is standing still.
func sprite_rest_y(u: Unit) -> float:
	return _frame_h[u] * 0.5

## Roughly torso height: where hits, numbers and projectiles aim.
func unit_chest(u: Unit) -> Vector3:
	return unit_rest(u) + Vector3(0.0, _body_h[u] * 0.55, 0.0)

## Top surface of a tile in world space (walls use their top).
func cell_top(cell: Vector2i) -> Vector3:
	var level := surface_level(_grid, cell) if _grid != null else 0
	return cell_to_world(cell, level)

## Drops any hop still playing or queued and snaps the unit back to a clean standing pose on its tile.
func settle_unit(u: Unit) -> void:
	_kill_tween(u)
	_holders[u].position = unit_rest(u)
	var sprite: Sprite3D = _sprites[u]
	sprite.position.y = sprite_rest_y(u)
	sprite.modulate = Color.WHITE
	sprite.shaded = true
	_stand(u)

## Turn the unit to look toward `world`. Which of the sheet's four facings that shows depends on the
## camera, so it is worked out from the camera every frame (see _apply_frame).
func face_toward(u: Unit, world: Vector3) -> void:
	var from: Vector3 = _holders[u].global_position
	var heading := Vector2(world.x - from.x, world.z - from.z)
	if heading.length() > 0.01:
		_facing[u] = heading.normalized()
		_apply_frame(u)

## Shows the right frame of the sheet for the unit's facing, current step and the camera's yaw.
func _apply_frame(u: Unit) -> void:
	var file_name: String = _file_names.get(u, "")
	if file_name == "" or camera == null:
		return
	var cam_basis := camera.global_transform.basis
	var cam_forward := Vector2(-cam_basis.z.x, -cam_basis.z.z).normalized()
	var row := UnitSprites.Row.FRONT
	if _facing.has(u):
		row = UnitSprites.row_for(_facing[u], cam_forward)
	var rect := UnitSprites.frame_rect(file_name, row, _step_frame[u])
	if _shown_rect.get(u) != rect:
		_shown_rect[u] = rect
		(_sprites[u] as Sprite3D).region_rect = rect

## Pan the camera rig to `world` and push in by `zoom_factor` (< 1 = closer). Nothing in the
## game reads the camera, so this is purely visual.
func camera_focus(world: Vector3, zoom_factor: float, time: float) -> void:
	if _cam_tween != null:
		_cam_tween.kill()
	var c := _clamp_to_map(world)
	var target := Vector3(c.x, PIVOT_HEIGHT + world.y, c.z)
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(_rig, "position", target, time)
	_cam_tween.tween_property(camera, "position:z", maxf(_distance * zoom_factor, CAM_FOCUS_MIN_DIST), time)

## Make `world` the place the camera rests (what camera_release returns to). With glide = true the
## camera also moves there now. The battle view points this at the current unit.
func set_camera_home(world: Vector3, glide: bool, time: float) -> void:
	var c := _clamp_to_map(world)
	_rig_home = Vector3(c.x, PIVOT_HEIGHT + world.y, c.z)
	if glide:
		camera_release(time)

## Keeps the camera centre near the map so the view never shows mostly empty space.
## Maps smaller than 2 * margin just stay centred.
func _clamp_to_map(world: Vector3) -> Vector3:
	if _map_size == Vector2i.ZERO:
		return world
	var out := world
	out.x = _clamp_axis(world.x, float(_map_size.x - 1))
	out.z = _clamp_axis(world.z, float(_map_size.y - 1))
	return out

func _clamp_axis(value: float, max_value: float) -> float:
	var lo := CAM_EDGE_MARGIN
	var hi := max_value - CAM_EDGE_MARGIN
	if lo > hi:
		return max_value * 0.5
	return clampf(value, lo, hi)

## World position of the map centre (the HUD uses it to pick which side its panels sit on).
func map_center() -> Vector3:
	return Vector3((_map_size.x - 1) * 0.5, PIVOT_HEIGHT, (_map_size.y - 1) * 0.5)

func camera_release(time: float) -> void:
	if _cam_tween != null:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(_rig, "position", _rig_home, time)
	_cam_tween.tween_property(camera, "position:z", _distance, time)

## Decaying screen shake through the camera's own frustum offset (does not move the rig).
func camera_shake(strength: float, time: float) -> void:
	if _shake_tween != null:
		_shake_tween.kill()
	var scale_with_distance := camera.position.z / SHAKE_REFERENCE_DIST
	_shake_tween = create_tween()
	_shake_tween.tween_method(func(t: float) -> void:
		var k := (1.0 - t) * (1.0 - t) * strength * scale_with_distance
		camera.h_offset = randf_range(-k, k)
		camera.v_offset = randf_range(-k, k), 0.0, 1.0, time)
	_shake_tween.tween_callback(func() -> void:
		camera.h_offset = 0.0
		camera.v_offset = 0.0)

# --- Highlights --------------------------------------------------------------

## colors: cell -> Color. Cells that are not tiles are skipped. Quads are pooled.
func set_highlights(colors: Dictionary) -> void:
	var used := 0
	if _grid != null:
		for cell: Vector2i in colors.keys():
			if not _grid.has_tile(cell):
				continue
			var quad := _highlight_quad(used)
			used += 1
			var mat: StandardMaterial3D = quad.material_override
			mat.albedo_color = colors[cell]
			quad.position = cell_to_world(cell, surface_level(_grid, cell)) + Vector3(0.0, HIGHLIGHT_LIFT, 0.0)
			quad.visible = true
	for i in range(used, _highlight_pool.size()):
		_highlight_pool[i].visible = false

## entries: [{"cell": Vector2i, "text": String}]. Floating countdown over each locked tile.
func set_cast_labels(entries: Array) -> void:
	if _grid == null:
		return
	var used := 0
	for e: Dictionary in entries:
		var cell: Vector2i = e["cell"]
		if not _grid.has_tile(cell):
			continue
		var label := _cast_label(used)
		used += 1
		label.text = str(e["text"])
		label.position = cell_to_world(cell, surface_level(_grid, cell)) + Vector3(0.0, 1.2, 0.0)
		label.visible = true
	for i in range(used, _cast_label_pool.size()):
		_cast_label_pool[i].visible = false

func _cast_label(index: int) -> Label3D:
	if index < _cast_label_pool.size():
		return _cast_label_pool[index]
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.pixel_size = 0.005
	label.outline_size = 12
	label.modulate = Color(0.85, 0.6, 1.0)
	_highlight_root.add_child(label)
	_cast_label_pool.append(label)
	return label

func _highlight_quad(index: int) -> MeshInstance3D:
	if index < _highlight_pool.size():
		return _highlight_pool[index]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := MeshInstance3D.new()
	quad.mesh = _highlight_mesh
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight_root.add_child(quad)
	_highlight_pool.append(quad)
	return quad

# --- Camera ------------------------------------------------------------------

func _build_camera_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "CameraRig"
	_rig.rotation_degrees = Vector3(CAM_PITCH, yaw_degrees, 0.0)
	add_child(_rig)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAM_FOV
	camera.near = 0.5
	camera.far = 200.0
	camera.cull_mask = MAIN_LAYER_BIT | SPRITE_LAYER_BIT   # the mask copies live on layer 2 and are not drawn here
	camera.position = Vector3(0.0, 0.0, _distance)
	_rig.add_child(camera)
	camera.current = true
	# Lights units only (layer 4), always from the camera's side, so no camera angle leaves a unit in the dark.
	var unit_light := DirectionalLight3D.new()
	unit_light.name = "UnitLight"
	unit_light.light_color = Color(1.0, 0.95, 0.88)
	unit_light.light_energy = SPRITE_LIGHT_ENERGY
	unit_light.light_cull_mask = SPRITE_LAYER_BIT
	unit_light.shadow_enabled = false
	camera.add_child(unit_light)

## direction: +1 or -1. Only the camera moves; nothing in the game reads it.
func snap_yaw(direction: int) -> void:
	yaw_target += 90.0 * direction
	if _yaw_tween != null:
		_yaw_tween.kill()
	_yaw_tween = create_tween()
	_yaw_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_yaw_tween.tween_property(self, "yaw_degrees", yaw_target, CAM_YAW_TIME)

func zoom(factor: float) -> void:
	_distance = clampf(_distance * factor, CAM_MIN_DIST, CAM_MAX_DIST)
	camera.position.z = _distance

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_Q:
					snap_yaw(1)
				KEY_E:
					snap_yaw(-1)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed:
			match button.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					zoom(ZOOM_FACTOR)
				MOUSE_BUTTON_WHEEL_DOWN:
					zoom(1.0 / ZOOM_FACTOR)

# --- Look: light, environment, tilt-shift ------------------------------------

func _build_light_and_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_cull_mask = MAIN_LAYER_BIT
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var sky := Color(0.70, 0.80, 0.90)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.64, 0.80)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = false   # threshold 1.0 on an LDR Compatibility frame never triggers, but the passes cost full-screen blurs
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = sky
	env.fog_density = 0.006
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

## Compatibility has no DoF blur, so blur by screen-space distance from a horizontal band.
## Layer 0 sits below the UI CanvasLayer (layer 1), so the UI stays sharp.
func _build_tilt_shift() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TiltShift"
	layer.layer = 0
	add_child(layer)
	var rect := ColorRect.new()
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = TILT_SHIFT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("ps1_height", PS1_HEIGHT)
	mat.set_shader_parameter("color_levels", PS1_COLOR_LEVELS)
	mat.set_shader_parameter("dither_strength", PS1_DITHER)
	if _mask_vp != null:
		mat.set_shader_parameter("unit_mask", _mask_vp.get_texture())
		mat.set_shader_parameter("use_unit_mask", true)
		mat.set_shader_parameter("debug_mask", PS1_DEBUG_MASK)
	_ps1_mat = mat
	rect.material = mat

# --- Unit mask (keeps units out of the PS1 filter) ---------------------------
# A second camera in a hidden SubViewport re-draws the scene as flat shapes: terrain in black,
# unit silhouettes in white. Because the terrain copy is drawn too, a unit behind a wall is hidden
# in the mask exactly as it is in the real picture. The tilt-shift/PS1 shader reads this mask and
# leaves white pixels alone.

func _window_pixels() -> Vector2i:
	var win := get_window()
	var px := Vector2i(win.size) if win != null else Vector2i(1280, 720)
	return Vector2i(maxi(int(px.x * MASK_SCALE), 2), maxi(int(px.y * MASK_SCALE), 2))

func _build_unit_mask() -> void:
	_mask_vp = SubViewport.new()
	_mask_vp.name = "UnitMask"
	_mask_vp.own_world_3d = false          # draws the same world as the main view
	_mask_vp.transparent_bg = false
	_mask_vp.msaa_3d = Viewport.MSAA_DISABLED
	_mask_vp.gui_disable_input = true
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_vp.size = _window_pixels()
	add_child(_mask_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	_mask_cam = Camera3D.new()
	_mask_cam.environment = env
	_mask_cam.cull_mask = MASK_LAYER_BIT   # only the flat copies
	_mask_vp.add_child(_mask_cam)
	_mask_cam.current = true

	_mask_black = StandardMaterial3D.new()
	_mask_black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mask_black.albedo_color = Color.BLACK
	_mask_terrain = Node3D.new()
	_mask_terrain.name = "MaskTerrain"
	add_child(_mask_terrain)

	var win := get_window()
	if win != null:
		win.size_changed.connect(func() -> void: _mask_vp.size = _window_pixels())
	RenderingServer.frame_pre_draw.connect(_sync_unit_mask)

## Black, unlit boxes the same size and place as the terrain blocks (see terrain_tiles.gd).
## One MultiMesh per block type (5 draw calls) instead of one node and draw call per tile.
func _build_mask_terrain(grid: Grid) -> void:
	if _mask_terrain == null:
		return
	for child in _mask_terrain.get_children():
		child.queue_free()
	var by_block: Dictionary = {}   # block id -> Array[Transform3D]
	for cell: Vector2i in grid.heights.keys():
		var block: int = Block.WALL
		if not grid.walls.has(cell):
			block = clampi(grid.height_at(cell), Block.H0, Block.H3)
		var top := block_level(block) * STEP
		if not by_block.has(block):
			by_block[block] = []
		(by_block[block] as Array).append(Transform3D(Basis.IDENTITY, Vector3(cell.x, (top - BASE_DEPTH) * 0.5, cell.y)))
	for block: int in by_block.keys():
		var xforms: Array = by_block[block]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mask_mesh(block)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.layers = MASK_LAYER_BIT
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mask_terrain.add_child(mmi)

func _mask_mesh(block: int) -> BoxMesh:
	if not _mask_meshes.has(block):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, block_level(block) * STEP + BASE_DEPTH, 1.0)
		mesh.material = _mask_black
		_mask_meshes[block] = mesh
	return _mask_meshes[block]

## A white copy of the unit's sprite on the mask layer, riding on the same holder.
func _add_mask_proxy(u: Unit, holder: Node3D, sprite: Sprite3D, tex: Texture2D) -> void:
	if _mask_vp == null:
		return
	var white := _silhouette(tex)
	if white == null:
		return
	var proxy := Sprite3D.new()
	proxy.texture = white
	proxy.pixel_size = sprite.pixel_size
	proxy.billboard = sprite.billboard
	proxy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	proxy.shaded = false
	proxy.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	proxy.double_sided = true
	proxy.region_enabled = sprite.region_enabled
	proxy.region_rect = sprite.region_rect
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.layers = MASK_LAYER_BIT
	proxy.position = sprite.position
	holder.add_child(proxy)
	_proxies[u] = proxy

## Same pixels as `tex`, every visible one turned white.
func _silhouette(tex: Texture2D) -> Texture2D:
	if _silhouettes.has(tex):
		return _silhouettes[tex]
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		data[i] = 255
		data[i + 1] = 255
		data[i + 2] = 255
	var white := ImageTexture.create_from_image(Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data))
	_silhouettes[tex] = white
	return white

## Runs right before each frame is drawn, so the mask uses this frame's camera and sprite poses
## (not last frame's) and cannot trail behind during hops, zooms and shakes.
func _sync_unit_mask() -> void:
	if _mask_cam == null or camera == null:
		return
	_mask_cam.global_transform = camera.global_transform
	_mask_cam.projection = camera.projection
	_mask_cam.fov = camera.fov
	_mask_cam.near = camera.near
	_mask_cam.far = camera.far
	_mask_cam.h_offset = camera.h_offset
	_mask_cam.v_offset = camera.v_offset
	for u: Unit in _proxies.keys():
		var proxy: Sprite3D = _proxies[u]
		var sprite: Sprite3D = _sprites[u]
		proxy.position = sprite.position
		proxy.rotation = sprite.rotation
		proxy.scale = sprite.scale
		proxy.flip_h = sprite.flip_h
		proxy.flip_v = sprite.flip_v
		if proxy.region_rect != sprite.region_rect:
			proxy.region_rect = sprite.region_rect
