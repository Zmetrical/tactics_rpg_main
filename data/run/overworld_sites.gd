extends RefCounted
## Scale, path widths and site sizes for the voxel overworld. World units unchanged: 1 unit = one old cell.
const VOXEL_SIZE := 0.5            # = Stage3D.STEP; 2 x 2 voxels per old cell, one height level = one voxel
const VOXELS_PER_CELL := 2         # 1.0 / VOXEL_SIZE
const ROAD_WIDTH_MIN := 2          # voxels, cobble, story edges
const ROAD_WIDTH_MAX := 3
const TRAIL_WIDTH := 1             # voxels, dirt, battle-to-battle edges
## Minimum landmark footprints in voxels (x, z). RunTuning.ROOM_SIZES is a minimum; these are larger.
const SITE_SIZE := {
	"START": Vector2i(8, 8),       # landing camp
	"SHOP": Vector2i(12, 12),      # village
	"CAMPFIRE": Vector2i(8, 8),    # shrine
	"BOSS": Vector2i(16, 16),      # fortress
	"BATTLE": Vector2i(4, 4),      # banner / campfire / signpost / stone circle
	"ELITE": Vector2i(6, 6),       # ruined tower / braziered stone circle
}
## Character regions (terrain variety without biomes).
const REGIONS: Array[String] = ["DEEP_FOREST", "CLIFF_TERRACES", "RIVER_VALLEY", "LAVENDER_GROVE", "VILLAGE_BASIN", "RUINED_HILL"]
## Per-stage seed salts: stage seed = master seed ^ salt.
const SALT_TERRAIN := 0x7E44A1
const SALT_SITES := 0x51735
const SALT_PATHS := 0x9A7B5
const SALT_PROPS := 0x960B5
## Routing grid stays on the coarse 1-unit cell grid; width is painted afterwards.
const ROUTE_CELL_VOXELS := 2
