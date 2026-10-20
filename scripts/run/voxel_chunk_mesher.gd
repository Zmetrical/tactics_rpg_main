class_name VoxelChunkMesher
extends RefCounted
## Chunk mesher, no nodes. 16x16 columns per chunk, full height.
## Hidden-face culling: face emitted only when neighbour voxel (via world, so
## across chunk borders too) is AIR. One ArrayMesh, one surface per chunk.
## Vertex colour = palette colour * face shade, then optional hook (8b AO / 8c shadow).

const CHUNK := OverworldVoxel.CHUNK_SIZE

## Face order: +Y, -Y, +X, -X, +Z, -Z. Corners clockwise seen from outside.
const FACE_NORMALS: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const FACE_CORNERS: Array = [
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
	[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
]

## Hook: Callable(world, x, y, z, face, corner, color) -> Color. Empty = none.
var vertex_color_hook: Callable = Callable()
## Per-face base colour: Callable(x, y, z, face, material) -> Color. Replaces palette colour * face shade
## (step 1c parity: terrain colours come from per-cell data). Empty = palette. The hook above still runs after it.
var face_color_fn: Callable = Callable()
## Skip -Y faces on y = 0: nobody sees a slab's floor from above.
var cull_floor := false
## Column fast path, used while the world has no edits: faces come from column heights, interior voxels are never
## visited. Same mesh as the slow path (the test compares triangle counts).
var use_fast_path := true
var last_triangles: int = 0
var last_ms: float = 0.0

var _use_hook := false
var _s := 1.0


static func chunk_counts(world: VoxelWorld) -> Vector2i:
	return Vector2i(ceili(float(world.size_x) / CHUNK), ceili(float(world.size_z) / CHUNK))


## Chunks whose mesh changes when voxel (x, z) changes: own + border neighbours.
static func chunks_touching(x: int, z: int) -> Array[Vector2i]:
	var cx := x / CHUNK
	var cz := z / CHUNK
	var out: Array[Vector2i] = [Vector2i(cx, cz)]
	if x % CHUNK == 0 and cx > 0:
		out.append(Vector2i(cx - 1, cz))
	if x % CHUNK == CHUNK - 1:
		out.append(Vector2i(cx + 1, cz))
	if z % CHUNK == 0 and cz > 0:
		out.append(Vector2i(cx, cz - 1))
	if z % CHUNK == CHUNK - 1:
		out.append(Vector2i(cx, cz + 1))
	return out


## Returns mesh (no surface when chunk empty). Sets last_triangles, last_ms.
func build(world: VoxelWorld, cx: int, cz: int) -> ArrayMesh:
	var t0 := Time.get_ticks_usec()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	_s = OverworldVoxel.VOXEL_SIZE
	_use_hook = vertex_color_hook.is_valid()
	var fast := use_fast_path and world.edit_count() == 0
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	for x in range(x0, mini(x0 + CHUNK, world.size_x)):
		for z in range(z0, mini(z0 + CHUNK, world.size_z)):
			if fast:
				_column_fast(world, x, z, verts, normals, colors, indices)
			else:
				_column_slow(world, x, z, verts, normals, colors, indices)
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	last_triangles = indices.size() / 3
	last_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return mesh


func _column_slow(world: VoxelWorld, x: int, z: int, verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array) -> void:
	for y in world.column_top_bound(x, z):
		var m := world.get_voxel(x, y, z)
		if m == VoxelWorld.AIR:
			continue
		for f in 6:
			if cull_floor and f == 1 and y == 0:
				continue
			var n := FACE_NORMALS[f]
			if world.get_voxel(x + n.x, y + n.y, z + n.z) != VoxelWorld.AIR:
				continue
			_emit(world, x, y, z, f, m, verts, normals, colors, indices)


func _column_fast(world: VoxelWorld, x: int, z: int, verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var h := world.ground_height_at(x, z)
	if h == 0:
		return
	var runs := world.column_runs(x, z)
	_emit(world, x, h - 1, z, 0, runs[runs.size() - 2], verts, normals, colors, indices)
	if not cull_floor:
		_emit(world, x, 0, z, 1, runs[0], verts, normals, colors, indices)
	for f in range(2, 6):
		var n := FACE_NORMALS[f]
		var hn := world.ground_height_at(x + n.x, z + n.z)
		if hn >= h:
			continue
		var acc := 0
		for i in range(0, runs.size(), 2):
			var top := acc + runs[i + 1]
			for y in range(maxi(acc, hn), top):
				_emit(world, x, y, z, f, runs[i], verts, normals, colors, indices)
			acc = top


func _emit(world: VoxelWorld, x: int, y: int, z: int, f: int, m: int, verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var col: Color
	if face_color_fn.is_valid():
		col = face_color_fn.call(x, y, z, f, m)
	else:
		var base: Color = OverworldVoxel.COLORS[m]
		var shade := OverworldVoxel.FACE_SHADE[f]
		col = Color(base.r * shade, base.g * shade, base.b * shade, base.a)
	var n := Vector3(FACE_NORMALS[f])
	var vi := verts.size()
	var corners: Array = FACE_CORNERS[f]
	var origin := Vector3(x, y, z)
	for c in 4:
		var cc := col
		if _use_hook:
			cc = vertex_color_hook.call(world, x, y, z, f, c, col)
		verts.append((origin + (corners[c] as Vector3)) * _s)
		normals.append(n)
		colors.append(cc)
	indices.append_array([vi, vi + 1, vi + 2, vi, vi + 2, vi + 3])
