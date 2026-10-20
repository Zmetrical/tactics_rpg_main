extends RefCounted
## World colours of the voxel overworld. HUD / plates / Label3D keep gbc_palette; only world geometry reads this.
## Material ids index MATERIALS and are stored per top voxel in VoxelGrid.mat.
enum Mat { NONE, GRASS_MINT, GRASS_PINE, BLOSSOM, CLIFF_PEACH, STONE, WATER, COBBLE, DIRT }
const GRASS_MINT := [Color("a8dcb0"), Color("7cc494"), Color("54a874"), Color("3a8460"), Color("286248")]   # mint to deep pine
const LAVENDER := [Color("e4d4f4"), Color("c8aee8"), Color("a88cd0")]
const CLIFF_PEACH := [Color("f8d8c0"), Color("f0c0a0"), Color("e0a484"), Color("c88868")]                 # strata bands
const STONE := [Color("8c90a0"), Color("6c7288"), Color("50566c")]
const WATER := [Color("b0e0f4"), Color("80c4ec"), Color("5ca8dc")]
const COBBLE := [Color("f0e8dc"), Color("dcd4c8")]
const DIRT := [Color("7c5c3c"), Color("684c30")]
const SEA := Color("e8f4fc")
## Grayscale gate: min luminance gap between path, ground, node and water ramps.
const MIN_LUMA_GAP := 0.08

static func luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

static func mean_luma(ramp: Array) -> float:
	var s := 0.0
	for c in ramp:
		s += luma(c)
	return s / float(ramp.size())

## Prints the separation of path (cobble, dirt), ground (mint), node (stone) and water. Returns true when
## every pair differs by at least MIN_LUMA_GAP.
static func grayscale_gate() -> bool:
	var named := {"cobble": COBBLE, "dirt": DIRT, "ground": GRASS_MINT, "stone": STONE, "water": WATER}
	var names := named.keys()
	names.sort()
	var ok := true
	for i in names.size():
		for j in range(i + 1, names.size()):
			var gap := absf(mean_luma(named[names[i]]) - mean_luma(named[names[j]]))
			var pass_ := gap >= MIN_LUMA_GAP
			ok = ok and pass_
			print("[palette] %s vs %s luma gap %.3f %s" % [names[i], names[j], gap, "ok" if pass_ else "TOO CLOSE"])
	return ok
