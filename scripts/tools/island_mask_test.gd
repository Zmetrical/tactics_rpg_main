extends SceneTree
## Headless check for steps 2a-2 / 2a-3: godot --headless -s res://scripts/tools/island_mask_test.gd [-- <first seed> <count>]
## Default: seeds 1..20. Per seed: build twice (hash must match), the flood fill must find exactly one island,
## no spur cells, is_land meta set and consistent. Neighbouring seeds must differ clearly. Saves the black/white
## mask PNGs under user:// (OverworldDebugConfig).
const Mask = preload("res://scripts/run/overworld/island_mask.gd")
const Debug = preload("res://scripts/run/overworld/overworld_debug.gd")
const Config = preload("res://data/run/overworld_debug_config.gd")
const MIN_DIFF := 0.10

func _init() -> void:
	var first := 1
	var count := 20
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0].is_valid_int() and args[1].is_valid_int():
		first = int(args[0])
		count = maxi(int(args[1]), 2)
	var fail := 0
	var one_island := 0
	var prev = null
	var min_diff := 1.0
	var total_ms := 0.0
	for s in range(first, first + count):
		var builder := func(sd: int) -> String:
			return Mask.build(sd).content_hash()
		var det: bool = Debug.determinism_check("island_mask seed %d" % s, builder, s)["ok"]
		var m = Mask.build(s)
		var b: Rect2i = m.bbox()
		var bodies: int = m.component_count()
		var spurs: int = m.spur_cells()
		var ms := 0.0
		for t in m.timings:
			ms += float(t["ms"])
		total_ms += ms
		var probe := Node.new()
		m.apply_meta(probe)
		var meta_ok: bool = probe.get_meta("nx", 0) == m.nx and probe.get_meta("nz", 0) == m.nz \
				and (probe.get_meta("land") as PackedByteArray).size() == m.nx * m.nz \
				and int(probe.get_meta("land_count")) == m.land_count and m.land_count > 0
		for cell in [Vector2i(0, 0), Vector2i(-1, 5), Vector2i(m.nx, 0), Vector2i(m.nx / 2, m.nz / 2)]:
			if m.is_land_cell(cell) != m.is_land(cell.x, cell.y):
				meta_ok = false
		probe.free()
		var ok: bool = det and bodies == 1 and spurs == 0 and meta_ok
		print("[island] seed %3d: land %4d, bbox %dx%d, fill %4.1f%%, islands %d, spurs %d, rounds %d, meta %s, %.1f ms %s" % [
			s, m.land_count, b.size.x, b.size.y, m.fill_percent(), bodies, spurs, m.clean_rounds,
			"ok" if meta_ok else "BAD", ms, "" if ok else "FAIL"])
		if bodies == 1:
			one_island += 1
		if not ok:
			fail += 1
		if prev != null:
			min_diff = minf(min_diff, m.difference(prev))
		prev = m
		if Config.SAVE_ISLAND_MASK_PNG:
			var img: Image = m.to_image()
			img.resize(m.nx * Config.ISLAND_MASK_PNG_SCALE, m.nz * Config.ISLAND_MASK_PNG_SCALE, Image.INTERPOLATE_NEAREST)
			img.save_png("user://island_mask_%d.png" % s)
	print("[island] exactly one island on %d / %d seeds; smallest difference between neighbouring seeds %.1f%% (need >= %.0f%%); %.1f ms per mask" % [
		one_island, count, min_diff * 100.0, MIN_DIFF * 100.0, total_ms / float(count)])
	print("[island] PNGs in %s" % ProjectSettings.globalize_path("user://"))
	if min_diff < MIN_DIFF:
		fail += 1
	print("[island] mask test %s" % ("PASS" if fail == 0 else "FAIL"))
	quit(fail)
