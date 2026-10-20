extends RefCounted
## One thing the player must decide before a spell can be committed.
## A spell is an ordered list of these: Chain Arc = [UNIT, PIVOT], Surge = [PATH, FORK, FORK].

enum Kind {
	UNIT,       ## click a hostile unit (locks on and follows it while charging)
	TILE,       ## click any tile; may lock onto the unit standing there
	DIRECTION,  ## pick a compass direction from the caster
	PIVOT,      ## rotate a fixed-range hitbox around the previous step's anchor
	PATH,       ## draw a tile-by-tile path out of the caster
	FORK,       ## draw a path out of the previous step's first victim (stored relative to it)
}

var kind: Kind = Kind.UNIT
var label: String = ""
## UNIT / TILE: unused (the spell's range applies). DIRECTION: ray length. PIVOT: arm reach.
## PATH / FORK: the tile cap.
var reach: int = 0
## Optional steps can be skipped (Enter). Everything after a skipped step is skipped too.
var optional := false
## TILE only: the player may choose to lock onto the unit on the tile.
var lockable := false
## DIRECTION / PIVOT: snap to the 4 cardinal directions only (no diagonals).
var cardinal := false

static func make(p_kind: Kind, p_label: String, p_reach: int = 0, p_optional: bool = false, p_lockable: bool = false, p_cardinal: bool = false) -> RefCounted:
	var s: RefCounted = load("res://scripts/spells/aim_step.gd").new()
	s.kind = p_kind
	s.label = p_label
	s.reach = p_reach
	s.optional = p_optional
	s.lockable = p_lockable
	s.cardinal = p_cardinal
	return s
