extends RefCounted
## Builds a RunMap from one RandomNumberGenerator. Same rng state in, same map out (only `rng` is used).
## Numbers live in run_tuning.gd; the two below are generator-only.
## Every layer has one node per column (a layer may drop one column), edges never cross, and each
## layer branches. Layers 0..LAYERS-1 are regular, the boss layer follows.

const RunMap = preload("res://scripts/run/run_map.gd")
const RunTuning = preload("res://scripts/run/run_tuning.gd")

## pos_jitter is rolled in [-JITTER, JITTER] on each axis.
const JITTER := 0.25
const MAX_ATTEMPTS := 10
## At least this many nodes per layer must have two forward edges.
const MIN_BRANCHING := 2

static func generate(rng: RandomNumberGenerator) -> RunMap:
	var map: RunMap = null
	for attempt in MAX_ATTEMPTS:
		map = _generate_once(rng)
		if _validate(map):
			break
		if attempt == MAX_ATTEMPTS - 1:
			push_warning("MapGenerator: map failed validation %d times, using the last one" % MAX_ATTEMPTS)
	# Layout jitter, one roll pair per node in id order.
	for node in map.nodes:
		node.pos_jitter = Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER))
	return map

static func _generate_once(rng: RandomNumberGenerator) -> RunMap:
	var last := RunTuning.LAYERS - 1

	# 1. Columns present in each layer.
	var layer_cols: Array = []
	for l in RunTuning.LAYERS:
		var cols: Array[int] = []
		for c in RunTuning.COLUMNS:
			cols.append(c)
		var forced_full := l == 0 or RunTuning.CAMPFIRE_LAYERS.has(l)
		if not forced_full and rng.randf() >= RunTuning.FULL_LAYER_CHANCE:
			cols.remove_at(rng.randi() % cols.size())
		layer_cols.append(cols)

	# 2. Edges, layer by layer. edges[l] = Array[Vector2i(from_col, to_col)] into layer l+1.
	var edges: Array = []
	for l in last:
		edges.append(_edges_between(layer_cols[l], layer_cols[l + 1], rng))

	# 3. Nodes and links.
	var map := RunMap.new()
	var id_at := {}  # Vector2i(layer, col) -> id
	for l in layer_cols.size():
		var ids: Array[int] = []
		for c in layer_cols[l]:
			var node := RunMap.MapNode.new()
			node.id = map.nodes.size()
			node.layer = l
			node.col = c
			id_at[Vector2i(l, c)] = node.id
			map.nodes.append(node)
			ids.append(node.id)
		map.layers.append(ids)
	var boss := RunMap.MapNode.new()
	boss.id = map.nodes.size()
	boss.layer = RunTuning.BOSS_LAYER
	boss.col = (RunTuning.COLUMNS - 1) >> 1
	boss.type = RunMap.NodeType.BOSS
	map.nodes.append(boss)
	map.layers.append([boss.id] as Array[int])
	map.boss_id = boss.id
	for l in last:
		for e: Vector2i in edges[l]:
			(map.nodes[id_at[Vector2i(l, e.x)]] as RunMap.MapNode).next_ids.append(id_at[Vector2i(l + 1, e.y)])
	for id in map.layers[last]:
		map.nodes[id].next_ids.append(boss.id)

	# 4. Types.
	for l in RunTuning.LAYERS:
		_assign_types(map, l, rng)
	return map

# --- edges -------------------------------------------------------------------------------

static func _nearest(cols: Array, c: int) -> int:
	var best: int = cols[0]
	for x: int in cols:
		if absi(x - c) < absi(best - c):
			best = x
	return best

## a->b and c->d cross when (a_col - c_col) * (b_col - d_col) < 0.
static func _crosses(edges: Array, a: int, b: int) -> bool:
	for e: Vector2i in edges:
		if (a - e.x) * (b - e.y) < 0:
			return true
	return false

static func _add_edge(edges: Array, a: int, b: int) -> bool:
	if edges.has(Vector2i(a, b)) or _crosses(edges, a, b):
		return false
	edges.append(Vector2i(a, b))
	return true

static func _out_count(edges: Array, a: int) -> int:
	var n := 0
	for e: Vector2i in edges:
		if e.x == a:
			n += 1
	return n

