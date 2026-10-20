extends RefCounted
## Column storage for the voxel island: per (x, z) column a top height and a bottom height (the tapered
## underside), plus a material id for the top voxel. Heights are in voxels; world size comes from
## OverworldSites.VOXEL_SIZE. Pure logic, no nodes. Out of range reads return empty (top < bottom).
const Debug = preload("res://scripts/run/overworld/overworld_debug.gd")
const NONE_MAT := 0

var nx := 0
var nz := 0
var top := PackedInt32Array()      # top surface height (exclusive), voxels
var bottom := PackedInt32Array()   # underside height (inclusive), voxels; bottom >= top means empty
var mat := PackedByteArray()       # material of the top voxel, see overworld_palette.gd ids

func _init(size_x: int = 0, size_z: int = 0) -> void:
	resize(size_x, size_z)

func resize(size_x: int, size_z: int) -> void:
	nx = size_x
	nz = size_z
	top.resize(nx * nz)
	bottom.resize(nx * nz)
	mat.resize(nx * nz)
	top.fill(0)
	bottom.fill(0)
	mat.fill(NONE_MAT)

func in_range(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < nx and z < nz

func idx(x: int, z: int) -> int:
	return z * nx + x

func is_solid(x: int, z: int) -> bool:
	return in_range(x, z) and top[idx(x, z)] > bottom[idx(x, z)]

func top_at(x: int, z: int) -> int:
	return top[idx(x, z)] if in_range(x, z) else 0

func bottom_at(x: int, z: int) -> int:
	return bottom[idx(x, z)] if in_range(x, z) else 0

func set_column(x: int, z: int, bottom_h: int, top_h: int, material: int) -> void:
	if not in_range(x, z):
		return
	var i := idx(x, z)
	bottom[i] = bottom_h
	top[i] = top_h
	mat[i] = material

## Content hash for the determinism check.
func content_hash() -> String:
	return Debug.hash_variant([nx, nz, top, bottom, mat])

