extends RefCounted
## Look of one overworld biome: terrain numbers. overworld_terrain.gd reads a style dictionary, so a new
## biome is another const with the same keys. Distances are overworld units (1 unit = 1 block).
## Colours are not stored here: they come from gbc_palette.gd (or shades of it) through the static
## functions below.
const Palette = preload("res://ui/theme/gbc_palette.gd")
const TerrainTiles = preload("res://scripts/battle/terrain_tiles.gd")
const BattleView = preload("res://scripts/battle/battle_view.gd")
## Noise seed = run seed ^ this. Never the layer index.
const NOISE_SALT := 0xC0FFEE
## Baked slab light, from the top-left of the screen: share of the colour kept by top faces and by wall /
## step faces that face the left or the right of the screen. Seen from the map's first camera yaw, which is
## Stage3D.CAM_START_YAW + this offset (the same -90 as RunMapView.START_YAW_OFFSET).
const LIGHT_TOP := 1.0
const LIGHT_LEFT := 0.85
const LIGHT_RIGHT := 0.70
const VIEW_YAW_OFFSET := -90.0
## Biome ids, as returned by the terrain's biome_at(cell).
const MEADOW := 0
const FOREST := 1
const ROCK := 2
const BIOME_NAMES: Array[String] = ["meadow", "forest", "rock"]
## Stored in the terrain's per-cell biome array for cells outside the land mask (no block there). Not a biome:
## it has no entry in BIOME_NAMES, and terrain.biome_at(cell) returns "" for such cells.
const NONE := 3
## Land mask (overworld_terrain.gd, step 19). A cell is land when its distance d to the nearest room footprint or
## corridor cell is below COAST_R0 + n * COAST_A, n = 2-octave noise (seed ^ NOISE_SALT) in -1..1. Cells nearer than
## COAST_FORCE_D are always land, which keeps every room / corridor cell at least COAST_MIN_CLEAR cells from the coast
## (d is a chamfer distance, up to ~8% above the true distance: 3.6 / 1.0824 = 3.3 >= 3).
const COAST_R0 := 8.0
const COAST_A := 5.0
const COAST_NOISE_FREQ := 0.07
const COAST_OCTAVES := 2
const COAST_NOISE_OFFSET := 3000.0   # noise sample offset, so the coast does not follow the hill noise
const COAST_MIN_CLEAR := 3.0
const COAST_FORCE_D := 3.6
## Extra radius towards the boss (east) end of the layout, ramped in from the layout's centre. 0 = off (the brief's
## numbers as given). Raise it if the main range has too little land east of the boss room to rise.
const COAST_EAST_BONUS := 0.0
## Spire props (overworld_decor.gd): only on rock at or above this level (massif summits and upper slopes), in clumps.
const SPIRE_MIN_LEVEL := 4
const SPIRE_DENSITY := 0.3       # chance per qualifying cell at the centre of a clump
const SPIRE_CLUMP_FREQ := 0.22   # clump noise: roughly 4-5 cell clumps
const SPIRE_CLUMP_FROM := 0.50   # clump noise (0..1) where the density starts / is full
const SPIRE_CLUMP_TO := 0.70
const SPIRE_LONE_RADIUS := 3     # a spire with no other spire within this many cells (8-way, out to this radius) is dropped
## --- island mask (scripts/run/overworld/island_mask.gd, step 2a-2) ---
## Pure outline: knows no rooms, nodes or paths. Grid = ISLAND_NX x ISLAND_NZ cells (x = layer axis, z = column axis),
## about 2:1. Land = cells inside a distorted ellipse (radii = half the grid * ISLAND_FILL), after a domain warp.
## The "Island outline" spec in docs/STATE.md was not written yet (step 2a-1 needs reference.png): these are the
## brief's defaults (2:1, ragged, one landmass); retune here once the spec exists.
const ISLAND_SALT := 0x15A1D4
const ISLAND_NX := 96
const ISLAND_NZ := 48
const ISLAND_FILL := 0.74            # ellipse radius as a share of the half grid, before lobes and noise
const ISLAND_BORDER := 2             # cells at the grid edge that are always water
const ISLAND_WARP_FREQ := 0.035      # domain warp: cycles per cell
const ISLAND_WARP_OCTAVES := 2
const ISLAND_WARP_AMP := 0.14        # warp distance as a share of the shorter grid side
const ISLAND_EAST_WIDEN := 0.14      # east (+x) end wider by this share, west end narrower
const ISLAND_BEND := 0.10            # banana bend of the long axis (sign from seed), share of the z radius
const ISLAND_LOBE_SCALE := 1.6       # bays and peninsulas: noise walked around the outline, larger = more lobes
const ISLAND_LOBE_OCTAVES := 2
const ISLAND_LOBE_AMP := 0.24        # radius +- this share of the ellipse radius
const ISLAND_EDGE_FREQ := 0.09       # ragged edge noise: cycles per cell
const ISLAND_EDGE_OCTAVES := 3
const ISLAND_EDGE_AMP := 0.07
const ISLAND_CLEAN_ROUNDS := 6       # cleanup (open, keep biggest body, fill holes, prune tips) repeats until stable, at most this often
const ISLAND_OPEN_PASSES := 1        # erode + dilate (4-neighbour): removes spurs and strips 1-2 cells wide
## --- island base height (scripts/run/overworld/island_height.gd, step 2a-4) ---
## Heights are whole VOXELS (OverworldVoxel.VOXEL_SIZE). Every land cell sits on a "rung" of a seeded ladder that starts
## at ISLAND_H_FLOOR; the rungs are ISLAND_H_STEP_MIN..MAX voxels apart. Neighbouring land cells differ by 0 or by that
## many voxels (vertical cliff face, never a slope). Continuous height = floor + coast-distance base + hill noise, then
## it snaps down to a rung. Mesas (2b) add on top of this.
const ISLAND_H_SALT := 0x4E1647
const ISLAND_H_FLOOR := 4            # coast / lowest land height, voxels
const ISLAND_H_BASE_RISE := 4.0      # low continental base: extra voxels reached inland
const ISLAND_H_BASE_DIST := 14.0     # cells from the coast over which the base rises (smoothstep)
const ISLAND_H_HILL_AMP := 16.0      # rolling hills: up to this many voxels on top of the base
const ISLAND_H_HILL_FREQ := 0.045
const ISLAND_H_HILL_OCTAVES := 3
const ISLAND_H_HILL_FROM := 0.42     # hill noise (0..1) below this = no hill, full hill at ISLAND_H_HILL_TO
const ISLAND_H_HILL_TO := 0.72
const ISLAND_H_HILL_RAMP_DIST := 8.0 # hills fade in over this many cells from the coast (lowland rim)
const ISLAND_H_STEP_MIN := 3         # voxels between neighbouring rungs, and so the smallest cliff
const ISLAND_H_STEP_MAX := 6         # ... and the largest; no two neighbouring land cells differ by more
const ISLAND_H_MIN_PATCH := 12       # a same-height patch smaller than this (cells) joins its neighbours
const ISLAND_H_ROUNDS := 4           # patch merge + step limit rounds, at most
const ISLAND_H_MAX := 40             # hard cap, voxels (OverworldVoxel.MAX_HEIGHT is 64)
## Debug height ramp, low to high; water is ISLAND_H_WATER_COLOR.
const ISLAND_H_WATER_COLOR := Color("1b3a5c")
const ISLAND_H_RAMP: Array[Color] = [Color("2e7d5b"), Color("8fcf8a"), Color("e6d5a8"), Color("e8a060"), Color("b5503a"), Color("ffffff")]
const GRASSLAND := {
	# --- heightmap (sampled once per 1x1 block, then quantized to Stage3D.STEP levels) ---
	"vertex_step": 1.0,         # one sample per block; keep at 1.0
	"margin": 12.0,             # terrain extends this far past layout.bounds
	"level_max": 3,             # blocks are 0..3 levels high, like the battle's H0..H3
	"hill_amp": 1.5,            # = level_max * STEP, so the hills use every level
	"hill_freq": 0.07,
	"hill_octaves": 2,
	"hill_floor": 0.30,         # noise (0..1) below this is flat meadow, above it hills rise to hill_peak
	"hill_peak": 0.85,
	# Hills grow with smoothstep(0, mask_radius, distance - flat radius). Cells whose centre lies within
	# the flat radius are level 0 (a cell centre is at most 0.71 from a road point, road_flat is 1.1).
	"mask_radius": 3.0,
	"road_flat": 1.1,
	"node_flat": 2.0,
	# --- diorama slab (overworld_terrain.gd): a block of land with a natural silhouette (land mask, COAST_* above) ---
	# The grid the mask lives on is layout.bounds grown by max(slab_margin, COAST_R0 + COAST_A + COAST_EAST_BONUS + 2); slab_margin and
	# slab_extra_east now only define the "old rectangle" the build log compares the land cell count with.
	"slab_margin": 9.0,         # slab = layout.bounds grown by this; keep >= decor_margin + tree_radius so nothing hangs off the edge
	"slab_level": 1,            # flat height level of every cell (top at level * Stage3D.STEP); heights never depend on colour
	"slab_depth": 3.0,          # side wall height below the level-0 plane (y = 0)
	"slab_lip": 0.3,            # grass lip: the top band of the side wall; soil below it
	# --- rolling height (levels 1..roll_level_max, from noise; hill_freq / hill_octaves set the noise) ---
	"roll_level_max": 2,
	"roll_from": 0.40,          # noise (0..1) below this stays level 1; above roll_to it reaches roll_level_max (before rounding)
	"roll_to": 0.60,
	"flat_blend": 4.0,          # cells over which height blends to level 1 around every room / corridor cell (smoothstep)
	# --- biomes (overworld_terrain.gd). Levels below are absolute (meadow rolls 1..roll_level_max) ---
	"meadow_share_min": 0.62,   # meadow is a random share in this range of all land cells; forests fill what the massifs leave
	"meadow_share_max": 0.68,
	# --- massifs (overworld_terrain.gd): rock masses that rise from a wide base ---
	"slab_extra_east": 7.0,     # extra slab margin on the boss (east) side, so the main range can be 8-12 cells deep clear of the boss room
	"massif_clear": 4.0,        # no massif cell within this distance of a room or corridor cell (= flat_blend: the blend zone stays free)
	"massif_depth_min": 8,      # main range: a band along the boss edge of the slab, this many cells deep (random in range)
	"massif_depth_max": 12,
	"massif_taper": 6.0,        # the main range's two ends taper over this many cells along the edge
	"massif_small_min": 2,      # smaller massifs elsewhere on the slab
	"massif_small_max": 3,
	"massif_small_r_min": 7.5,  # their base radius, in cells (before the outline noise)
	"massif_small_r_max": 10.0,
	"massif_len_min": 0.75,     # the main range keeps at least this share of the edge length when fitting the rock share
	"massif_small_scale_min": 0.8,   # smallest size factor the small massifs shrink to (below it they would not reach the summit levels)
	"massif_foot_level": 2,     # height at the outer ring of every massif
	"massif_peak_min": 5,       # summit height varies between these (ridged noise)
	"massif_peak_max": 6,
	"massif_step_min": 1.5,     # cells inward per level; the slope is fitted to each massif's depth inside this range
	"massif_step_max": 2.0,
	"massif_freq": 0.09,        # ridged noise (seed ^ NOISE_SALT) for outline and summit
	"massif_octaves": 3,
	"massif_edge_amp": 3.5,     # outline wobble, cells
	"massif_level_noise": 0.8,  # summit wobble, +- levels
	"massif_min_cells": 24,     # a rock patch smaller than this (cut off by the blend zone) is dropped
	"rock_share_min": 0.13,     # share of all cells that is rock; the brief asks 12-18%, this leaves room for the notches below
	"rock_share_max": 0.17,
	"border_max_run": 8,        # no biome border runs straight for more than this many cells
	"forest_count_min": 3,
	"forest_count_max": 5,
	"forest_min_cells": 40,
	"forest_clear": 2.0,        # forest cells are at least this far from a room or corridor cell (never within 1 cell)
	"forest_edge_noise": 3.0,   # raggedness of the region edge, in cells
	"forest_noise_freq": 0.15,
	# --- road tiles and decoration (overworld_decor.gd) ---
	"road_lift": 0.01,          # road tiles sit this far above the block tops (battle HIGHLIGHT_LIFT)
	"decor_margin": 8.0,        # scatter area = layout.bounds grown by this
	"max_slope": 0.7,           # no trees/rocks where the ground is steeper (rise over run)
	"tree_count": 380,          # targets; fewer are placed when the grass runs out
	"tree_radius": 0.65,        # spacing: two things never overlap (radius sum)
	"tree_h_min": 0.2,          # only on grass: ground height between these
	"tree_h_max": 2.0,
	"tree_road_clear": 1.5,
	"tree_node_clear": 3.0,
	"tree_noise_freq": 0.09,    # density noise: clumps and forests
	"tree_dens_from": 0.50,     # noise (0..1) where density starts / is full
	"tree_dens_to": 0.72,
	"tree_base_density": 0.04,  # chance floor outside the clumps (lone trees)
	"tree_scale_min": 0.8,      # scatter still draws these (keeps the rng stream), sprites ignore them
	"tree_scale_max": 1.35,
	"rock_count": 60,
	"rock_radius": 0.8,
	"rock_h_min": 0.2,
	"rock_h_max": 2.4,
	"rock_road_clear": 1.5,
	"rock_node_clear": 3.0,
	"rock_noise_freq": 0.13,
	"rock_dens_from": 0.55,
	"rock_dens_to": 0.80,
	"rock_base_density": 0.03,
	"rock_scale_min": 0.6,
	"rock_scale_max": 1.2,
}
## Slab colours, all shades of gbc_palette colours. Top: meadow green. Lip: the same green, darker (side wall,
## upper band). Soil: the palette's orange pulled dark to a brown (side wall, lower band).
static func grass_top_color() -> Color:
	return Palette.HP_GREEN.darkened(0.25)
