class_name VoxelWorld
extends RefCounted
## Voxel store, no meshing. Column store + sparse edit Dictionary.
## Column: bottom-up material runs from y=0, flat [mat, count, mat, count...].
## Edit: Vector3i -> material id. AIR (0) edit = carve. Edits equal to the
## column value are erased, so state is canonical.

signal voxel_changed(x: int, y: int, z: int)

const AIR := 0

var size_x: int
var size_z: int
var max_y: int
var material_keys: PackedStringArray

var _heights: PackedInt32Array = PackedInt32Array()
var _runs: Array = []
var _edits: Dictionary = {}
var _edit_top: Dictionary = {}  # Vector2i -> highest edited y + 1 (upper bound, never lowered)


func _init(p_size_x: int, p_size_z: int, p_max_y: int, p_material_keys: PackedStringArray = PackedStringArray()) -> void:
	size_x = p_size_x
	size_z = p_size_z
	max_y = p_max_y
	material_keys = p_material_keys
	var n := size_x * size_z
	_heights.resize(n)
	_runs.resize(n)
	for i in n:
		_runs[i] = PackedInt32Array()


func bounds() -> Vector3i:
	return Vector3i(size_x, max_y, size_z)


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < size_x and z >= 0 and z < size_z and y >= 0 and y < max_y


func set_column(x: int, z: int, runs: PackedInt32Array) -> void:
	assert(x >= 0 and x < size_x and z >= 0 and z < size_z, "set_column out of bounds")
	assert(runs.size() % 2 == 0, "runs must be [mat, count] pairs")
	var merged := PackedInt32Array()
	var total := 0
	for i in range(0, runs.size(), 2):
		var mat := runs[i]
		var count := runs[i + 1]
		if count <= 0:
			continue
		total += count
		var m := merged.size()
		if m > 0 and merged[m - 2] == mat:
			merged[m - 1] += count
		else:
			merged.append(mat)
			merged.append(count)
	assert(total <= max_y, "column exceeds max_y")
	var idx := x * size_z + z
	_runs[idx] = merged
	_heights[idx] = mini(total, max_y)


func ground_height_at(x: int, z: int) -> int:
	if x < 0 or x >= size_x or z < 0 or z >= size_z:
		return 0
	return _heights[x * size_z + z]


## Top solid y + 1 including edits. 0 = empty column.
func height_at(x: int, z: int) -> int:
	if x < 0 or x >= size_x or z < 0 or z >= size_z:
		return 0
	var top: int = maxi(_heights[x * size_z + z], _edit_top.get(Vector2i(x, z), 0))
	var y := top - 1
	while y >= 0:
		if get_voxel(x, y, z) != AIR:
			return y + 1
		y -= 1
	return 0


func surface_material_at(x: int, z: int) -> int:
	var h := height_at(x, z)
	if h == 0:
		return AIR
	return get_voxel(x, h - 1, z)


func get_voxel(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return AIR
	var key := Vector3i(x, y, z)
	if _edits.has(key):
		return _edits[key]
	return _column_get(x, y, z)


func set_voxel(x: int, y: int, z: int, material: int) -> bool:
	if not in_bounds(x, y, z):
		return false
	var key := Vector3i(x, y, z)
	var old := get_voxel(x, y, z)
	if material == old:
		return true
	if material == _column_get(x, y, z):
		_edits.erase(key)
	else:
		_edits[key] = material
	if material != AIR:
		var ck := Vector2i(x, z)
		_edit_top[ck] = maxi(_edit_top.get(ck, 0), y + 1)
	voxel_changed.emit(x, y, z)
	return true


## Cheap upper bound of solid y + 1 (ground or highest edit). For meshers.
func column_top_bound(x: int, z: int) -> int:
	if x < 0 or x >= size_x or z < 0 or z >= size_z:
		return 0
	return maxi(_heights[x * size_z + z], _edit_top.get(Vector2i(x, z), 0))


## Bottom-up [mat, count, ...] runs of the column (no edits applied). Read-only: do not modify.
func column_runs(x: int, z: int) -> PackedInt32Array:
	return _runs[x * size_z + z]


func edit_count() -> int:
	return _edits.size()


## Stable SHA-256 hex over keys, dims, columns, sorted edits.
func hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedInt32Array([size_x, size_z, max_y]).to_byte_array())
	ctx.update("|".join(material_keys).to_utf8_buffer())
	ctx.update(_heights.to_byte_array())
	var flat := PackedInt32Array()
	for runs: PackedInt32Array in _runs:
		flat.append(runs.size())
		flat.append_array(runs)
	ctx.update(flat.to_byte_array())
	var keys: Array = _edits.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		if a.y != b.y:
			return a.y < b.y
		return a.z < b.z)
	var ef := PackedInt32Array()
	for k: Vector3i in keys:
		ef.append(k.x)
		ef.append(k.y)
		ef.append(k.z)
		ef.append(_edits[k])
	ctx.update(ef.to_byte_array())
	return ctx.finish().hex_encode()


func _column_get(x: int, y: int, z: int) -> int:
	var idx := x * size_z + z
	if y >= _heights[idx]:
		return AIR
	var runs: PackedInt32Array = _runs[idx]
	var acc := 0
	for i in range(0, runs.size(), 2):
		acc += runs[i + 1]
		if y < acc:
			return runs[i]
	return AIR
