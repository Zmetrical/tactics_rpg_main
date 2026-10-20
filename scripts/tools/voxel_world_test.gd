extends SceneTree
## godot --headless -s scripts/tools/voxel_world_test.gd
## Stand-in terrain: seeded FastNoiseLite. Replace callables with OverworldTerrain output.

const W := 256
const D := 128

func _init() -> void:
	var fails := 0
	var t0 := Time.get_ticks_usec()
	var a := _build(1)
	var t1 := Time.get_ticks_usec()
	var b := _build(1)
	var c := _build(2)
	var ha := a.hash()
	var t2 := Time.get_ticks_usec()
	print("build ms: %.1f" % ((t1 - t0) / 1000.0))
	print("hash ms: %.1f" % ((t2 - t1) / 1000.0))
	print("hash seed1: ", ha)
	fails += _check("hash stable across builds", ha == b.hash())
	fails += _check("hash differs across seeds", ha != c.hash())

	var x := 10
	var z := 10
	var h := a.height_at(x, z)
	fails += _check("surface material", a.surface_material_at(x, z) != VoxelWorld.AIR)
	fails += _check("set above ground", a.set_voxel(x, h + 2, z, OverworldVoxel.WOOD))
	fails += _check("get edit", a.get_voxel(x, h + 2, z) == OverworldVoxel.WOOD)
	fails += _check("height_at sees edit", a.height_at(x, z) == h + 3)
	fails += _check("hash changes on edit", a.hash() != ha)
	a.set_voxel(x, h + 2, z, VoxelWorld.AIR)
	fails += _check("edit undone erases", a.edit_count() == 0)
	fails += _check("hash reverts", a.hash() == ha)
	var below := a.get_voxel(x, h - 1, z)
	a.set_voxel(x, h - 1, z, VoxelWorld.AIR)
	fails += _check("carve", a.get_voxel(x, h - 1, z) == VoxelWorld.AIR and a.edit_count() == 1)
	a.set_voxel(x, h - 1, z, below)
	fails += _check("carve undone", a.edit_count() == 0 and a.hash() == ha)
	fails += _check("out of bounds set", not a.set_voxel(-1, 0, 0, 1))
	fails += _check("out of bounds get", a.get_voxel(W, 0, 0) == VoxelWorld.AIR)
	print("FAILS: ", fails)
	quit(1 if fails > 0 else 0)


func _build(seed_value: int) -> VoxelWorld:
	var n := FastNoiseLite.new()
	n.seed = (seed_value ^ OverworldVoxel.STAGE_SALT) & 0x7fffffff
	n.frequency = 0.02
	var w := VoxelWorld.new(W, D, OverworldVoxel.MAX_HEIGHT, PackedStringArray(OverworldVoxel.MATERIAL_KEYS))
	VoxelWorldFill.fill(w,
		func(x: int, z: int) -> int: return 4 + int((n.get_noise_2d(x, z) + 1.0) * 10.0),
		func(x: int, z: int) -> int: return OverworldVoxel.WATER if n.get_noise_2d(x, z) < -0.4 else OverworldVoxel.GRASS)
	return w


func _check(label: String, ok: bool) -> int:
	print(("ok   " if ok else "FAIL ") + label)
	return 0 if ok else 1
