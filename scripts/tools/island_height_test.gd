extends SceneTree
## Headless check for step 2a-4: godot --headless -s res://scripts/tools/island_height_test.gd [-- <first seed> <count>]
## Default seeds 1..20. Per seed: mask + base height, build twice (hash must match), validate() (meta levels / min /
## max, heights in range, every land neighbour pair differs by 0 or 3-6 voxels). Saves the height colour ramp PNGs
## under user:// (OverworldDebugConfig).
const Mask = preload("res://scripts/run/overworld/island_mask.gd")
const Height = preload("res://scripts/run/overworld/island_height.gd")
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
	var prev = null
	var min_diff := 1.0
	var total_ms := 0.0
	for s in range(first, first + count):
		var builder := func(sd: int) -> String:
			return Height.build(Mask.build(sd), sd).content_hash()
		var det: bool = Debug.determinism_check("island_height seed %d" % s, builder, s)["ok"]
		var h = Height.build(Mask.build(s), s)
		var errs: Array[String] = h.validate()
		var ms := 0.0
		for t in h.timings:
			ms += float(t["ms"])
		total_ms += ms
		var hist: Dictionary = h.step_histogram()
		var keys := hist.keys()
		keys.sort()
		var steps := PackedStringArray()
		for k in keys:
			steps.append("%d:%d" % [k, hist[k]])
		var mn: Vector3 = h.meta.get("min", Vector3.ZERO)
		var mx: Vector3 = h.meta.get("max", Vector3.ZERO)
		print("[height] seed %3d: voxels %d..%d, %d rungs, levels %d..%d, meta min %s max %s, steps {%s}, rounds %d, %.1f ms %s" % [
			s, h.min_vox, h.max_vox, h.rungs.size(), h.levels[h.vox.find(h.min_vox)], h.levels[h.vox.find(h.max_vox)],
			mn, mx, ", ".join(steps), h.rounds, ms, "" if det and errs.is_empty() else "FAIL"])
		for e in errs:
			push_error("height seed %d: %s" % [s, e])
		if not det or not errs.is_empty():
			fail += 1
		if prev != null:
			min_diff = minf(min_diff, h.difference(prev))
		prev = h
		if Config.SAVE_ISLAND_MASK_PNG:
			var img: Image = h.to_image()
			img.resize(h.nx * Config.ISLAND_MASK_PNG_SCALE, h.nz * Config.ISLAND_MASK_PNG_SCALE, Image.INTERPOLATE_NEAREST)
			img.save_png("user://island_height_%d.png" % s)
	print("[height] smallest height difference between neighbouring seeds %.1f%% (need >= %.0f%%); %.1f ms per island" % [min_diff * 100.0, MIN_DIFF * 100.0, total_ms / float(count)])
	print("[height] PNGs in %s" % ProjectSettings.globalize_path("user://"))
	if min_diff < MIN_DIFF:
		fail += 1
	print("[height] height test %s" % ("PASS" if fail == 0 else "FAIL"))
	quit(fail)
