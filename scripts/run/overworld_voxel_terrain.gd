class_name OverworldVoxelTerrain
extends RefCounted
## Step 1c parity adapter: OverworldTerrain.Terrain data -> VoxelWorld + per-face colours that reproduce the old slab mesh.
## Scale: 1 cell = CELL_VOX voxels per side, 1 height level = LEVEL_VOX voxels, so VOXEL_SIZE 0.25 gives cubes
## (cell 1.0 / 0.25 = 4, Stage3D.STEP 0.5 / 0.25 = 2). Voxel y = 0 is the slab bottom (world y = -slab_depth).
## Voxel (0, 0, 0) is the corner of cell (x0, z0): world (x0 - 0.5, -slab_depth, z0 - 0.5). See `origin`.
## Colours: face_color() is the VoxelChunkMesher.face_color_fn. Same rules as the old mesh in overworld_terrain.gd:
## lit top (checker, rock by level), unlit water top, two-band wall (lip, soil) on faces to non-land,
## one-band step to a lower neighbour (shore colour when that neighbour is water), baked left / right light.
## Not identical: the bank strip (0.18 wide in the old mesh) becomes the outer voxel row (0.25), lip band 0.3 -> 1 voxel.

const Style = preload("res://data/run/overworld_style.gd")
const Stage3D = preload("res://scripts/battle/stage_3d.gd")

## Cell step per face index (+Y, -Y, +X, -X, +Z, -Z); only 2..5 are read.
const FACE_DIR: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var world: VoxelWorld
## Position of voxel (0, 0, 0) in terrain space: put the VoxelChunkView here.
var origin := Vector3.ZERO
var cell_vox := 4
var level_vox := 2
var base_vox := 12    # voxels below level 0
var lip_vox := 1
var build_ms := 0.0

var _parity_shift := 0   # x0 + z0: the old checker is posmod(x0 + ix + z0 + iz, 2)

var _nx := 1
var _nz := 1
var _levels := PackedInt32Array()
var _biomes := PackedByteArray()
var _water := PackedByteArray()
var _land := PackedByteArray()
var _top_cache: Dictionary = {}   # key -> lit top Color
var _water_top := Color.WHITE
var _bank_top := Color.WHITE
var _lip: Array = []              # [face][biome] -> Color
var _soil: Array = []             # [face] -> Color
var _water_side: Array = []       # [face] -> Color
var _shore: Array = []            # [face] -> Color


## `style` defaults to Style.GRASSLAND, like OverworldTerrain.build.
static func build(t: Object, style: Dictionary = {}) -> OverworldVoxelTerrain:
	var t0 := Time.get_ticks_usec()
	var r := OverworldVoxelTerrain.new()
	r._setup(t, style if not style.is_empty() else Style.GRASSLAND)
	r.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return r


func _setup(t: Object, s: Dictionary) -> void:
	var vs := OverworldVoxel.VOXEL_SIZE
	cell_vox = roundi(1.0 / vs)
	level_vox = roundi(Stage3D.STEP / vs)
	base_vox = roundi(float(s["slab_depth"]) / vs)
	lip_vox = maxi(roundi(float(s["slab_lip"]) / vs), 1)
	assert(is_equal_approx(cell_vox * vs, 1.0) and is_equal_approx(level_vox * vs, Stage3D.STEP), "VOXEL_SIZE must divide 1.0 and Stage3D.STEP")
	_nx = t.nx
	_nz = t.nz
	_levels = t.levels
	_biomes = t.biomes
	_water = t.water
	_land = t.land
	_parity_shift = t.x0 + t.z0
	origin = Vector3(t.x0 - 0.5, -float(s["slab_depth"]), t.z0 - 0.5)
	_init_colors()
	world = VoxelWorld.new(_nx * cell_vox, _nz * cell_vox, OverworldVoxel.MAX_HEIGHT, PackedStringArray(OverworldVoxel.MATERIAL_KEYS))
	for iz in _nz:
		for ix in _nx:
			var i := iz * _nx + ix
			if _land[i] == 0:
				continue
			var h := base_vox + _levels[i] * level_vox
			var top := OverworldVoxel.WATER if _water[i] == 1 else (OverworldVoxel.STONE if _biomes[i] == Style.ROCK else OverworldVoxel.GRASS)
			var runs := PackedInt32Array([OverworldVoxel.ROCK, h - 1, top, 1])
			for dx in cell_vox:
				for dz in cell_vox:
					world.set_column(ix * cell_vox + dx, iz * cell_vox + dz, runs)


## VoxelChunkMesher.face_color_fn.
func face_color(x: int, y: int, z: int, f: int, _m: int) -> Color:
	var ix := x / cell_vox
	var iz := z / cell_vox
	var i := iz * _nx + ix
	var wet := _water[i] == 1
	if f == 0:
		if wet:
			return _water_top
		var sx := x % cell_vox
		var sz := z % cell_vox
		if (sx == 0 and _wet_at(ix - 1, iz)) or (sx == cell_vox - 1 and _wet_at(ix + 1, iz)) \
				or (sz == 0 and _wet_at(ix, iz - 1)) or (sz == cell_vox - 1 and _wet_at(ix, iz + 1)):
			return _bank_top
		var bi := _biomes[i]
		var level := _levels[i]
		var alt := posmod(ix + iz + _parity_shift, 2) == 1
		var key := (bi * 2 + (1 if alt else 0)) * 64 + level
		var c: Variant = _top_cache.get(key)
		if c == null:
			c = _lit(Style.top_color(bi, alt, level), Style.LIGHT_TOP)
			_top_cache[key] = c
		return c
	if f == 1:
		return _soil[3]
	var d := FACE_DIR[f]
	var jx := ix + d.x
	var jz := iz + d.y
	if jx < 0 or jz < 0 or jx >= _nx or jz >= _nz or _land[jz * _nx + jx] == 0:
		# Slab edge: lip band on top, soil below.
		if y >= base_vox + _levels[i] * level_vox - lip_vox:
			return _water_side[f] if wet else _lip[f][_biomes[i]]
		return _soil[f]
	if wet:
		return _water_side[f]
	if _water[jz * _nx + jx] == 1:
		return _shore[f]
	return _lip[f][_biomes[i]]


func _wet_at(ix: int, iz: int) -> bool:
	if ix < 0 or iz < 0 or ix >= _nx or iz >= _nz:
		return false
	return _water[iz * _nx + ix] == 1


func _init_colors() -> void:
	var yaw := deg_to_rad(Stage3D.CAM_START_YAW + Style.VIEW_YAW_OFFSET)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	_water_top = Style.water_color()
	_bank_top = _lit(Style.bank_lip_color(), Style.LIGHT_TOP)
	var soil := Style.soil_color()
	var wside := Style.water_side_color()
	var bank := Style.bank_lip_color()
	_lip.resize(6)
	_soil.resize(6)
	_water_side.resize(6)
	_shore.resize(6)
	for f in 6:
		var light := Style.LIGHT_RIGHT
		if f >= 2:
			var out := Vector3(FACE_DIR[f].x, 0, FACE_DIR[f].y)
			light = Style.LIGHT_LEFT if out.dot(right) < 0.0 else Style.LIGHT_RIGHT
		var per_biome: Array = []
		for b in 3:
			per_biome.append(_lit(Style.face_color(b), light))
		_lip[f] = per_biome
		_soil[f] = _lit(soil, light)
		_water_side[f] = _lit(wside, light)
		_shore[f] = _lit(bank, light)


static func _lit(col: Color, f: float) -> Color:
	return Color(col.r * f, col.g * f, col.b * f, col.a)
