extends RefCounted
## Island base height (step 2a-4). Pure logic, no nodes. Input: an IslandMask (land only; knows no nodes or paths).
## Output per cell: height in voxels (vox), snapped to a seeded ladder of rungs 3-6 voxels apart, so neighbouring land
## cells differ by 0 or 3-6 voxels: vertical cliff faces, no slopes. Low continental base (rises with the distance from
## the coast) plus rolling hills (fbm noise, faded in from the coast). Tunables: data/run/overworld_style.gd (ISLAND_H_*).
## Meta (apply_meta, same names as the terrain root): levels, x0, z0, nx, nz, land, min, max (+ heights_vox, level_vox).
const Style = preload("res://data/run/overworld_style.gd")
const Debug = preload("res://scripts/run/overworld/overworld_debug.gd")
const Voxel = preload("res://data/run/overworld_voxel.gd")
const Stage = preload("res://scripts/battle/stage_3d.gd")

var seed_value := 0
var x0 := 0
var z0 := 0
var nx := 0
var nz := 0
var land := PackedByteArray()
## Ladder of allowed heights (voxels), ascending; rungs[0] = ISLAND_H_FLOOR.
var rungs := PackedInt32Array()
## Per cell: index into rungs, -1 on water.
var rung := PackedInt32Array()
## Per cell: height in voxels; 0 on water.
var vox := PackedInt32Array()
## Per cell: height in height levels (Stage3D.STEP world units each) = vox / level_vox, rounded. 0 on water.
var levels := PackedInt32Array()
var level_vox := 2
var min_vox := 0   # lowest and highest land height, voxels
var max_vox := 0
var meta := {}
var rounds := 0
var timings: Array[Dictionary] = []
var _t0 := {}

static func build(mask: RefCounted, seed_value_in: int) -> RefCounted:
	var h = new()
	h.seed_value = seed_value_in
	h.nx = mask.nx
	h.nz = mask.nz
	h.x0 = int(mask.meta.get("x0", 0))
	h.z0 = int(mask.meta.get("z0", 0))
	h.land = mask.land.duplicate()
	h._generate()
	return h

