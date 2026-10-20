extends SceneTree
## Headless check: godot --headless -s res://scripts/tools/overworld_harness_check.gd [-- <seed>]
## Runs the legacy pipeline twice with one seed and compares layout and terrain hashes, prints per-stage
## timing, runs the palette grayscale gate and a VoxelGrid hash self-test.
const Debug = preload("res://scripts/run/overworld/overworld_debug.gd")
const Grid = preload("res://scripts/run/overworld/voxel_grid.gd")
const Cache = preload("res://scripts/run/overworld/overworld_cache.gd")
const Palette = preload("res://data/run/overworld_palette.gd")
const Layout = preload("res://scripts/run/overworld_layout.gd")
const Terrain = preload("res://scripts/run/overworld_terrain.gd")
const MapGen = preload("res://scripts/run/map_generator.gd")

func _init() -> void:
	var seed := 12345
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		seed = int(args[0])
	var dbg := Debug.new()
	var fail := 0
	var build_hash := func(s: int) -> String:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var map = MapGen.generate(rng)
		dbg.stage_begin("layout")
		var lay = Layout.build(map, s)
		dbg.stage_end("layout")
		dbg.stage_begin("terrain")
		var ter = Terrain.build(lay, s)
		dbg.stage_end("terrain")
		var h := Debug.hash_variant([Debug.hash_layout(lay), Debug.hash_terrain(ter)])
		ter.free()
		return h
	if not Debug.determinism_check("legacy layout+terrain", build_hash, seed)["ok"]:
		fail += 1
	dbg.print_summary("legacy (2 builds)")
	var g := func(s: int) -> String:
		var grid := Grid.new(8, 8)
		for i in 8:
			grid.set_column(i, (i * 7 + s) % 8, 0, 3 + i, 1)
		return grid.content_hash()
	if not Debug.determinism_check("voxel_grid", g, seed)["ok"]:
		fail += 1
	Cache.put(1, "a")
	Cache.put(2, "b")
	Cache.put(3, "c")
	if Cache.has_seed(1) or not Cache.has_seed(3):
		push_error("cache eviction wrong")
		fail += 1
	if not Palette.grayscale_gate():
		print("[palette] gate FAILED: retune ramps in overworld_palette.gd")
	print("[overworld] harness check %s" % ("PASS" if fail == 0 else "FAIL"))
	quit(fail)