static func grass_lip_color() -> Color:
	return grass_top_color().darkened(0.25)
## Ground colour of a cell's top. Meadow alternates two grass tiles (alt = checker parity); forest is a dark
## green; rock is the palette's gray, lighter than its side.
static func top_color(biome: int, alt: bool, level: int = 0) -> Color:
	match biome:
		FOREST:
			return Palette.HP_GREEN.darkened(0.55)
		ROCK:
			return rock_top_color(level)
		_:
			return grass_top_color().lightened(0.12) if alt else grass_top_color()
## Rock top: the palette's gray, lighter the higher the cell stands (massif summits read as pale caps).
const ROCK_LIGHTEN := 0.4             # at ROCK_LIGHTEN_FROM_LEVEL and below
const ROCK_LIGHTEN_FROM_LEVEL := 2
const ROCK_LIGHTEN_PER_LEVEL := 0.1
const ROCK_LIGHTEN_MAX := 0.8
static func rock_top_color(level: int) -> Color:
	var f := ROCK_LIGHTEN + ROCK_LIGHTEN_PER_LEVEL * maxi(level - ROCK_LIGHTEN_FROM_LEVEL, 0)
	return Palette.INK_LIGHT.lightened(minf(f, ROCK_LIGHTEN_MAX))
## Colour of the cliff face below a cell of that biome (meadow: grass lip, as the slab wall's top band).
static func face_color(biome: int) -> Color:
	match biome:
		FOREST:
			return Palette.HP_GREEN.darkened(0.55).darkened(0.25)
		ROCK:
			return Palette.INK_LIGHT
		_:
			return grass_lip_color()
