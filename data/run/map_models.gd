extends RefCounted
## Voxel-style 3D props for the overworld, never hand-authored: MapModels.make(kind) returns one ArrayMesh per
## kind. If res://art/map/<kind>.glb exists, its first mesh is used. Otherwise a placeholder is built from a box
## spec [size, centre, palette colour], all boxes merged into one mesh, flat vertex colours, no texture.
## Scale: 1 cell = 1 unit, the base sits on y = 0 and the model is centred on x / z. Draw it with a MultiMesh.
## Colours are the key colours of map_pixels.gd (gbc_palette.gd shades), nothing else.
## Kinds now: pine, tree, spire (props), stones, arch, tower, skull (landmarks, one each per map), boulder and flowers (micro props).

const MapPixels = preload("res://data/run/map_pixels.gd")

const GLB_DIR := "res://art/map/"

static var _cache := {}

## The ArrayMesh for `kind` ("pine", "tree", "spire", "stones", "arch", "tower", "skull", "boulder" or "flowers"), cached. null for an unknown kind.
static func make(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var mesh := _from_glb(kind)
	if mesh == null:
		var boxes := _spec(kind)
		if boxes.is_empty():
			push_error("MapModels.make: unknown kind '%s'" % kind)
			return null
		mesh = _merge(boxes)
	_cache[kind] = mesh
	return mesh

## Box specs: [size Vector3, centre Vector3 (base of the model at y = 0), Color].
static func _spec(kind: String) -> Array:
	var k := MapPixels.key_colors()
	var leaf: Color = k["g"]
	var trunk: Color = k["t"]
	var stone: Color = k["r"]
	var pale: Color = k["w"]
	var ink: Color = k["o"]
	var yellow: Color = k["l"]
	match kind:
		"pine":   # trunk + 3 shrinking tiers
			return [
				[Vector3(0.2, 0.3, 0.2), Vector3(0.0, 0.15, 0.0), trunk],
				[Vector3(0.8, 0.25, 0.8), Vector3(0.0, 0.425, 0.0), leaf.darkened(0.25)],
				[Vector3(0.6, 0.25, 0.6), Vector3(0.0, 0.675, 0.0), leaf],
				[Vector3(0.4, 0.25, 0.4), Vector3(0.0, 0.925, 0.0), leaf.lightened(0.1)],
			]
		"tree":   # trunk + one cube
			return [
				[Vector3(0.2, 0.4, 0.2), Vector3(0.0, 0.2, 0.0), trunk],
				[Vector3(0.7, 0.6, 0.7), Vector3(0.0, 0.7, 0.0), leaf],
			]
		"spire":  # 3 stacked tapering boxes
			return [
				[Vector3(1.2, 0.9, 1.2), Vector3(0.0, 0.45, 0.0), stone.darkened(0.15)],
				[Vector3(0.8, 0.9, 0.8), Vector3(0.0, 1.35, 0.0), stone],
				[Vector3(0.4, 0.9, 0.4), Vector3(0.0, 2.25, 0.0), pale],
			]
		"stones":  # a tall standing stone ringed by four shorter ones
			return [
				[Vector3(0.3, 1.3, 0.3), Vector3(0.0, 0.65, 0.0), stone],
				[Vector3(0.3, 0.2, 0.3), Vector3(0.0, 1.4, 0.0), pale],
				[Vector3(0.22, 0.7, 0.22), Vector3(-0.35, 0.35, -0.3), stone.darkened(0.15)],
				[Vector3(0.22, 0.9, 0.22), Vector3(0.35, 0.45, -0.3), stone],
				[Vector3(0.22, 0.6, 0.22), Vector3(-0.3, 0.3, 0.35), stone],
				[Vector3(0.22, 0.8, 0.22), Vector3(0.3, 0.4, 0.35), stone.darkened(0.15)],
			]
		"arch":   # two pillars, a lintel and a tuft of grass on top
			return [
				[Vector3(0.25, 1.2, 0.35), Vector3(-0.4, 0.6, 0.0), stone],
				[Vector3(0.25, 1.2, 0.35), Vector3(0.4, 0.6, 0.0), stone],
				[Vector3(1.05, 0.25, 0.35), Vector3(0.0, 1.325, 0.0), pale],
				[Vector3(0.4, 0.1, 0.3), Vector3(0.0, 1.5, 0.0), leaf],
			]
		"tower":  # base, shaft, battlement with four merlons and a dark window
			return [
				[Vector3(0.9, 0.5, 0.9), Vector3(0.0, 0.25, 0.0), stone.darkened(0.15)],
				[Vector3(0.6, 1.4, 0.6), Vector3(0.0, 1.2, 0.0), stone],
				[Vector3(0.8, 0.25, 0.8), Vector3(0.0, 2.025, 0.0), pale],
				[Vector3(0.2, 0.2, 0.2), Vector3(-0.3, 2.25, -0.3), pale],
				[Vector3(0.2, 0.2, 0.2), Vector3(0.3, 2.25, -0.3), pale],
				[Vector3(0.2, 0.2, 0.2), Vector3(-0.3, 2.25, 0.3), pale],
				[Vector3(0.2, 0.2, 0.2), Vector3(0.3, 2.25, 0.3), pale],
				[Vector3(0.2, 0.3, 0.08), Vector3(0.0, 1.3, 0.3), ink],
			]
		"skull":  # a stone mound under a bone-pale skull with dark eye sockets
			return [
				[Vector3(1.0, 0.35, 1.0), Vector3(0.0, 0.175, 0.0), stone.darkened(0.15)],
				[Vector3(0.5, 0.25, 0.5), Vector3(0.0, 0.475, 0.0), pale.darkened(0.15)],
				[Vector3(0.7, 0.5, 0.6), Vector3(0.0, 0.85, 0.0), pale],
				[Vector3(0.16, 0.16, 0.08), Vector3(-0.17, 0.9, 0.3), ink],
				[Vector3(0.16, 0.16, 0.08), Vector3(0.17, 0.9, 0.3), ink],
				[Vector3(0.1, 0.12, 0.08), Vector3(0.0, 0.7, 0.3), ink],
			]
		"boulder":  # a lumpy rock: body, a lighter top and one small stone beside it
			return [
				[Vector3(0.6, 0.4, 0.5), Vector3(0.0, 0.2, 0.0), stone.darkened(0.1)],
				[Vector3(0.4, 0.2, 0.35), Vector3(-0.05, 0.5, 0.0), stone],
				[Vector3(0.25, 0.2, 0.25), Vector3(0.3, 0.1, 0.25), stone.darkened(0.25)],
			]
		"flowers":  # a low grass patch with five stems, blossoms alternating yellow and pale
			return [
				[Vector3(0.6, 0.06, 0.6), Vector3(0.0, 0.03, 0.0), leaf.darkened(0.2)],
				[Vector3(0.04, 0.2, 0.04), Vector3(-0.25, 0.16, -0.2), leaf],
				[Vector3(0.12, 0.1, 0.12), Vector3(-0.25, 0.31, -0.2), yellow],
				[Vector3(0.04, 0.2, 0.04), Vector3(0.2, 0.16, -0.25), leaf],
				[Vector3(0.12, 0.1, 0.12), Vector3(0.2, 0.31, -0.25), pale],
				[Vector3(0.04, 0.2, 0.04), Vector3(0.0, 0.16, 0.05), leaf],
				[Vector3(0.12, 0.1, 0.12), Vector3(0.0, 0.31, 0.05), yellow],
				[Vector3(0.04, 0.2, 0.04), Vector3(-0.2, 0.16, 0.25), leaf],
				[Vector3(0.12, 0.1, 0.12), Vector3(-0.2, 0.31, 0.25), pale],
				[Vector3(0.04, 0.2, 0.04), Vector3(0.28, 0.16, 0.2), leaf],
				[Vector3(0.12, 0.1, 0.12), Vector3(0.28, 0.31, 0.2), yellow],
			]
	return []

## First MeshInstance3D mesh of res://art/map/<kind>.glb, or null when the file is missing or has no mesh.
static func _from_glb(kind: String) -> ArrayMesh:
	var path := GLB_DIR + kind + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var root := scene.instantiate()
	var found: ArrayMesh = null
	var todo: Array[Node] = [root]
	while not todo.is_empty() and found == null:
		var n: Node = todo.pop_front()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh:
			found = (n as MeshInstance3D).mesh
		todo.append_array(n.get_children())
	root.free()
	return found

## All boxes in one surface: five faces each (the bottom is never seen), flat vertex colours, lit.
static func _merge(boxes: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in boxes:
		var size: Vector3 = b[0]
		var c: Vector3 = b[1]
		var col: Color = b[2]
		var lo := c - size * 0.5
		var hi := c + size * 0.5
		_quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3.UP, col)
		_quad(st, Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3.FORWARD, col)
		_quad(st, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3.BACK, col)
		_quad(st, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3.LEFT, col)
		_quad(st, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3.RIGHT, col)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	st.set_material(mat)
	return st.commit()

## Quad a, b / c, d (rows) facing `outward`; the winding is flipped if needed (Godot front faces are clockwise).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
	_tri(st, a, b, c, outward, col)
	_tri(st, b, d, c, outward, col)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(outward)
		st.add_vertex(v)
