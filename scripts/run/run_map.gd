extends RefCounted
## The run's branching map: plain data, no nodes, no rendering. Built by map_generator.gd.
## Node ids are indexes into `nodes`; ids ascend layer by layer.

enum NodeType { BATTLE, ELITE, CAMPFIRE, SHOP, BOSS }

class MapNode extends RefCounted:
	var id := 0
	var layer := 0
	## Column 0..COLUMNS-1, left to right.
	var col := 0
	## A NodeType value.
	var type := 0
	## Ids of the nodes this one links to in the next layer.
	var next_ids: Array[int] = []
	## Layout offset in column/layer units, rolled once at generation.
	var pos_jitter := Vector2.ZERO
	## Shop nodes only: entries {item, price, sold}, rolled on the first visit and kept so a reopened shop matches.
	var shop_stock: Array = []

## layers[l] = Array[int] of the node ids in layer l, left to right. The last entry is the boss layer.
var layers: Array = []
var nodes: Array[MapNode] = []
var boss_id := -1

## Every node reachable by following links from `node_id`, excluding itself, ascending.
func reachable_from(node_id: int) -> Array[int]:
	var seen := {}
	var stack: Array[int] = [node_id]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		for n in nodes[cur].next_ids:
			if not seen.has(n):
				seen[n] = true
				stack.append(n)
	var out: Array[int] = []
	for k in seen.keys():
		out.append(k)
	out.sort()
	return out
