extends RefCounted
## Turns a map node into battle settings. Pure data, no nodes, no rendering.
## Shared .tres files are never touched: the biome is duplicated, and enemy stats are scaled on the
## Unit after it is built (a duplicated UnitData has no resource_path, and stage_3d.gd picks the
## sprite from that path).

const BiomeData = preload("res://scripts/battle/biome_data.gd")
const MapLoader = preload("res://scripts/battle/map_loader.gd")
const RunMap = preload("res://scripts/run/run_map.gd")
const Unit = preload("res://scripts/battle/unit.gd")

const BIOMES := {
	"plains": "res://data/biomes/plains.tres",
	"forest": "res://data/biomes/forest.tres",
	"ridge": "res://data/biomes/ridge.tres",
}
const PLAINS_LAST_LAYER := 2
const FOREST_LAST_LAYER := 5
const SIZES: Array[String] = ["large", "medium", "small"]
const SMALL_LAST_LAYER := 2

const BOSS_UNIT := "res://data/units/orc_warlord.tres"
const BOSS_MAP := "res://scenes/maps/ridge/large/spine.tscn"
## Enemies next to the warlord.
const BOSS_ESCORTS := 2

## Enemy stats grow per layer of depth.
const HP_PER_LAYER := 0.12
const LAYERS_PER_AC := 3
const LAYERS_PER_EXTRA_ENEMY := 3
## An elite fights as if it sat this many layers deeper.
const ELITE_DEPTH_BONUS := 3

## -> {biome_path, map_size, enemy_scale, force_map_path, is_boss}
## enemy_scale = {hp_mult, ac_bonus, extra_enemies, boss}. force_map_path is "" unless it is the boss.
## `rng` is unused for now: every choice here is a function of the node.
static func build(node: RunMap.MapNode, _rng: RandomNumberGenerator) -> Dictionary:
	var is_boss := node.type == RunMap.NodeType.BOSS
	var is_elite := node.type == RunMap.NodeType.ELITE
	var biome_name := "plains"
	if node.layer > FOREST_LAST_LAYER:
		biome_name = "ridge"
	elif node.layer > PLAINS_LAST_LAYER:
		biome_name = "forest"

	var wanted := "small" if node.layer <= SMALL_LAST_LAYER else "medium"
	if is_elite or is_boss:
		wanted = "large"
	# Not every biome has every size (only ridge has large); fall back to the next smaller one.
	var size := wanted
	for i in range(SIZES.find(wanted), SIZES.size()):
		if not MapLoader.list_maps(biome_name, SIZES[i]).is_empty():
			size = SIZES[i]
			break

	var depth := node.layer + (ELITE_DEPTH_BONUS if is_elite else 0)
	return {
		"biome_path": BIOMES[biome_name],
		"map_size": size,
		"enemy_scale": {
			"hp_mult": 1.0 + HP_PER_LAYER * depth,
			"ac_bonus": floori(float(depth) / LAYERS_PER_AC),
			"extra_enemies": floori(float(depth) / LAYERS_PER_EXTRA_ENEMY),
			"boss": is_boss,
		},
		"force_map_path": BOSS_MAP if is_boss else "",
		"is_boss": is_boss,
	}

## A duplicate of `biome` with the enemy count raised (or, for the boss, the warlord first). The roster is
## the list of shared UnitData the biome already uses; it is only re-ordered or repeated, never edited.
static func scaled_biome(biome: BiomeData, enemy_scale: Dictionary) -> BiomeData:
	var b := biome.duplicate() as BiomeData
	var roster: Array[Resource] = []
	roster.assign(biome.enemy_roster)
	if enemy_scale["boss"]:
		roster.insert(0, load(BOSS_UNIT))
		b.enemy_count_min = 1 + BOSS_ESCORTS
		b.enemy_count_max = b.enemy_count_min
	else:
		var extra: int = enemy_scale["extra_enemies"]
		b.enemy_count_min = biome.enemy_count_min + extra
		b.enemy_count_max = biome.enemy_count_max + extra
		var i := 0
		while roster.size() < b.enemy_count_max:  # the first N roster entries spawn, so lengthen it
			roster.append(biome.enemy_roster[i % biome.enemy_roster.size()])
			i += 1
	b.enemy_roster = roster
	return b

## Scales one freshly built enemy Unit. The warlord is already tuned as the boss.
static func scale_enemy(u: Unit, enemy_scale: Dictionary) -> void:
	if u.data.resource_path == BOSS_UNIT:
		return
	u.max_hp = maxi(1, roundi(u.max_hp * float(enemy_scale["hp_mult"])))
	u.hp = u.max_hp
	u.ac += int(enemy_scale["ac_bonus"])
