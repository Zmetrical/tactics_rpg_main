extends RefCounted
## Static cache of built overworld results keyed by seed. The map scene reloads after every arrival, so a
## slow build must not rerun per node. Values are opaque to the cache (a built bundle). Not a node.
const Config = preload("res://data/run/overworld_debug_config.gd")

static var _items := {}          # seed -> value
static var _order: Array[int] = []   # insertion order, oldest first

static func has_seed(seed: int) -> bool:
	return _items.has(seed)

static func get_seed(seed: int) -> Variant:
	return _items.get(seed)

static func put(seed: int, value: Variant) -> void:
	if not _items.has(seed):
		_order.append(seed)
	_items[seed] = value
	while _order.size() > Config.CACHE_MAX:
		_items.erase(_order.pop_front())

static func clear() -> void:
	_items.clear()
	_order.clear()
