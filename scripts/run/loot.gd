extends RefCounted
## Gear rolls and gold for a won encounter. Static, pure logic, every roll comes from the rng you pass in.
## The base items in data/items/*.tres are never touched: a roll works on a duplicate().
## Item has no rarity field, so the rolled rarity is kept as metadata on the copy: item.get_meta("rarity").

const Ability = preload("res://scripts/battle/ability.gd")
const Item = preload("res://scripts/inventory/item.gd")
const RunMap = preload("res://scripts/run/run_map.gd")
const RunTuning = preload("res://scripts/run/run_tuning.gd")

enum Rarity { COMMON, UNCOMMON, RARE }
const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare"]

## Rarity weights [common, uncommon, rare] at depth 0 and at the boss layer. Linear in between.
const ODDS_SHALLOW: Array[float] = [80.0, 18.0, 2.0]
const ODDS_DEEP: Array[float] = [30.0, 45.0, 25.0]
## Flat bonus per rarity: to every defense pool the base item already has, and to a damaging weapon's damage_bonus.
const DEFENSE_BONUS: Array[int] = [0, 2, 5]
const DAMAGE_BONUS: Array[int] = [0, 1, 3]

## An elite or boss rolls as if it sat this many layers deeper.
const ELITE_RARITY_BONUS := 3
const BOSS_RARITY_BONUS := 6
const BOSS_ROLLS := 3

const ITEMS_DIR := "res://data/items"

static var _bases: Array[Item] = []

## Every non-consumable base item, sorted by path so the same rng gives the same pick.
static func base_items() -> Array[Item]:
	if not _bases.is_empty():
		return _bases
	var files: Array[String] = []
	for f in DirAccess.get_files_at(ITEMS_DIR):
		var file := f.trim_suffix(".remap")  # exported builds list resources as <n>.tres.remap
		if file.ends_with(".tres"):
			files.append(file)
	files.sort()
	for file in files:
		var item := load("%s/%s" % [ITEMS_DIR, file]) as Item
		if item != null and item.item_type != Item.ItemType.CONSUMABLE:
			_bases.append(item)
	return _bases

## A Rarity value. `rarity_bonus` counts as extra layers of depth.
static func roll_rarity(rng: RandomNumberGenerator, layer: int, rarity_bonus: int = 0) -> int:
	var t := clampf(float(layer + rarity_bonus) / RunTuning.BOSS_LAYER, 0.0, 1.0)
	var weights: Array[float] = []
	var total := 0.0
	for i in RARITY_NAMES.size():
		weights.append(lerpf(ODDS_SHALLOW[i], ODDS_DEEP[i], t))
		total += weights[i]
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll < 0.0:
			return i
	return weights.size() - 1

static func roll_item(rng: RandomNumberGenerator, layer: int, rarity_bonus: int = 0) -> Item:
	var bases := base_items()
	var base: Item = bases[rng.randi() % bases.size()]
	var rarity := roll_rarity(rng, layer, rarity_bonus)
	var item := base.duplicate() as Item
	var defense: int = DEFENSE_BONUS[rarity]
	if item.physical_armor > 0:
		item.physical_armor += defense
	if item.magic_barrier > 0:
		item.magic_barrier += defense
	if item.physical_armor == 0 and item.magic_barrier == 0 and not item.is_weapon():
		item.magic_barrier = defense  # a bare ring or amulet gains a barrier
	var damage: int = DAMAGE_BONUS[rarity]
	if damage > 0 and item.ability != null and not item.ability.damage_dice.is_empty():
		var ability := item.ability.duplicate() as Ability  # the base's Ability stays as it was
		ability.damage_bonus += damage
		item.ability = ability
	item.display_name = "%s %s" % [RARITY_NAMES[rarity], base.display_name]
	item.set_meta("rarity", rarity)
	return item

## Gold for winning at `node`: battle 15-25 + 5 per layer, elite x2, boss flat.
static func gold_for(node: RunMap.MapNode, rng: RandomNumberGenerator) -> int:
	if node.type == RunMap.NodeType.BOSS:
		return RunTuning.BOSS_GOLD
	var gold := rng.randi_range(RunTuning.BATTLE_GOLD_MIN, RunTuning.BATTLE_GOLD_MAX) + RunTuning.GOLD_PER_LAYER * node.layer
	if node.type == RunMap.NodeType.ELITE:
		gold *= RunTuning.ELITE_GOLD_MULT
	return gold

static func rolls_for(node: RunMap.MapNode) -> int:
	return BOSS_ROLLS if node.type == RunMap.NodeType.BOSS else RunTuning.REWARD_ITEMS

static func rarity_bonus_for(node: RunMap.MapNode) -> int:
	match node.type:
		RunMap.NodeType.ELITE:
			return ELITE_RARITY_BONUS
		RunMap.NodeType.BOSS:
			return BOSS_RARITY_BONUS
	return 0
