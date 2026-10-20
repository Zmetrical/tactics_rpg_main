extends RefCounted
## Phase harness: per-stage timing, content hash, double-build determinism check, debug layer enum.
## Pure logic, no nodes. Every later phase calls stage_begin / stage_end around its stages and
## determinism_check at the end of its build.
const Config = preload("res://data/run/overworld_debug_config.gd")

## One debug layer per phase. View code reads this and shows only that layer (ALL = normal view).
enum Layer { ALL, TERRAIN, SITES, PATHS, MESH, PROPS, LOOK }

var layer: int = Layer.ALL
var timings: Array[Dictionary] = []   # [{name, ms}] in call order
var _open := {}                       # name -> start usec

func stage_begin(stage_name: String) -> void:
	_open[stage_name] = Time.get_ticks_usec()

func stage_end(stage_name: String) -> float:
	var t0: int = _open.get(stage_name, Time.get_ticks_usec())
	_open.erase(stage_name)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	timings.append({"name": stage_name, "ms": ms})
	if Config.PRINT_TIMING:
		print("[overworld] %-24s %8.1f ms" % [stage_name, ms])
	return ms

func total_ms() -> float:
	var s := 0.0
	for t in timings:
		s += float(t["ms"])
	return s

func print_summary(label: String) -> void:
	var over := total_ms() > Config.BUDGET_MS
	print("[overworld] %s total %.1f ms (budget %.0f ms)%s" % [label, total_ms(), Config.BUDGET_MS, "  OVER BUDGET" if over else ""])

## SHA-256 hex of any Variant. Arrays keep order; Dictionaries keep insertion order, so the caller
## must insert in sorted-key order (or use hash_dict_sorted).
static func hash_variant(v: Variant) -> String:
	return hash_bytes(var_to_bytes(v))

static func hash_bytes(b: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode()

## Hash of a Dictionary independent of insertion order: keys sorted first.
static func hash_dict_sorted(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	var flat: Array = []
	for k in keys:
		flat.append(k)
		flat.append(d[k])
	return hash_variant(flat)

## Build twice with the same seed and compare hashes. `builder` is Callable(seed:int) -> String (hash of
## its outputs). Returns {ok, hash_a, hash_b}. Prints a one-line verdict.
static func determinism_check(label: String, builder: Callable, seed: int) -> Dictionary:
	var a: String = builder.call(seed)
	var b: String = builder.call(seed)
	var ok := a == b
	if ok:
		print("[overworld] determinism %s OK %s" % [label, a.substr(0, 12)])
	else:
		push_error("[overworld] determinism %s FAILED %s != %s" % [label, a.substr(0, 12), b.substr(0, 12)])
	return {"ok": ok, "hash_a": a, "hash_b": b}

## Hash of the OverworldLayout contract fields (rooms, node_pos, roads, failed, bounds), keys sorted.
static func hash_layout(layout: RefCounted) -> String:
	var rooms_ids: Array = layout.rooms.keys()
	rooms_ids.sort()
	var rooms_flat: Array = []
	for id in rooms_ids:
		rooms_flat.append([id, layout.rooms[id], layout.node_pos.get(id)])
	var roads_flat: Array = []
	for r in layout.roads:
		roads_flat.append([r["from_id"], r["to_id"], r["cells"]])
	return hash_variant([rooms_flat, roads_flat, layout.failed, layout.bounds])

## Hash of the OverworldTerrain.Terrain data arrays.
static func hash_terrain(t: Node) -> String:
	return hash_variant([t.x0, t.z0, t.nx, t.nz, t.land, t.levels, t.biomes, t.water, t.ridge, t.region_ids, t.region_names])
