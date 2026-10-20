extends RefCounted
## The eight skill disciplines, the attribute each one runs on, and the archetypes (skill schools) inside them.
## Pure data. A unit's rank in a discipline lives on UnitData.discipline_ranks.
##
## Learning a SkillDef needs only the discipline rank ("Requires 2 Rogue"), so a unit can freely cross-class:
## a Fighter with 2 Rogue ranks can learn Rogue skills. The stat is what the discipline's skills scale with.

const Ability = preload("res://scripts/battle/ability.gd")

enum Branch { COMBAT, TECHNIQUES, ARCANE, DIVINE }

## discipline id -> definition. `archetypes` is ordered; each has a short design blurb for tooltips / UI.
const DEFS := {
	&"warrior": {
		"name": "Warrior", "branch": Branch.COMBAT, "stat": Ability.Stat.STR,
		"blurb": "Frontline survivability, physical dominance and stacking Armor Shred.",
		"archetypes": {
			&"vanguard": {"name": "Vanguard", "blurb": "Mobile initiators: leap into the fray, AoE crowd control, baseline Shred."},
			&"sentinel": {"name": "Sentinel", "blurb": "Immovable protectors: taunts, intercepts and chokepoint anchors. Scales with CON and STR."},
		},
	},
	&"rogue": {
		"name": "Rogue", "branch": Branch.TECHNIQUES, "stat": Ability.Stat.DEX,
		"blurb": "Mobility, positioning and exploiting Advantage to pierce physical defenses.",
		"archetypes": {
			&"assassin": {"name": "Assassin", "blurb": "Precision burst from stealth, backstabs and Flanking."},
			&"skirmisher": {"name": "Skirmisher", "blurb": "Hit-and-run momentum fighters: sidearms, vaults and shoves into hazards."},
		},
	},
	&"ranger": {
		"name": "Ranger", "branch": Branch.TECHNIQUES, "stat": Ability.Stat.DEX,
		"blurb": "Mobility, positioning and exploiting Advantage to pierce physical defenses.",
		"archetypes": {
			&"deadeye": {"name": "Deadeye", "blurb": "Pure ranged hyper-carry. High Ground Advantage and frontline protection."},
			&"pathfinder": {"name": "Pathfinder", "blurb": "Grid control: traps, difficult terrain and Overwatch reaction shots."},
		},
	},
	&"tempest": {
		"name": "Tempest", "branch": Branch.ARCANE, "stat": Ability.Stat.INT,
		"blurb": "Wind and lightning. Artillery: extreme-range bombardment, chain lightning, updrafts.",
		"archetypes": {&"tempest": {"name": "Tempest", "blurb": "The artillery school."}},
	},
	&"torrent": {
		"name": "Torrent", "branch": Branch.ARCANE, "stat": Ability.Stat.INT,
		"blurb": "Water and ice. Soak a target, then shatter its Magic Barrier with one glacial spike.",
		"archetypes": {&"torrent": {"name": "Torrent", "blurb": "The execution school."}},
	},
	&"cinder": {
		"name": "Cinder", "branch": Branch.ARCANE, "stat": Ability.Stat.INT,
		"blurb": "Fire. Close-quarters battlemage: auras, sweeping arcs of flame, burning tiles.",
		"archetypes": {&"cinder": {"name": "Cinder", "blurb": "The close-quarters battlemage school."}},
	},
	&"verdant": {
		"name": "Verdant", "branch": Branch.DIVINE, "stat": Ability.Stat.WIS,
		"blurb": "Grass and nature. Healing flora, cleansing, and vines that raise Resolve.",
		"archetypes": {&"verdant": {"name": "Verdant", "blurb": "The enchanter and protection school."}},
	},
	&"tremor": {
		"name": "Tremor", "branch": Branch.DIVINE, "stat": Ability.Stat.WIS,
		"blurb": "Rock and earth. Pillars, mud hazards and quakes that stack Fracture on casters.",
		"archetypes": {&"tremor": {"name": "Tremor", "blurb": "The disruptor and grid control school."}},
	},
}

const BRANCH_NAMES := {
	Branch.COMBAT: "Combat", Branch.TECHNIQUES: "Techniques",
	Branch.ARCANE: "Arcane Skill Attributes", Branch.DIVINE: "Divine Skill Attributes",
}

static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in DEFS.keys():
		out.append(id)
	return out

static func exists(id: StringName) -> bool:
	return DEFS.has(id)

static func display_name(id: StringName) -> String:
	return String(DEFS[id]["name"]) if DEFS.has(id) else String(id).capitalize()

## The Ability.Stat this discipline is built on (Warrior = STR, Rogue / Ranger = DEX, ...).
static func stat_of(id: StringName) -> int:
	return int(DEFS[id]["stat"]) if DEFS.has(id) else Ability.Stat.STR

static func branch_of(id: StringName) -> int:
	return int(DEFS[id]["branch"]) if DEFS.has(id) else Branch.COMBAT

static func archetype_ids(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if DEFS.has(id):
		for a: StringName in DEFS[id]["archetypes"].keys():
			out.append(a)
	return out

static func archetype_name(id: StringName, archetype: StringName) -> String:
	if DEFS.has(id) and DEFS[id]["archetypes"].has(archetype):
		return String(DEFS[id]["archetypes"][archetype]["name"])
	return String(archetype).capitalize()

static func stat_letters(stat: int) -> String:
	return String(Ability.Stat.keys()[stat])
