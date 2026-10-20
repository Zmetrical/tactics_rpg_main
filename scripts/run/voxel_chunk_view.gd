class_name VoxelChunkView
extends Node3D
## One MeshInstance3D per chunk. Rebuilds only dirty chunks on VoxelWorld edits.
## Debug: F6 toggles chunk wireframe (or set debug_wireframe).

const DEBUG_KEY := KEY_F6

var world: VoxelWorld
var mesher := VoxelChunkMesher.new()
var debug_wireframe := false:
	set(v):
		debug_wireframe = v
		if _wire_root:
			_wire_root.visible = v

var _chunks: Dictionary = {}  # Vector2i -> MeshInstance3D
var _dirty: Dictionary = {}   # Vector2i -> true
var _material: StandardMaterial3D
var _wire_root: Node3D


func setup(p_world: VoxelWorld) -> void:
	world = p_world
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_root = Node3D.new()
	_wire_root.name = "ChunkWire"
	_wire_root.visible = debug_wireframe
	add_child(_wire_root)
	world.voxel_changed.connect(_on_voxel_changed)
	rebuild_all()


func rebuild_all() -> void:
	var t0 := Time.get_ticks_usec()
	var counts := VoxelChunkMesher.chunk_counts(world)
	var tris := 0
	for cx in counts.x:
		for cz in counts.y:
			tris += rebuild_chunk(Vector2i(cx, cz), false)["triangles"]
			_ensure_wire(Vector2i(cx, cz))
	print("voxel meshing: %d chunks, %d tris, %.1f ms" % [counts.x * counts.y, tris, (Time.get_ticks_usec() - t0) / 1000.0])


## Rebuilds exactly one chunk. Returns {chunk, triangles, ms}.
func rebuild_chunk(c: Vector2i, log: bool = true) -> Dictionary:
	var mesh := mesher.build(world, c.x, c.y)
	var inst: MeshInstance3D = _chunks.get(c)
	if inst == null:
		inst = MeshInstance3D.new()
		inst.name = "Chunk_%d_%d" % [c.x, c.y]
		inst.material_override = _material
		add_child(inst)
		_chunks[c] = inst
	inst.mesh = mesh
	var stats := {"chunk": c, "triangles": mesher.last_triangles, "ms": mesher.last_ms}
	if log:
		print("chunk (%d,%d): %d tris, %.2f ms" % [c.x, c.y, stats["triangles"], stats["ms"]])
	return stats


func _on_voxel_changed(x: int, _y: int, z: int) -> void:
	var counts := VoxelChunkMesher.chunk_counts(world)
	for c in VoxelChunkMesher.chunks_touching(x, z):
		if c.x >= 0 and c.y >= 0 and c.x < counts.x and c.y < counts.y:
			_dirty[c] = true


func _process(_delta: float) -> void:
	if _dirty.is_empty():
		return
	var keys := _dirty.keys()
	keys.sort()
	_dirty.clear()
	for c: Vector2i in keys:
		rebuild_chunk(c)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == DEBUG_KEY:
		debug_wireframe = not debug_wireframe


func _ensure_wire(c: Vector2i) -> void:
	var s := OverworldVoxel.VOXEL_SIZE
	var lo := Vector3(c.x * VoxelChunkMesher.CHUNK, 0, c.y * VoxelChunkMesher.CHUNK) * s
	var hi := Vector3(
		mini((c.x + 1) * VoxelChunkMesher.CHUNK, world.size_x), world.max_y,
		mini((c.y + 1) * VoxelChunkMesher.CHUNK, world.size_z)) * s
	var p := PackedVector3Array()
	for i in 8:
		p.append(Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	var edges := [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7]
	var idx := PackedInt32Array(edges)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = p
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.9, 0.2)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	_wire_root.add_child(mi)
