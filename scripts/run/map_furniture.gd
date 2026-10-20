extends Node3D
## Things that sit on the overworld without being part of it. Now: mist.
##
## Mist: at most MIST_COUNT large translucent billboards (Sprite3D, the 32 x 14 "mist" pixel sprite, which has a
## ragged outline and no straight edge), each drifting MIST_SPEED units per second along MIST_WIND over its own
## track and fading in and out at the track's ends, so nothing ever pops. Rules:
## - A mist cloud only exists on ground more than MIST_CLEAR cells from every reachable room, counting the cloud's
##   own radius: its opacity follows how far its nearest edge is past that line, over MIST_FADE_BAND, and chases that
##   value at 1 / MIST_FADE_TIME per second, so a room that becomes reachable (set_reachable) fades the cloud out.
## - A cloud and its whole track stay clear of the slab edge, so it is never drawn over a slab wall.
## - A cloud's home and every point of its track, with the four sides of its disc, lie over land cells (the is_land
##   callable passed to build_mist): no mist over the plain background beyond the coast.
## - Opacity never exceeds MIST_ALPHA (<= 0.4): at least 60% of the terrain colour shows through. Tracks are spaced
##   so two clouds never overlap in the world (they may still cross on screen, where the camera lines them up).
## Same (layout, seed) gives the same clouds. Build with build_mist() once, after the terrain.

const MapPixels = preload("res://data/run/map_pixels.gd")
const Layout = preload("res://scripts/run/overworld_layout.gd")

## These belong in overworld_style.gd by the project rule; that file is not part of this step.
const SALT := 0x315A
const MIST_COUNT := 6              # at most this many clouds (4 to this many are tried)
const MIST_MIN := 4
const MIST_WIDTH := 9.0            # world units across; the sprite is 32 px wide
const MIST_ALPHA := 0.35           # top opacity; keep <= 0.4
const MIST_SPEED := 1.0            # units per second
const MIST_TRACK := 5.0            # half the length of a drift track
const MIST_EDGE := 2.0             # units at each end of a track over which the cloud fades in / out
const MIST_CLEAR := 8.0            # no mist this close to a reachable room
const MIST_FADE_BAND := 3.0        # opacity ramps up over this many units past MIST_CLEAR
const MIST_FADE_TIME := 1.5        # seconds a cloud needs to fade fully in or out when rooms change
const MIST_BOTTOM := 0.4           # lowest edge of a cloud above the highest ground under it
const MIST_WIND := Vector2(0.8, 0.6)
const MIST_TRIES := 600

var _rooms: Array[Rect2] = []      # reachable rooms in world units (x / z), edges at cell borders
var _clouds: Array[Dictionary] = []   # {sprite, home: Vector2, phase: float, fade: float}
var _wind := MIST_WIND.normalized()
var _radius := MIST_WIDTH * 0.5
var _half_height := 0.0
var _height_fn := Callable()
var _is_land := Callable()   # Vector2i cell -> bool; invalid = every cell counts as land
var _time := 0.0

## Places the clouds. `reachable` = ids of the rooms the player can go to next, `slab_min` / `slab_max` the terrain's
## meta boxes (only x / z are read), `height_fn` the Vector2 -> ground height function, `is_land` the Vector2i cell -> bool
## land test (terrain.is_land). Prints what it placed.
@warning_ignore("shadowed_global_identifier")
func build_mist(layout: Layout.OverworldLayout, reachable: Array, slab_min: Vector3, slab_max: Vector3,
		height_fn: Callable, seed: int, is_land := Callable()) -> void:
	_height_fn = height_fn
	_is_land = is_land
	_rooms = _room_rects(layout, reachable)
	var tex := MapPixels.sprite("mist")
	if tex == null:
		return
	var pixel := MIST_WIDTH / float(tex.get_width())
	_half_height = tex.get_height() * pixel * 0.5
	var inset := _radius + MIST_TRACK + 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ SALT
	var want := rng.randi_range(mini(MIST_MIN, MIST_COUNT), MIST_COUNT)
	var spacing := MIST_WIDTH + 2.0 * MIST_TRACK   # tracks (and the clouds on them) never overlap
	var homes: Array[Vector2] = []
	for t in MIST_TRIES:
		if homes.size() >= want:
			break
		var p := Vector2(rng.randf_range(slab_min.x + inset, slab_max.x - inset), rng.randf_range(slab_min.z + inset, slab_max.z - inset))
		if _room_distance(p) < _radius + MIST_TRACK + MIST_CLEAR or not _over_land(p):
			continue
		var apart := true
		for h in homes:
			if h.distance_to(p) < spacing:
				apart = false
		if apart:
			homes.append(p)
	for h in homes:
		var s := Sprite3D.new()
		s.name = "Mist%d" % _clouds.size()
		s.texture = tex
		s.pixel_size = pixel
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.modulate = Color(1.0, 1.0, 1.0, 0.0)
		add_child(s)
		_clouds.append({"sprite": s, "home": h, "phase": rng.randf_range(0.0, 2.0 * MIST_TRACK), "fade": _room_fade(h)})
	_time = 0.0
	_update(0.0)
	var where := PackedStringArray()
	for h in homes:
		where.append("(%.0f, %.0f)" % [h.x, h.y])
	print("mist: %d clouds, %d reachable rooms kept clear by %.0f cells, at %s" % [homes.size(), _rooms.size(), MIST_CLEAR, ", ".join(where)])
	var off := 0
	for h in homes:
		if not _over_land(h):
			off += 1
	print("mist clouds not over land: %d" % off)

