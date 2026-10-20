extends SceneTree
## godot --headless -s scripts/tools/voxel_chunk_mesher_test.gd

func _init() -> void:
	var fails := 0
	var keys := PackedStringArray(OverworldVoxel.MATERIAL_KEYS)
	var mesher := VoxelChunkMesher.new()

	# culling: 1 voxel = 6 faces, 2 adjacent = 10 faces
	var w := VoxelWorld.new(4, 4, 8, keys)
	w.set_column(1, 1, PackedInt32Array([OverworldVoxel.GRASS, 1]))
	mesher.build(w, 0, 0)
	fails += _check("1 voxel = 12 tris", mesher.last_triangles == 12)
	w.set_column(2, 1, PackedInt32Array([OverworldVoxel.GRASS, 1]))
	mesher.build(w, 0, 0)
	fails += _check("2 adjacent = 20 tris", mesher.last_triangles == 20)

	# single-chunk rebuild
	var big := VoxelWorld.new(40, 40, OverworldVoxel.MAX_HEIGHT, keys)
	VoxelWorldFill.fill(big, func(_x: int, _z: int) -> int: return 4, func(_x: int, _z: int) -> int: return OverworldVoxel.GRASS)
	var counts := VoxelChunkMesher.chunk_counts(big)
	fails += _check("3x3 chunks", counts == Vector2i(3, 3))
	var tris := {}
	var t0 := Time.get_ticks_usec()
	for cx in counts.x:
		for cz in counts.y:
			var m := mesher.build(big, cx, cz)
			tris[Vector2i(cx, cz)] = mesher.last_triangles
			print("chunk (%d,%d): %d tris, %.2f ms, surfaces %d" % [cx, cz, mesher.last_triangles, mesher.last_ms, m.get_surface_count()])
	print("all chunks ms: %.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))

	var dirty := []
	big.voxel_changed.connect(func(x: int, _y: int, z: int) -> void: dirty.append(Vector2i(x, z)))
	big.set_voxel(5, 4, 5, OverworldVoxel.WOOD)
	fails += _check("edit signal once", dirty == [Vector2i(5, 5)])
	var touched := VoxelChunkMesher.chunks_touching(5, 5)
	fails += _check("interior edit touches 1 chunk", touched == [Vector2i(0, 0)])
	fails += _check("border edit touches neighbour", VoxelChunkMesher.chunks_touching(15, 5).has(Vector2i(1, 0)))
	mesher.build(big, 0, 0)
	print("rebuilt (0,0): %d tris, %.2f ms" % [mesher.last_triangles, mesher.last_ms])
	fails += _check("chunk (0,0) +8 tris", mesher.last_triangles == tris[Vector2i(0, 0)] + 8)
	mesher.build(big, 1, 1)
	fails += _check("chunk (1,1) unchanged", mesher.last_triangles == tris[Vector2i(1, 1)])

	# hook
	mesher.vertex_color_hook = func(_w: VoxelWorld, _x: int, _y: int, _z: int, _f: int, _c: int, col: Color) -> Color: return col.darkened(0.5)
	mesher.build(w, 0, 0)
	fails += _check("hook runs", mesher.last_triangles == 20)

	# 1c: fast path == slow path, cull_floor, face_color_fn
	var fw := VoxelWorld.new(20, 20, 16, keys)
	for x in 20:
		for z in 20:
			fw.set_column(x, z, PackedInt32Array([OverworldVoxel.ROCK, 2 + (x * 7 + z * 3) % 5, OverworldVoxel.GRASS, 1]))
	var fm := VoxelChunkMesher.new()
	fm.use_fast_path = false
	fm.build(fw, 0, 0)
	var slow_tris := fm.last_triangles
	fm.use_fast_path = true
	fm.build(fw, 0, 0)
	print("fast %d tris %.2f ms, slow %d tris" % [fm.last_triangles, fm.last_ms, slow_tris])
	fails += _check("fast == slow tris", fm.last_triangles == slow_tris)
	fm.cull_floor = true
	fm.build(fw, 0, 0)
	fails += _check("cull_floor drops 256 floor faces (512 tris)", fm.last_triangles == slow_tris - 512)
	fm.use_fast_path = false
	fm.build(fw, 0, 0)
	fails += _check("cull_floor same on slow path", fm.last_triangles == slow_tris - 512)
	var seen := [0]
	fm.face_color_fn = func(_x: int, _y: int, _z: int, _f: int, _m: int) -> Color:
		seen[0] += 1
		return Color.RED
	fm.build(fw, 0, 0)
	fails += _check("face_color_fn once per face", seen[0] * 2 == fm.last_triangles)

	print("FAILS: ", fails)
	quit(1 if fails > 0 else 0)


func _check(label: String, ok: bool) -> int:
	print(("ok   " if ok else "FAIL ") + label)
	return 0 if ok else 1
