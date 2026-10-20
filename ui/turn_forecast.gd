extends RefCounted
## Predicts upcoming turns without touching Battle. It replays Battle.pick_next() on COPIES of
## CT and cast timers: tick CT += SPD for living units, pick CT >= 100 (higher CT, then higher
## SPD, then player side, then list order), skip units that are mid-cast, count casts down
## after each tick. The current unit is entry 0 and its CT is reduced by 100 the way
## end_turn() does it. Exact unless a cast kills someone, a new cast starts, or the player
## changes the outcome; the bar is recomputed on every change, so it self-corrects.

const Unit = preload("res://scripts/battle/unit.gd")

const CT_THRESHOLD := 100
const MAX_STEPS := 2000
const KIND_TURN := &"turn"
const KIND_RELEASE := &"release"

## casts: rows of {"caster": Unit, "ticks": int, "spell": String}, oldest first.
## Returns up to `count` upcoming units. A fast unit can appear more than once.
static func predict(units: Array, casts: Array, current: Unit, count: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for e: Dictionary in predict_timeline(units, casts, current, count * 2 + casts.size()):
		if e["kind"] == KIND_TURN and out.size() < count:
			out.append(e["unit"])
	return out

## Same simulation, but charged-spell releases are part of the timeline. Returns up to `count`
## entries of {"kind": KIND_TURN | KIND_RELEASE, "unit": Unit, "spell": String}. A release lands
## right after the tick that brings its timer to 0 and before the next turn is picked, exactly
## where Battle._tick_casts() resolves it.
static func predict_timeline(units: Array, casts: Array, current: Unit, count: int) -> Array[Dictionary]:
	var ct: Dictionary = {}        # Unit -> int
	for u: Unit in units:
		if u.is_alive():
			ct[u] = u.ct
	var charging: Array[Dictionary] = []  # {"caster", "ticks", "spell"}, commit order
	for row: Dictionary in casts:
		charging.append({"caster": row["caster"], "ticks": int(row["ticks"]), "spell": String(row.get("spell", ""))})

	var order: Array[Dictionary] = []
	if current != null and ct.has(current):
		order.append({"kind": KIND_TURN, "unit": current, "spell": ""})
		ct[current] = int(ct[current]) - CT_THRESHOLD

	var guard := 0
	while order.size() < count and guard < MAX_STEPS:
		guard += 1
		var best: Unit = null
		for u: Unit in ct.keys():
			if int(ct[u]) >= CT_THRESHOLD and not _is_charging(charging, u) and (best == null or _goes_before(u, best, ct)):
				best = u
		if best != null:
			order.append({"kind": KIND_TURN, "unit": best, "spell": ""})
			ct[best] = int(ct[best]) - CT_THRESHOLD
			continue
		if ct.is_empty():
			break
		for u: Unit in ct.keys():
			ct[u] = int(ct[u]) + u.spd
		for c in charging:
			c["ticks"] = int(c["ticks"]) - 1
		for c in charging.duplicate():
			if int(c["ticks"]) <= 0:
				charging.erase(c)
				order.append({"kind": KIND_RELEASE, "unit": c["caster"], "spell": c["spell"]})
	return order

static func _is_charging(charging: Array[Dictionary], u: Unit) -> bool:
	for c in charging:
		if c["caster"] == u:
			return true
	return false

## Same ranking as Battle._goes_before, reading the copied CT.
static func _goes_before(a: Unit, b: Unit, ct: Dictionary) -> bool:
	var ca: int = int(ct[a])
	var cb: int = int(ct[b])
	if ca != cb:
		return ca > cb
	if a.spd != b.spd:
		return a.spd > b.spd
	return a.side == Unit.Side.PLAYER and b.side != Unit.Side.PLAYER
