extends RefCounted
## Shop rules: stock, prices, buying. Pure logic, no nodes. Stock is rolled once per shop node
## and kept on MapNode.shop_stock, so reopening the shop shows the same goods.

const Inventory = preload("res://scripts/inventory/inventory.gd")
const Item = preload("res://scripts/inventory/item.gd")
const Loot = preload("res://scripts/run/loot.gd")
const RunMap = preload("res://scripts/run/run_map.gd")
const RunTuning = preload("res://scripts/run/run_tuning.gd")

static func price_of(item: Item) -> int:
	var rarity := int(item.get_meta("rarity", 0))
	return roundi(RunTuning.SLOT_BASE_PRICE[item.item_type] * RunTuning.RARITY_PRICE_MULT[rarity])

## The node's stock, rolled from `rng` only the first time.
static func stock_for(node: RunMap.MapNode, rng: RandomNumberGenerator) -> Array:
	if not node.shop_stock.is_empty():
		return node.shop_stock
	for i in RunTuning.SHOP_GEAR_COUNT:
		_add(node, Loot.roll_item(rng, node.layer))
	for i in RunTuning.SHOP_CONSUMABLE_COUNT:
		var path: String = RunTuning.SHOP_CONSUMABLES[i % RunTuning.SHOP_CONSUMABLES.size()]
		_add(node, (load(path) as Item).duplicate() as Item)
	return node.shop_stock

static func _add(node: RunMap.MapNode, item: Item) -> void:
	node.shop_stock.append({"item": item, "price": price_of(item), "sold": false})

static func can_buy(entry: Dictionary, gold: int, bag: Inventory) -> bool:
	return not entry.sold and gold >= entry.price and bag.find_space(entry.item) != Inventory.NO_SPACE

## Adds the item to the bag and returns the gold left. Unchanged gold when the buy is refused.
static func buy(entry: Dictionary, gold: int, bag: Inventory) -> int:
	if not can_buy(entry, gold, bag):
		return gold
	bag.add(entry.item)
	entry.sold = true
	return gold - entry.price
