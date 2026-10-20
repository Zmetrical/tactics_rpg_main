extends RefCounted
## spell id -> behaviour. One shared instance per spell (behaviours hold no state).

const SpellBehavior = preload("res://scripts/spells/spell_behavior.gd")
const ChainArc = preload("res://scripts/spells/aeromancy/chain_arc.gd")
const Thunder = preload("res://scripts/spells/aeromancy/thunder.gd")
const Bolt = preload("res://scripts/spells/aeromancy/bolt.gd")
const Surge = preload("res://scripts/spells/aeromancy/surge.gd")

static var _cache: Dictionary = {}

static func _scripts() -> Dictionary:
	return {
		&"chain_arc": ChainArc,
		&"thunder": Thunder,
		&"bolt": Bolt,
		&"surge": Surge,
	}

static func behavior_for(spell_id: StringName) -> SpellBehavior:
	if _cache.has(spell_id):
		return _cache[spell_id]
	var scripts := _scripts()
	if not scripts.has(spell_id):
		push_error("No spell behaviour registered for '%s'" % spell_id)
		return null
	var b: SpellBehavior = scripts[spell_id].new()
	_cache[spell_id] = b
	return b

static func has_behavior(spell_id: StringName) -> bool:
	return _scripts().has(spell_id)