static func _edges_between(from_cols: Array, to_cols: Array, rng: RandomNumberGenerator) -> Array:
	var edges: Array = []
	# a. One forward edge per node: same column 50%, each neighbour 25%. Left to right, never below
	# the highest target so far, so nothing crosses.
	var floor_col := 0
	for c: int in from_cols:
		var r := rng.randf()
		var want := c if r < 0.5 else (c - 1 if r < 0.75 else c + 1)
		var allowed: Array[int] = []
		for x: int in to_cols:
			if x >= floor_col:
				allowed.append(x)
		var pick := _nearest(allowed, want)
		_add_edge(edges, c, pick)
		floor_col = pick
	# b. Every target with no incoming edge gets one from the nearest source that does not cross.
	for t: int in to_cols:
		var has_in := false
		for e: Vector2i in edges:
			if e.y == t:
				has_in = true
		if has_in:
			continue
		var order: Array[int] = []
		order.assign(from_cols)
		order.sort_custom(func(x: int, y: int) -> bool:
			return absi(x - t) < absi(y - t) or (absi(x - t) == absi(y - t) and x < y))
		for s in order:
			if _add_edge(edges, s, t):
				break
	# c. Second edge to a neighbouring column with EXTRA_EDGE_CHANCE.
	for c: int in from_cols:
		if _out_count(edges, c) == 1 and rng.randf() < RunTuning.EXTRA_EDGE_CHANCE:
			_try_second_edge(edges, c, to_cols, rng)
	# Guarantee MIN_BRANCHING nodes with two edges.
	var two := 0
	for c: int in from_cols:
		if _out_count(edges, c) >= 2:
			two += 1
	if two < MIN_BRANCHING:
		var singles: Array[int] = []
		for c: int in from_cols:
			if _out_count(edges, c) == 1:
				singles.append(c)
		_shuffle(singles, rng)
		for c in singles:
			if two >= MIN_BRANCHING:
				break
			if _try_second_edge(edges, c, to_cols, rng):
				two += 1
	return edges

static func _try_second_edge(edges: Array, c: int, to_cols: Array, rng: RandomNumberGenerator) -> bool:
	var opts: Array[int] = []
	for t in [c - 1, c, c + 1]:
		if to_cols.has(t):
			opts.append(t)
	_shuffle(opts, rng)
	for t in opts:
		if _add_edge(edges, c, t):
			return true
	return false

static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp

# --- types -------------------------------------------------------------------------------

static func _assign_types(map: RunMap, l: int, rng: RandomNumberGenerator) -> void:
	var ids: Array = map.layers[l]
	if l == 0:
		for id in ids:
			map.nodes[id].type = RunMap.NodeType.BATTLE
	elif l == RunTuning.LAYERS - 1:
		for id in ids:
			map.nodes[id].type = RunMap.NodeType.CAMPFIRE
	elif RunTuning.CAMPFIRE_LAYERS.has(l):
		var fires := 0
		for id in ids:
			var t: int = RunMap.NodeType.BATTLE
			if rng.randf() < RunTuning.CAMPFIRE_LAYER_CHANCE:
				t = RunMap.NodeType.CAMPFIRE
				fires += 1
			map.nodes[id].type = t
		if fires < 2:
			var spare: Array = []
			for id in ids:
				if map.nodes[id].type != RunMap.NodeType.CAMPFIRE:
					spare.append(id)
			_shuffle(spare, rng)
			for id in spare:
				if fires >= 2:
					break
				map.nodes[id].type = RunMap.NodeType.CAMPFIRE
				fires += 1
	else:
		var elites := 0
		var shops := 0
		for id in ids:
			var types: Array[int] = [RunMap.NodeType.BATTLE]
			var weights: Array[int] = [RunTuning.WEIGHT_BATTLE]
			if l >= RunTuning.ELITE_MIN_LAYER and elites < 1:
				types.append(RunMap.NodeType.ELITE)
				weights.append(RunTuning.WEIGHT_ELITE)
			if l >= RunTuning.SHOP_MIN_LAYER and shops < 1:
				types.append(RunMap.NodeType.SHOP)
				weights.append(RunTuning.WEIGHT_SHOP)
			var total := 0
			for w in weights:
				total += w
			var roll := int(rng.randi() % total)
			var pick: int = types[0]
			for i in types.size():
				roll -= weights[i]
				if roll < 0:
					pick = types[i]
					break
			if pick == RunMap.NodeType.ELITE:
				elites += 1
			elif pick == RunMap.NodeType.SHOP:
				shops += 1
			map.nodes[id].type = pick

# --- validation --------------------------------------------------------------------------

static func _validate(map: RunMap) -> bool:
	var last := RunTuning.LAYERS - 1
	var has_in := {}
	for l in RunTuning.LAYERS:
		var ids: Array = map.layers[l]
		if ids.size() < 3 or ids.size() > RunTuning.COLUMNS:
			return false
		if l == 0 and ids.size() != RunTuning.COLUMNS:
			return false
		var seen: Array[Vector2i] = []
		for id in ids:
			var n: RunMap.MapNode = map.nodes[id]
			if n.next_ids.is_empty():
				return false
			for nid in n.next_ids:
				has_in[nid] = true
				var m: RunMap.MapNode = map.nodes[nid]
				if l == last:
					if nid != map.boss_id:
						return false
					continue
				if m.layer != l + 1:
					return false
				for e in seen:
					if (n.col - e.x) * (m.col - e.y) < 0:
						return false
				seen.append(Vector2i(n.col, m.col))
	for l in range(1, RunTuning.LAYERS):
		for id in map.layers[l]:
			if not has_in.has(id):
				return false
	return has_in.has(map.boss_id)
