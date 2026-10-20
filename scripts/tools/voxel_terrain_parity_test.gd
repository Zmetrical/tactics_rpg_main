extends SceneTree
## godot --headless -s res://scripts/tools/voxel_terrain_parity_test.gd [-- <seed>]
## Step 1c: builds layout + terrain, fills VoxelWorld from it twice (hash must match), checks every cell's height and
## surface material against the terrain data, meshes all chunks, prints timing.
const Layout = preload("res://scripts/run/overworld_layout.gd")
const Terrain = preload("res://scripts/run/overworld_terrain.gd")
const MapGen = preload("res://scripts/run/map_generator.gd")
const Style = preload("res://data/run/overworld_style.gd")


func _init() -> void:
	var seed := 12345
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		seed = int(args[0])
	var fails := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var map = MapGen.generate(rng)
	var lay = Layout.build(map, seed)
	var ter = Terrain.build(lay, seed)
	var a := OverworldVoxelTerrain.build(ter)
	var b := OverworldVoxelTerrain.build(ter)
	print("fill ms: %.1f, world %d x %d x %d" % [a.build_ms, a.world.size_x, a.world.max_y, a.world.size_z])
	print("hash: ", a.world.hash())
	fails += _check("hash identical across two builds", a.world.hash() == b.world.hash())
	var bad_h := 0
	var bad_m := 0
	var bad_c := 0
	for iz in ter.nz:
		for ix in ter.nx:
			var i: int = iz * ter.nx + ix
			var vx: int = ix * a.cell_vox + 1
			var vz: int = iz * a.cell_vox + 1
			if ter.land[i] == 0:
				if a.world.height_at(vx, vz) != 0:
					bad_h += 1
				continue
			if a.world.height_at(vx, vz) != a.base_vox + ter.levels[i] * a.level_vox:
				bad_h += 1
			var want := OverworldVoxel.WATER if ter.water[i] == 1 else (OverworldVoxel.STONE if ter.biomes[i] == Style.ROCK else OverworldVoxel.GRASS)
			if a.world.surface_material_at(vx, vz) != want:
				bad_m += 1
			if ter.water[i] == 0 and ter.biomes[i] == Style.MEADOW:
				var top: Color = a.face_color(ix * a.cell_vox + 1, a.world.height_at(vx, vz) - 1, vz, 0, want)
				var alt := posmod(ter.x0 + ix + ter.z0 + iz, 2) == 1
				var old: Color = Style.top_color(Style.MEADOW, alt, ter.levels[i])
				if not top.is_equal_approx(old):
					bad_c += 1
	fails += _check("heights match terrain levels", bad_h == 0)
	fails += _check("surface materials match", bad_m == 0)
	fails += _check("meadow top colours match old mesh", bad_c == 0)
	var mesher := VoxelChunkMesher.new()
	mesher.cull_floor = true
	mesher.face_color_fn = a.face_color
	var counts := VoxelChunkMesher.chunk_counts(a.world)
	var tris := 0
	var t0 := Time.get_ticks_usec()
	for cx in counts.x:
		for cz in counts.y:
			mesher.build(a.world, cx, cz)
			tris += mesher.last_triangles
	print("meshing: %d chunks, %d tris, %.1f ms" % [counts.x * counts.y, tris, (Time.get_ticks_usec() - t0) / 1000.0])
	fails += _check("mesh not empty", tris > 0)
	ter.free()
	print("FAILS: ", fails)
	quit(1 if fails > 0 else 0)


func _check(label: String, ok: bool) -> int:
	print(("ok   " if ok else "FAIL ") + label)
	return 0 if ok else 1
