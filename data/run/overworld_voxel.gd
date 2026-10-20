class_name OverworldVoxel
extends RefCounted
## Tunables for VoxelWorld (step 1a). Phase 0 budget may change VOXEL_SIZE / MAX_HEIGHT.

const VOXEL_SIZE := 0.25
const MAX_HEIGHT := 64
const STAGE_SALT := 0x564F5845
const DEBUG_HASH := true
## Step 1c debug toggle: true = overworld terrain is drawn from VoxelWorld + mesher, false = the old Slab mesh.
const PARITY_VOXEL_TERRAIN := true

const AIR := 0
const GRASS := 1
const CLAY := 2
const STONE := 3
const ROAD := 4
const TRAIL := 5
const WATER := 6
const WOOD := 7
const ROOF := 8
const ROCK := 9
const ROOT := 10

## id -> palette key. Index = id. Palette colours arrive in 8a.
const MATERIAL_KEYS: Array[String] = [
	"air", "grass", "clay", "stone", "road", "trail",
	"water", "wood", "roof", "rock", "root",
]

## Placeholder colours, index = material id. Replaced by overworld_palette.gd in 8a.
const COLORS: Array[Color] = [
	Color(0, 0, 0, 0),
	Color("8fcf8a"), Color("e8b08c"), Color("9a9a9f"), Color("e6d5a8"), Color("b8a070"),
	Color("8ec9ea"), Color("a9774d"), Color("d9825f"), Color("7a5a45"), Color("4a3a30"),
]

## Per-face shade, order = VoxelChunkMesher face order: +Y, -Y, +X, -X, +Z, -Z.
const FACE_SHADE: Array[float] = [1.0, 0.5, 0.8, 0.65, 0.72, 0.58]

const CHUNK_SIZE := 16
