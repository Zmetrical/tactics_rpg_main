extends RefCounted
## Island mask (step 2a-2). Pure logic, no nodes. Knows nothing about rooms, nodes or paths.
## land[z * nx + x] = 1 for land. Domain-warped noise on a distorted ellipse (about 2:1 along x, the layer axis),
## then cleanup (step 2a-3), repeated until nothing changes: spurs removed (erode + dilate, then leaf pruning), flood
## fill keeps one landmass (the biggest, the rest is dropped), water holes filled. is_land meta: see meta / apply_meta.
## Same (seed, size) always gives the same mask. Tunables: data/run/overworld_style.gd (ISLAND_*).
const Style = preload("res://data/run/overworld_style.gd")
const Debug = preload("res://scripts/run/overworld/overworld_debug.gd")

var seed_value := 0
var nx := 0
var nz := 0
var land := PackedByteArray()
var land_count := 0
## Same keys and layout as the terrain's land meta: nx, nz, x0, z0, land (1 = land, z * nx + x), land_box (Rect2i),
## land_count. Set after every build.
var meta := {}
## Cleanup rounds the last build needed (1 = the first round changed nothing after the raw mask was cleaned).
var clean_rounds := 0
## Per-stage timing of the last build: [{name, ms}].
var timings: Array[Dictionary] = []

## size 0 = the style's ISLAND_NX / ISLAND_NZ.
static func build(seed_value_in: int, size_x: int = 0, size_z: int = 0) -> RefCounted:
	var m = new()
	m.seed_value = seed_value_in
	m.nx = size_x if size_x > 0 else Style.ISLAND_NX
	m.nz = size_z if size_z > 0 else Style.ISLAND_NZ
	m._generate()
	return m

## Callable-compatible with terrain.is_land(cell): cell.x = x (layer axis), cell.y = z.
func is_land_cell(cell: Vector2i) -> bool:
	return is_land(cell.x, cell.y)

## Sets the is_land meta on `target` (a Node or any Object): the keys of `meta`, same names the terrain root uses.
func apply_meta(target: Object) -> void:
	for k in meta:
		target.set_meta(k, meta[k])

func is_land(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= nx or z >= nz:
		return false
	return land[z * nx + x] == 1

## Bounding box of the land, in cells (empty Rect2i if there is no land).
func bbox() -> Rect2i:
	var x0 := nx
	var z0 := nz
	var x1 := -1
	var z1 := -1
	for z in nz:
		for x in nx:
			if land[z * nx + x] == 1:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				z0 = mini(z0, z)
				z1 = maxi(z1, z)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)

## Land cells as a share (0..100) of the land's bounding box.
func fill_percent() -> float:
	var b := bbox()
	if b.size.x * b.size.y == 0:
		return 0.0
	return 100.0 * float(land_count) / float(b.size.x * b.size.y)

## Number of 4-connected land bodies (1 after a build).
func component_count() -> int:
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var count := 0
	for start in nx * nz:
		if land[start] == 0 or seen[start] == 1:
			continue
		count += 1
		_flood(start, 1, seen)
	return count

## Land cells that have fewer than 2 land neighbours among their 4 (spur tips); 0 after a build.
func spur_cells() -> int:
	var n := 0
	for z in nz:
		for x in nx:
			if land[z * nx + x] == 0:
				continue
			var c := int(is_land(x - 1, z)) + int(is_land(x + 1, z)) + int(is_land(x, z - 1)) + int(is_land(x, z + 1))
			if c < 2:
				n += 1
	return n

func content_hash() -> String:
	return Debug.hash_variant([nx, nz, land])

## Debug view: black = water, white = land, one pixel per cell (scale up with Image.resize, INTERPOLATE_NEAREST).
func to_image() -> Image:
	var px := PackedByteArray()
	px.resize(nx * nz)
	for i in nx * nz:
		px[i] = 255 if land[i] == 1 else 0
	return Image.create_from_data(nx, nz, false, Image.FORMAT_L8, px)

## Share (0..1) of cells where this mask and `other` differ (same size).
func difference(other: RefCounted) -> float:
	if other.nx != nx or other.nz != nz:
		return 1.0
	var d := 0
	for i in nx * nz:
		if land[i] != other.land[i]:
			d += 1
	return float(d) / float(nx * nz)

# ---------------------------------------------------------------------------------------------------------

func _generate() -> void:
	timings.clear()
	_stage("noise")
	_raw_mask()
	_stage_end("noise")
	_stage("clean")
	clean_rounds = 0
	while clean_rounds < Style.ISLAND_CLEAN_ROUNDS:
		clean_rounds += 1
		var before := land.duplicate()
		for i in Style.ISLAND_OPEN_PASSES:
			_open_once()
		_keep_largest()
		_fill_holes()
		_prune_tips()
		if land == before:
			break
	_count()
	meta = {"nx": nx, "nz": nz, "x0": 0, "z0": 0, "land": land, "land_box": bbox(), "land_count": land_count}
	_stage_end("clean")
	if component_count() != 1 or spur_cells() != 0:
		push_warning("IslandMask seed %d: %d landmasses, %d spur cells after cleanup" % [seed_value, component_count(), spur_cells()])

var _t0 := {}

func _stage(name: String) -> void:
	_t0[name] = Time.get_ticks_usec()

func _stage_end(name: String) -> void:
	timings.append({"name": "island_" + name, "ms": float(Time.get_ticks_usec() - int(_t0.get(name, 0))) / 1000.0})

