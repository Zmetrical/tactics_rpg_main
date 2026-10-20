extends RefCounted
## Every tunable number of the run loop. Consts only.

# --- Map ---
const LAYERS := 8              # layers 0-7, plus the boss layer after them
const BOSS_LAYER := 8
const COLUMNS := 4
## Chance a layer keeps all COLUMNS nodes; otherwise one random column is dropped.
## Layer 0 and the CAMPFIRE_LAYERS are always full.
const FULL_LAYER_CHANCE := 0.8
## Chance a node with one forward edge gets a second one.
const EXTRA_EDGE_CHANCE := 0.65
## Layers that are mostly campfires (the last layer is all campfire). Nowhere else has campfires.
const CAMPFIRE_LAYERS: Array[int] = [3, 7]
const CAMPFIRE_LAYER_CHANCE := 0.75

# Node weights for the other layers. MIN_LAYER = first layer the type may appear on; max 1 elite and 1 shop per layer.
const WEIGHT_BATTLE := 70
const WEIGHT_ELITE := 15
const WEIGHT_SHOP := 15
const ELITE_MIN_LAYER := 4
const SHOP_MIN_LAYER := 2

# --- Economy ---
const START_GOLD := 50
const BATTLE_GOLD_MIN := 20
const BATTLE_GOLD_MAX := 30
const GOLD_PER_LAYER := 5
const ELITE_GOLD_MULT := 2
const BOSS_GOLD := 100
const REWARD_ITEMS := 2
const SHOP_GEAR_COUNT := 5
const SHOP_CONSUMABLE_COUNT := 2
const SHOP_CONSUMABLES: Array[String] = [
	"res://data/items/health_potion.tres",
	"res://data/items/mana_potion.tres",
]
## Base price by slot, indexed by Item.ItemType (WEAPON, HEAD, TORSO, LEGS, BRACE, RING, AMULET, CONSUMABLE).
const SLOT_BASE_PRICE: Array[int] = [30, 18, 25, 18, 10, 22, 22, 10]
## Price multiplier by Loot.Rarity (COMMON, UNCOMMON, RARE).
const RARITY_PRICE_MULT: Array[float] = [1.0, 1.5, 2.2]

# --- Recovery ---
const CAMPFIRE_HEAL := 0.4    # fraction of max HP
const REVIVE_HP := 1

# --- Starting party (same units battle_view.gd PLAYER_UNITS uses) ---
const STARTING_PARTY: Array[String] = [
	"res://data/units/fighter.tres",
	"res://data/units/mage.tres",
	"res://data/units/ranger.tres",
]

# --- Map layout (grid cells; see map_layout.gd) ---
## Footprint by RunMap.NodeType (BATTLE, ELITE, CAMPFIRE, SHOP, BOSS).
const ROOM_SIZES: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(4, 4), Vector2i(2, 2), Vector2i(3, 3), Vector2i(6, 6),
]
## Layer -> grid X, column -> grid Z.
const LAYER_STEP := 12
const COL_STEP := 9
## MapNode.pos_jitter, rounded to whole cells, clamped to +-this.
const ROOM_JITTER_CELLS := 2
## Empty cells kept between any two room footprints.
const ROOM_MARGIN := 2
const CORRIDOR_TURN_COST := 0.5
## Roads keep this many empty cells from every room that is not one of their two ends (hard block).
const ROAD_ROOM_CLEARANCE := 1
## Roads keep this many empty cells from every earlier road, except roads that share an end room with
## them (fan-out). Fallback a routes with 0 (touching, never sharing a cell).
const ROAD_CORRIDOR_CLEARANCE := 1
## Fallback b only: extra cost per cell of another road that is crossed (drawn as an ordinary flat road).
const ROAD_CROSS_COST := 20.0
## A* search box = both rooms grown by this many cells.
const CORRIDOR_SEARCH_PAD := 8
## Starting platform (room id -1): footprint, and empty cells between its far edge and the nearest
## layer-0 room on grid X. Centered on the layer-0 rooms' average Z.
const START_SIZE := Vector2i(2, 2)
const START_GAP := 8

# --- Overworld layout (grid cells, see overworld_layout.gd) ---
# Room footprints (ROOM_SIZES), START_SIZE, START_GAP, ROOM_MARGIN, CORRIDOR_TURN_COST, ROAD_ROOM_CLEARANCE and
# CORRIDOR_SEARCH_PAD above are shared with map_layout.gd.
## Layer -> X, column -> Z, in cells. Rounded to whole cells when rooms are placed.
const LAYER_SPACING := 12.0
const COL_SPACING := 10.0
## Room position jitter on each axis, whole cells +-this. Keep it well below COL_SPACING / 2.
const JITTER := 1
## A cell 4-adjacent to another corridor costs this much extra in the corridor A* (corridors never share cells).
const CORRIDOR_NEAR_COST := 3.0
## A cell right outside another room's border (a room that is not one of the road's two ends) costs this much extra, so
## roads keep off the lanes in front of doors.
const CORRIDOR_ROOM_NEAR_COST := 3.0
## Fallback only: when no route exists without sharing a cell, a road may cross another corridor's cell at this extra cost.
const CORRIDOR_CROSS_COST := 20.0
## When an edge cannot be routed the layout is rebuilt with LAYER_SPACING and COL_SPACING raised by
## SPACING_RETRY_STEP, at most SPACING_RETRIES times.
const SPACING_RETRY_STEP := 1.0
const SPACING_RETRIES := 6
## Salt xored into the run seed for the overworld rng.
const OVERWORLD_SEED_SALT := 0xA11CE

# --- Overworld node markers (see run_map_view.gd) ---
## Pad radius by RunMap.NodeType (BATTLE, ELITE, CAMPFIRE, SHOP, BOSS); must stay under the terrain's node flat radius (2.0).
const PAD_RADIUS: Array[float] = [1.2, 1.4, 1.0, 1.2, 1.9]
const START_PAD_RADIUS := 1.1
const PAD_HEIGHT := 0.1
const CAMPFIRE_LIGHT_RANGE := 4.0
const CAMPFIRE_LIGHT_ENERGY := 1.6