static func soil_color() -> Color:
	return Palette.ARMOR_SHRED.darkened(0.6)
## Map background: the palette's PANEL pulled 30% towards ACCENT. A light blue in the family
## of the battle backdrop (0.70, 0.80, 0.90), built only from palette colours.
static func sea_color() -> Color:
	return Palette.PANEL.lerp(Palette.ACCENT, 0.3)
## --- water (overworld_terrain.gd) ---
## Water top: the palette's ACCENT blue darkened by this share. Darker than the meadow and the sand, and more
## saturated than both, so it survives the PS1 colour-level quantization. Keep the blue channel well ahead of green.
const WATER_DARKEN := 0.4
## Side face of a water block (a step down the river): the water colour darkened by this share.
const WATER_SIDE_DARKEN := 0.35
## Bank lip: the palette's PANEL white pulled this far towards ACCENT. Lighter than every ground colour and than the water.
const BANK_LIP_TINT := 0.15
## Width of the lip strip along the top edge of a bank block that faces water (overworld units, 1 = one block).
const BANK_LIP_WIDTH := 0.18
## The strip sits this far above the block top, under the road tiles (road_lift 0.01), so neither z-fights.
const BANK_LIP_LIFT := 0.005
## Flat top colour of a water cell. The terrain draws it unshaded with no baked light and no checker.
static func water_color() -> Color:
	return Palette.ACCENT.darkened(WATER_DARKEN)
static func water_side_color() -> Color:
	return water_color().darkened(WATER_SIDE_DARKEN)
## Light shoreline colour of a bank block (the strip on its top edge and its face turned to the water).
static func bank_lip_color() -> Color:
	return Palette.PANEL.lerp(Palette.ACCENT, BANK_LIP_TINT)
## Road tile colour: the battle's sand block (height_2) top colour.
static func road_color() -> Color:
	return TerrainTiles.TILES[2]["color"]
## A road the player can take: the battle's blue "where you can walk" highlight laid over the sand tile,
## with the highlight's own alpha, the way the battle draws it.
static func road_option_color() -> Color:
	var hl: Color = BattleView.HL_REACH
	return road_color().lerp(Color(hl.r, hl.g, hl.b), hl.a)
## A road already walked: the palette's dark "spent" gray (the battle's movement-preview colour) over the sand.
static func road_walked_color() -> Color:
	return road_color().lerp(Palette.SPENT_PREVIEW, 0.6)
