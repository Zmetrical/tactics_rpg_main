class_name VoxelWorldFill
extends RefCounted
## Fills a VoxelWorld from a heightfield. Adapter, no terrain dependency.
## Hookup (needs OverworldTerrain, not provided): height_fn / surface_fn read
## the terrain's per-cell height + is_water/is_land, scaled to voxel units.

## height_fn(x, z) -> int voxels. surface_fn(x, z) -> material id.
## Top voxel = surface material, below = body_material.
static func fill(world: VoxelWorld, height_fn: Callable, surface_fn: Callable, body_material: int = OverworldVoxel.ROCK) -> void:
	for x in world.size_x:
		for z in world.size_z:
			var h: int = clampi(height_fn.call(x, z), 0, world.max_y)
			if h == 0:
				world.set_column(x, z, PackedInt32Array())
				continue
			world.set_column(x, z, PackedInt32Array([body_material, h - 1, surface_fn.call(x, z), 1]))