func height_at(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= nx or z >= nz:
		return 0
	return vox[z * nx + x]

func apply_meta(target: Object) -> void:
	for k in meta:
		target.set_meta(k, meta[k])

func content_hash() -> String:
	return Debug.hash_variant([nx, nz, vox, rungs])

## Number of land-land neighbour pairs (4-way, each once) per height difference: {0: n, 4: n, ...}.
func step_histogram() -> Dictionary:
	var out := {}
	for z in nz:
		for x in nx:
			var i := z * nx + x
			if land[i] == 0:
				continue
			if x < nx - 1 and land[i + 1] == 1:
				var d := absi(vox[i] - vox[i + 1])
				out[d] = int(out.get(d, 0)) + 1
			if z < nz - 1 and land[i + nx] == 1:
				var d2 := absi(vox[i] - vox[i + nx])
				out[d2] = int(out.get(d2, 0)) + 1
	return out

## Empty = valid. Checks meta levels / min / max and the step rule.
func validate() -> Array[String]:
	var err: Array[String] = []
	var n := nx * nz
	if vox.size() != n or levels.size() != n or land.size() != n:
		err.append("array sizes differ from nx * nz")
		return err
	var cap := mini(int(Style.ISLAND_H_MAX), Voxel.MAX_HEIGHT - 1)
	var lo := 1 << 30
	var hi := -1
	var cells := 0
	for i in n:
		if land[i] == 0:
			if vox[i] != 0 or levels[i] != 0:
				err.append("water cell %d has height" % i)
				break
			continue
		cells += 1
		lo = mini(lo, vox[i])
		hi = maxi(hi, vox[i])
		if vox[i] < int(Style.ISLAND_H_FLOOR) or vox[i] > cap:
			err.append("cell %d height %d outside %d..%d" % [i, vox[i], Style.ISLAND_H_FLOOR, cap])
			break
		if levels[i] != roundi(float(vox[i]) / float(level_vox)):
			err.append("cell %d level %d does not match height %d" % [i, levels[i], vox[i]])
			break
	if cells == 0:
		err.append("no land")
		return err
	if lo != min_vox or hi != max_vox or lo > hi:
		err.append("min/max voxel fields (%d, %d) do not match the land (%d, %d)" % [min_vox, max_vox, lo, hi])
	var mn: Vector3 = meta.get("min", Vector3.ZERO)
	var mx: Vector3 = meta.get("max", Vector3.ZERO)
	if not (mn.x < mx.x and mn.y < mx.y and mn.z < mx.z):
		err.append("meta min %s is not below meta max %s" % [mn, mx])
	if not is_equal_approx(mx.y, float(hi) * Voxel.VOXEL_SIZE):
		err.append("meta max y %s is not max height %d voxels" % [mx.y, hi])
	if (meta.get("levels", PackedInt32Array()) as PackedInt32Array).size() != n:
		err.append("meta levels has the wrong size")
	for d in step_histogram():
		if d != 0 and (d < int(Style.ISLAND_H_STEP_MIN) or d > int(Style.ISLAND_H_STEP_MAX)):
			err.append("neighbouring land cells differ by %d voxels (allowed 0 or %d-%d)" % [d, Style.ISLAND_H_STEP_MIN, Style.ISLAND_H_STEP_MAX])
			break
	return err

## Debug view: height colour ramp (low -> high), water dark blue, one pixel per cell.
func to_image() -> Image:
	var img := Image.create(nx, nz, false, Image.FORMAT_RGB8)
	var span := float(maxi(max_vox - int(Style.ISLAND_H_FLOOR), 1))
	for z in nz:
		for x in nx:
			var i := z * nx + x
			if land[i] == 0:
				img.set_pixel(x, z, Style.ISLAND_H_WATER_COLOR)
			else:
				img.set_pixel(x, z, _ramp(float(vox[i] - int(Style.ISLAND_H_FLOOR)) / span))
	return img

## Share (0..1) of cells whose height differs between this and `other` (same size).
func difference(other: RefCounted) -> float:
	if other.nx != nx or other.nz != nz:
		return 1.0
	var d := 0
	for i in nx * nz:
		if vox[i] != other.vox[i]:
			d += 1
	return float(d) / float(nx * nz)

# ---------------------------------------------------------------------------------------------------------

func _ramp(t: float) -> Color:
	var ramp: Array[Color] = Style.ISLAND_H_RAMP
	var f := clampf(t, 0.0, 1.0) * float(ramp.size() - 1)
	var k := mini(int(f), ramp.size() - 2)
	return ramp[k].lerp(ramp[k + 1], f - float(k))

func _stage(name: String) -> void:
	_t0[name] = Time.get_ticks_usec()

func _stage_end(name: String) -> void:
	timings.append({"name": "height_" + name, "ms": float(Time.get_ticks_usec() - int(_t0.get(name, 0))) / 1000.0})

func _generate() -> void:
	var s := Style
	var n := nx * nz
	level_vox = maxi(roundi(Stage.STEP / Voxel.VOXEL_SIZE), 1)
	var base := (seed_value ^ s.ISLAND_H_SALT) & 0x7fffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = base
	_stage("continuous")
	var dist := _coast_distance()
	var hills := FastNoiseLite.new()
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.seed = base + 1
	hills.frequency = s.ISLAND_H_HILL_FREQ
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = s.ISLAND_H_HILL_OCTAVES
	var floor_h := float(s.ISLAND_H_FLOOR)
	var cap := float(mini(int(s.ISLAND_H_MAX), Voxel.MAX_HEIGHT - 1))
	var top := minf(floor_h + float(s.ISLAND_H_BASE_RISE) + float(s.ISLAND_H_HILL_AMP) + 1.0, cap)
	rungs.clear()
	rungs.append(int(s.ISLAND_H_FLOOR))
	while float(rungs[rungs.size() - 1]) < top:
		rungs.append(rungs[rungs.size() - 1] + rng.randi_range(int(s.ISLAND_H_STEP_MIN), int(s.ISLAND_H_STEP_MAX)))
	rung.resize(n)
	rung.fill(-1)
	for z in nz:
		for x in nx:
			var i := z * nx + x
			if land[i] == 0:
				continue
			var d := dist[i]
			var n01 := hills.get_noise_2d(float(x), float(z)) * 0.5 + 0.5
			var hc := floor_h \
				+ s.ISLAND_H_BASE_RISE * smoothstep(0.0, s.ISLAND_H_BASE_DIST, d) \
				+ s.ISLAND_H_HILL_AMP * smoothstep(s.ISLAND_H_HILL_FROM, s.ISLAND_H_HILL_TO, n01) * smoothstep(0.0, s.ISLAND_H_HILL_RAMP_DIST, d)
			hc = minf(hc, cap)
			var r := 0
			while r + 1 < rungs.size() and float(rungs[r + 1]) <= hc:
				r += 1
			rung[i] = r
	_stage_end("continuous")
	_stage("terraces")
	rounds = 0
	_limit_steps()
	while rounds < int(s.ISLAND_H_ROUNDS):
		rounds += 1
		var merged := _merge_small_patches()
		_limit_steps()
		if not merged:
			break
	_stage_end("terraces")
	_finish()

## Chamfer 3-4 distance (in cells) from every land cell to the nearest water cell; the grid edge counts as water.
func _coast_distance() -> PackedFloat32Array:
	var n := nx * nz
	var d := PackedInt32Array()
	d.resize(n)
	for z in nz:
		for x in nx:
			var i := z * nx + x
			if land[i] == 0:
				d[i] = 0
			elif x == 0 or z == 0 or x == nx - 1 or z == nz - 1:
				d[i] = 3
			else:
				d[i] = 1000000
	for z in nz:
		for x in nx:
			var i := z * nx + x
			var v := d[i]
			if v == 0:
				continue
			if x > 0:
				v = mini(v, d[i - 1] + 3)
			if z > 0:
				v = mini(v, d[i - nx] + 3)
				if x > 0:
					v = mini(v, d[i - nx - 1] + 4)
				if x < nx - 1:
					v = mini(v, d[i - nx + 1] + 4)
			d[i] = v
	for z in range(nz - 1, -1, -1):
		for x in range(nx - 1, -1, -1):
			var i := z * nx + x
			var v := d[i]
			if v == 0:
				continue
			if x < nx - 1:
				v = mini(v, d[i + 1] + 3)
			if z < nz - 1:
				v = mini(v, d[i + nx] + 3)
				if x < nx - 1:
					v = mini(v, d[i + nx + 1] + 4)
				if x > 0:
					v = mini(v, d[i + nx - 1] + 4)
			d[i] = v
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = float(d[i]) / 3.0
	return out

## Lowers the higher cell of any neighbouring land pair that differs by more than ISLAND_H_STEP_MAX voxels, one rung
## at a time, until none does. Only ever lowers, so it ends.
func _limit_steps() -> void:
	var smax: int = Style.ISLAND_H_STEP_MAX
	var changed := true
	while changed:
		changed = false
		for z in nz:
			for x in nx:
				var i := z * nx + x
				if land[i] == 0:
					continue
				for j in [i + 1 if x < nx - 1 else -1, i + nx if z < nz - 1 else -1]:
					if j < 0 or land[j] == 0:
						continue
					var a := rungs[rung[i]]
					var b := rungs[rung[j]]
					if a - b > smax:
						rung[i] -= 1
						changed = true
					elif b - a > smax:
						rung[j] -= 1
						changed = true

## A patch of equal height smaller than ISLAND_H_MIN_PATCH cells takes the most common rung around it (tie: the lower).
## Returns true when it changed anything.
func _merge_small_patches() -> bool:
	var n := nx * nz
	var label := PackedInt32Array()
	label.resize(n)
	label.fill(-1)
	var patches: Array[PackedInt32Array] = []
	for start in n:
		if land[start] == 0 or label[start] != -1:
			continue
		var id := patches.size()
		var cells := PackedInt32Array()
		var stack := PackedInt32Array()
		stack.append(start)
		label[start] = id
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			cells.append(i)
			var x := i % nx
			@warning_ignore("integer_division")
			var z := i / nx
			if x > 0 and land[i - 1] == 1 and label[i - 1] == -1 and rung[i - 1] == rung[start]:
				label[i - 1] = id
				stack.append(i - 1)
			if x < nx - 1 and land[i + 1] == 1 and label[i + 1] == -1 and rung[i + 1] == rung[start]:
				label[i + 1] = id
				stack.append(i + 1)
			if z > 0 and land[i - nx] == 1 and label[i - nx] == -1 and rung[i - nx] == rung[start]:
				label[i - nx] = id
				stack.append(i - nx)
			if z < nz - 1 and land[i + nx] == 1 and label[i + nx] == -1 and rung[i + nx] == rung[start]:
				label[i + nx] = id
				stack.append(i + nx)
		patches.append(cells)
	var changed := false
	for id in patches.size():
		var cells := patches[id]
		if cells.size() >= int(Style.ISLAND_H_MIN_PATCH):
			continue
		var counts := {}
		for i in cells:
			var x := i % nx
			@warning_ignore("integer_division")
			var z := i / nx
			var around := [i - 1 if x > 0 else -1, i + 1 if x < nx - 1 else -1, i - nx if z > 0 else -1, i + nx if z < nz - 1 else -1]
			for j in around:
				if j >= 0 and land[j] == 1 and label[j] != id:
					counts[rung[j]] = int(counts.get(rung[j], 0)) + 1
		if counts.is_empty():
			continue
		var keys := counts.keys()
		keys.sort()
		var best: int = keys[0]
		for k in keys:
			if int(counts[k]) > int(counts[best]):
				best = k
		for i in cells:
			rung[i] = best
		changed = true
	return changed

func _finish() -> void:
	var n := nx * nz
	vox.resize(n)
	levels.resize(n)
	min_vox = 1 << 30
	max_vox = 0
	var box_x0 := nx
	var box_z0 := nz
	var box_x1 := -1
	var box_z1 := -1
	for z in nz:
		for x in nx:
			var i := z * nx + x
			if land[i] == 0:
				vox[i] = 0
				levels[i] = 0
				continue
			vox[i] = rungs[rung[i]]
			levels[i] = roundi(float(vox[i]) / float(level_vox))
			min_vox = mini(min_vox, vox[i])
			max_vox = maxi(max_vox, vox[i])
			box_x0 = mini(box_x0, x)
			box_x1 = maxi(box_x1, x)
			box_z0 = mini(box_z0, z)
			box_z1 = maxi(box_z1, z)
	if box_x1 < 0:
		min_vox = 0
		meta = {}
		return
	# World box of the land like the terrain's meta: cell centres on whole numbers, y in world units from 0.
	meta = {
		"levels": levels, "heights_vox": vox, "level_vox": level_vox,
		"x0": x0, "z0": z0, "nx": nx, "nz": nz, "land": land,
		"min": Vector3(x0 + box_x0 - 0.5, 0.0, z0 + box_z0 - 0.5),
		"max": Vector3(x0 + box_x1 + 0.5, float(max_vox) * Voxel.VOXEL_SIZE, z0 + box_z1 + 0.5),
	}