## The reachable rooms changed: clouds near the new ones fade out over MIST_FADE_TIME.
@warning_ignore("shadowed_global_identifier")
func set_reachable(layout: Layout.OverworldLayout, reachable: Array) -> void:
	_rooms = _room_rects(layout, reachable)

func _process(delta: float) -> void:
	_update(delta)

## Moves every cloud along its track and sets its opacity: MIST_ALPHA x track-end envelope x room fade.
func _update(delta: float) -> void:
	_time += delta
	var length := 2.0 * MIST_TRACK
	for c in _clouds:
		var along := fposmod(_time * MIST_SPEED + float(c["phase"]), length)
		var p: Vector2 = c["home"] + _wind * (along - MIST_TRACK)
		var env := smoothstep(0.0, MIST_EDGE, along) * smoothstep(0.0, MIST_EDGE, length - along)
		c["fade"] = move_toward(float(c["fade"]), _room_fade(p), delta / MIST_FADE_TIME)
		var s: Sprite3D = c["sprite"]
		var a := minf(MIST_ALPHA, 0.4) * env * float(c["fade"])
		s.modulate.a = a
		s.visible = a > 0.005
		s.position = Vector3(p.x, _ground_top(p) + MIST_BOTTOM + _half_height, p.y)

## true when a cloud homed at `p` is over land cells along its whole track: the centre, and the four sides of the disc
## (70% of its radius), sampled every unit from one end of the track to the other.
func _over_land(p: Vector2) -> bool:
	if not _is_land.is_valid():
		return true
	for t in range(-int(MIST_TRACK), int(MIST_TRACK) + 1):
		var c := p + _wind * float(t)
		for d in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var q: Vector2 = c + d * _radius * 0.7
			if not bool(_is_land.call(Vector2i(roundi(q.x), roundi(q.y)))):
				return false
	return true

## Highest ground under the cloud's disc (centre and four points on 70% of its radius), so it floats clear of it.
func _ground_top(p: Vector2) -> float:
	if not _height_fn.is_valid():
		return 0.0
	var top := float(_height_fn.call(p))
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		top = maxf(top, float(_height_fn.call(p + d * _radius * 0.7)))
	return top

## 0 within MIST_CLEAR of a reachable room (measured from the cloud's nearest edge), 1 from MIST_FADE_BAND further.
func _room_fade(p: Vector2) -> float:
	if _rooms.is_empty():
		return 1.0
	return smoothstep(0.0, MIST_FADE_BAND, _room_distance(p) - _radius - MIST_CLEAR)

## Distance from `p` to the nearest reachable room's footprint (INF with none).
func _room_distance(p: Vector2) -> float:
	var best := INF
	for r in _rooms:
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		best = minf(best, Vector2(dx, dz).length())
	return best

@warning_ignore("shadowed_global_identifier")
static func _room_rects(layout: Layout.OverworldLayout, reachable: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for id in reachable:
		if layout.rooms.has(id):
			var fp: Rect2i = layout.rooms[id]
			out.append(Rect2(Vector2(fp.position) - Vector2(0.5, 0.5), Vector2(fp.size)))
	return out