static func _noise(seed_v: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_v
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = maxi(octaves, 1)
	return n

func _raw_mask() -> void:
	var s := Style
	var base := (seed_value ^ s.ISLAND_SALT) & 0x7fffffff
	var warp_x := _noise(base + 1, s.ISLAND_WARP_FREQ, s.ISLAND_WARP_OCTAVES)
	var warp_z := _noise(base + 2, s.ISLAND_WARP_FREQ, s.ISLAND_WARP_OCTAVES)
	var lobe := _noise(base + 3, 1.0, s.ISLAND_LOBE_OCTAVES)
	var edge := _noise(base + 4, s.ISLAND_EDGE_FREQ, s.ISLAND_EDGE_OCTAVES)
	var rng := RandomNumberGenerator.new()
	rng.seed = base
	var bend_sign := 1.0 if rng.randi() % 2 == 0 else -1.0
	var lobe_phase := rng.randf() * 200.0
	var cx := float(nx - 1) * 0.5
	var cz := float(nz - 1) * 0.5
	var rx := cx * s.ISLAND_FILL
	var rz := cz * s.ISLAND_FILL
	var warp_amp: float = s.ISLAND_WARP_AMP * float(mini(nx, nz))
	land.resize(nx * nz)
	land.fill(0)
	var b: int = s.ISLAND_BORDER
	for z in range(b, nz - b):
		for x in range(b, nx - b):
			var px := float(x) - cx + warp_amp * warp_x.get_noise_2d(float(x), float(z))
			var pz := float(z) - cz + warp_amp * warp_z.get_noise_2d(float(x) + 417.0, float(z) + 291.0)
			var u := px / rx
			pz += bend_sign * s.ISLAND_BEND * rz * (u * u - 0.35)
			var rz_e: float = rz * (1.0 + s.ISLAND_EAST_WIDEN * clampf(u, -1.0, 1.0))
			var v := pz / rz_e
			var d := sqrt(u * u + v * v)
			var th := atan2(v, u)
			var reach: float = 1.0 \
				+ s.ISLAND_LOBE_AMP * lobe.get_noise_2d(cos(th) * s.ISLAND_LOBE_SCALE + lobe_phase, sin(th) * s.ISLAND_LOBE_SCALE + lobe_phase) \
				+ s.ISLAND_EDGE_AMP * edge.get_noise_2d(float(x), float(z))
			if d < reach:
				land[z * nx + x] = 1

## Erode (cell survives if all 4 neighbours are land), then dilate (land if it or a 4-neighbour survived).
func _open_once() -> void:
	var er := PackedByteArray()
	er.resize(nx * nz)
	for z in range(1, nz - 1):
		for x in range(1, nx - 1):
			var i := z * nx + x
			if land[i] == 1 and land[i - 1] == 1 and land[i + 1] == 1 and land[i - nx] == 1 and land[i + nx] == 1:
				er[i] = 1
	var out := PackedByteArray()
	out.resize(nx * nz)
	for z in nz:
		for x in nx:
			var i := z * nx + x
			var on := er[i] == 1
			if not on and x > 0:
				on = er[i - 1] == 1
			if not on and x < nx - 1:
				on = er[i + 1] == 1
			if not on and z > 0:
				on = er[i - nx] == 1
			if not on and z < nz - 1:
				on = er[i + nx] == 1
			out[i] = 1 if on else 0
	land = out

## 4-connected flood fill from `start` over cells equal to land[start]; marks seen[i] = mark. Returns the cell count.
func _flood(start: int, mark: int, seen: PackedByteArray) -> int:
	var want := land[start]
	var stack := PackedInt32Array()
	stack.append(start)
	seen[start] = mark
	var size := 0
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		size += 1
		var x := i % nx
		@warning_ignore("integer_division")
		var z := i / nx
		if x > 0 and land[i - 1] == want and seen[i - 1] == 0:
			seen[i - 1] = mark
			stack.append(i - 1)
		if x < nx - 1 and land[i + 1] == want and seen[i + 1] == 0:
			seen[i + 1] = mark
			stack.append(i + 1)
		if z > 0 and land[i - nx] == want and seen[i - nx] == 0:
			seen[i - nx] = mark
			stack.append(i - nx)
		if z < nz - 1 and land[i + nx] == want and seen[i + nx] == 0:
			seen[i + nx] = mark
			stack.append(i + nx)
	return size

## One landmass: keep the biggest body (first found wins a tie, scan order is fixed).
func _keep_largest() -> void:
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var best_start := -1
	var best_size := 0
	for start in nx * nz:
		if land[start] == 0 or seen[start] == 1:
			continue
		var size := _flood(start, 1, seen)
		if size > best_size:
			best_size = size
			best_start = start
	var keep := PackedByteArray()
	keep.resize(nx * nz)
	if best_start >= 0:
		_flood_into(best_start, keep)
	land = keep

func _flood_into(start: int, out: PackedByteArray) -> void:
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	_flood(start, 1, seen)
	for i in nx * nz:
		if seen[i] == 1:
			out[i] = 1

## Removes land cells with fewer than 2 land neighbours (4-way), over and over: 1-cell spurs and stray cells.
## Taking a leaf off never splits a body, so one landmass stays one.
func _prune_tips() -> void:
	var changed := true
	while changed:
		changed = false
		for z in nz:
			for x in nx:
				var i := z * nx + x
				if land[i] == 0:
					continue
				var c := int(is_land(x - 1, z)) + int(is_land(x + 1, z)) + int(is_land(x, z - 1)) + int(is_land(x, z + 1))
				if c < 2:
					land[i] = 0
					changed = true

## Water not connected to the grid edge becomes land (no lakes in the mask; ponds come in step 2c).
func _fill_holes() -> void:
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	if land[0] == 0:
		_flood(0, 1, seen)   # the border ring is water, so this is the sea
	for i in nx * nz:
		if land[i] == 0 and seen[i] == 0:
			land[i] = 1

func _count() -> void:
	land_count = 0
	for i in nx * nz:
		if land[i] == 1:
			land_count += 1
