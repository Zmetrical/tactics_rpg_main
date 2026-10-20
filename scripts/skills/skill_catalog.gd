extends RefCounted
## Every learnable skill, as data. Two per archetype to start (a rank 1 skill and a rank 2 skill).
## Add one by appending a row to ROWS. Numbers are first-pass: tune them here.
##
## Only mechanics the engine already has are used: damage dice / type, scaling, area, charge time,
## cooldown, and the status riders on SkillDef (exposed / restrained / wet). Effects the engine can't do yet
## (leaps, taunts, stealth, terrain, pushes) are listed in docs/skills.md, not promised in the tooltips.

const SkillDef = preload("res://scripts/skills/skill_def.gd")
const Ability = preload("res://scripts/battle/ability.gd")
const Discipline = preload("res://scripts/skills/discipline.gd")

const P := Ability.DamageType.PHYSICAL
const M := Ability.DamageType.MAGICAL
const ATK := Ability.Roll.ATTACK
const SAVE := Ability.Roll.SAVE
const AUTO := Ability.Roll.AUTO
const STR := Ability.Stat.STR
const DEX := Ability.Stat.DEX
const CON := Ability.Stat.CON
const INT := Ability.Stat.INT
const WIS := Ability.Stat.WIS

## id, name, discipline (primary), archetype, req_rank (rank in the primary discipline), roll, stat, save_stat, damage_type, dice, grade (Ability.Grade),
## range, area, charge_speed, cooldown, ap, extras{}  (extras "mem" = memory slots taken, 1..3; default 1)
static func _rows() -> Array:
	return [
		# --- Warrior / Vanguard (STR) ---
		[&"leaping_strike", "Leaping Strike", &"warrior", &"vanguard", 1, ATK, STR, DEX, P, "1d8", 4, 3, 0, 0, 1, 1.5,
			{"effect": "Strikes an enemy up to 3 tiles away for {dmg}. Builds Armor Shred."}],
		[&"shockwave_slam", "Shockwave Slam", &"warrior", &"vanguard", 2, SAVE, STR, DEX, P, "2d6", 3, 2, 1, 0, 2, 2.5,
			{"mem": 2, "effect": "Deals {dmg} to every unit within 1 tile of the target. Enemies hit are Restrained for 1 turn.",
			 "status": &"restrained", "turns": 1}],
		# --- Warrior / Sentinel (STR, scales CON) ---
		[&"iron_rebuke", "Iron Rebuke", &"warrior", &"sentinel", 1, ATK, CON, DEX, P, "1d6", 5, 1, 0, 0, 0, 1.5,
			{"effect": "A retaliating blow for {dmg}. Damage scales with CON."}],
		[&"anchor_smash", "Anchor Smash", &"warrior", &"sentinel", 2, ATK, STR, DEX, P, "1d10", 4, 1, 0, 0, 2, 2.0,
			{"mem": 2, "effect": "A crushing blow for {dmg}. The target is Exposed for 1 turn.", "status": &"exposed", "turns": 1}],
		# --- Rogue / Assassin (DEX) ---
		[&"backstab", "Backstab", &"rogue", &"assassin", 1, ATK, DEX, DEX, P, "2d6", 4, 1, 0, 0, 1, 1.5,
			{"effect": "A precise strike for {dmg}. Flanking gives it Advantage."}],
		[&"death_mark", "Death Mark", &"rogue", &"assassin", 2, ATK, DEX, DEX, P, "1d4", 2, 4, 0, 0, 2, 1.0,
			{"mem": 2, "effect": "Marks an enemy up to 4 tiles away for {dmg}. The target is Exposed for 2 turns, so attacks against it have Advantage.",
			 "status": &"exposed", "turns": 2}],
		# --- Rogue / Skirmisher (DEX) ---
		[&"skirmish_cut", "Skirmish Cut", &"rogue", &"skirmisher", 1, ATK, DEX, DEX, P, "1d6", 3, 1, 0, 0, 0, 1.0,
			{"effect": "A quick cut for {dmg}. Cheap enough to use twice a turn."}],
		[&"sidearm_shot", "Sidearm Shot", &"rogue", &"skirmisher", 2, ATK, DEX, DEX, P, "1d6", 4, 4, 0, 0, 0, 1.0,
			{"mem": 2, "effect": "A mid-range shot for {dmg}.", "accuracy": 70}],
		# --- Ranger / Deadeye (DEX) ---
		[&"aimed_shot", "Aimed Shot", &"ranger", &"deadeye", 1, ATK, DEX, DEX, P, "1d10", 5, 8, 0, 0, 1, 2.0,
			{"effect": "A steady shot up to 8 tiles for {dmg}. High ground gives it Advantage."}],
		[&"headshot", "Headshot", &"ranger", &"deadeye", 2, ATK, DEX, DEX, P, "2d8", 5, 7, 0, 0, 2, 3.0,
			{"mem": 3, "effect": "A devastating shot for {dmg}.", "accuracy": 65}],
		# --- Ranger / Pathfinder (DEX) ---
		[&"snare_shot", "Snare Shot", &"ranger", &"pathfinder", 1, ATK, DEX, DEX, P, "1d4", 2, 6, 0, 0, 1, 1.5,
			{"effect": "A pinning shot for {dmg}. The target is Restrained for 1 turn.", "status": &"restrained", "turns": 1}],
		[&"briar_trap", "Briar Trap", &"ranger", &"pathfinder", 2, SAVE, DEX, DEX, P, "1d8", 3, 5, 1, 25, 2, 2.0,
			{"mem": 2, "effect": "Lay a trap on a tile. It springs after a short delay, dealing {dmg} to every unit within 1 tile, who are then Restrained for 1 turn.",
			 "status": &"restrained", "turns": 1}],
		# --- Tempest (INT) ---
		[&"gale_lance", "Gale Lance", &"tempest", &"tempest", 1, SAVE, INT, DEX, M, "2d6", 4, 9, 0, 20, 0, 1.5,
			{"effect": "A long-range lance of wind for {dmg}."}],
		[&"static_field", "Static Field", &"tempest", &"tempest", 2, SAVE, INT, DEX, M, "1d8", 3, 7, 1, 16, 1, 2.5,
			{"mem": 2, "effect": "Charges a tile, then deals {dmg} to every unit within 1 tile."}],
		# --- Torrent (INT) ---
		[&"drench", "Drench", &"torrent", &"torrent", 1, AUTO, INT, DEX, M, "1d4", 2, 6, 0, 0, 0, 1.0,
			{"effect": "Soaks an enemy for {dmg}. Wet for 2 turns.", "status": &"wet", "turns": 2}],
		[&"glacial_spike", "Glacial Spike", &"torrent", &"torrent", 2, SAVE, INT, DEX, M, "3d8", 5, 6, 0, 14, 2, 3.0,
			{"mem": 3, "effect": "Hurls a spike of ice for {dmg}. A Wet target takes 50% more, which shatters Magic Barrier.",
			 "vs": &"wet", "vs_mult": 1.5}],
		# --- Cinder (INT) ---
		[&"flame_arc", "Flame Arc", &"cinder", &"cinder", 1, SAVE, INT, DEX, M, "2d6", 3, 2, 1, 0, 0, 1.5,
			{"effect": "A sweep of flame within 2 tiles, dealing {dmg} to every unit within 1 tile of the target. Allies and the caster are caught too."}],
		[&"pyre_burst", "Pyre Burst", &"cinder", &"cinder", 2, SAVE, INT, DEX, M, "3d6", 4, 3, 2, 18, 2, 3.0,
			{"mem": 3, "effect": "Ignites a tile, then deals {dmg} to every unit within 2 tiles. Allies and the caster are caught too."}],
		# --- Verdant (WIS) ---
		[&"thorn_lash", "Thorn Lash", &"verdant", &"verdant", 1, AUTO, WIS, DEX, M, "1d6", 3, 4, 0, 0, 0, 1.0,
			{"effect": "A whip of thorns for {dmg}. The target is Restrained for 1 turn.", "status": &"restrained", "turns": 1}],
		[&"vine_snare", "Vine Snare", &"verdant", &"verdant", 2, SAVE, WIS, STR, M, "1d8", 3, 5, 1, 0, 2, 2.5,
			{"mem": 2, "effect": "Vines burst up under every unit within 1 tile, dealing {dmg} and Restraining enemies for 2 turns.",
			 "status": &"restrained", "turns": 2}],
		# --- Tremor (WIS) ---
		[&"seismic_jolt", "Seismic Jolt", &"tremor", &"tremor", 1, AUTO, WIS, CON, M, "2d4", 3, 6, 1, 0, 0, 1.5,
			{"effect": "A jolt through the ground, dealing {dmg} to every unit within 1 tile. Magical damage builds Fracture."}],
		[&"rending_quake", "Rending Quake", &"tremor", &"tremor", 2, SAVE, WIS, CON, M, "2d6", 4, 5, 2, 14, 2, 3.0,
			{"mem": 3, "effect": "A localized quake that lands after a short delay, dealing {dmg} to every unit within 2 tiles. Heavy Fracture."}],
		# --- Hybrids: need ranks in several disciplines (cross-school). Primary discipline sets the stat. ---
		[&"steam_burst", "Steam Burst", &"cinder", &"cinder", 1, SAVE, INT, DEX, M, "2d8", 4, 5, 1, 18, 1, 2.5,
			{"mem": 2, "effect": "Fire meets water: scalds every unit within 1 tile of a charged tile for {dmg}. Wet for 1 turn.",
			 "req": {&"cinder": 2, &"torrent": 1}, "status": &"wet", "turns": 1}],
		[&"storm_surge", "Storm Surge", &"tempest", &"tempest", 1, SAVE, INT, DEX, M, "2d6", 4, 7, 0, 20, 1, 2.5,
			{"mem": 2, "effect": "Lightning through water: strikes one target for {dmg}. A Wet target takes 50% more.",
			 "req": {&"tempest": 2, &"torrent": 1}, "vs": &"wet", "vs_mult": 1.5}],
		[&"mudslide", "Mudslide", &"tremor", &"tremor", 1, SAVE, WIS, STR, M, "1d8", 3, 5, 1, 0, 1, 2.5,
			{"mem": 2, "effect": "Earth and water: a surge of mud dealing {dmg} to every unit within 1 tile. Enemies hit are Restrained for 1 turn.",
			 "req": {&"tremor": 2, &"torrent": 1}, "status": &"restrained", "turns": 1}],
		[&"thorn_volley", "Thorn Volley", &"ranger", &"pathfinder", 1, ATK, DEX, DEX, P, "1d8", 4, 6, 0, 0, 1, 2.0,
			{"mem": 2, "effect": "A shot wrapped in vines for {dmg}. The target is Restrained for 1 turn.",
			 "req": {&"ranger": 2, &"verdant": 1}, "status": &"restrained", "turns": 1}],
	]

static var _cache: Array[SkillDef] = []

static func all() -> Array[SkillDef]:
	if _cache.is_empty():
		for r: Array in _rows():
			_cache.append(_build(r))
	return _cache

static func by_id(id: StringName) -> SkillDef:
	for s in all():
		if s.skill_id == id:
			return s
	return null

static func in_discipline(discipline: StringName) -> Array[SkillDef]:
	var out: Array[SkillDef] = []
	for s in all():
		if s.discipline == discipline:
			out.append(s)
	return out

static func in_archetype(discipline: StringName, archetype: StringName) -> Array[SkillDef]:
	var out: Array[SkillDef] = []
	for s in in_discipline(discipline):
		if s.archetype == archetype:
			out.append(s)
	return out

static func _build(r: Array) -> SkillDef:
	var extras: Dictionary = r[16]
	var s := SkillDef.new()
	s.skill_id = r[0]
	s.display_name = r[1]
	s.discipline = r[2]
	s.archetype = r[3]
	s.school = Discipline.display_name(s.discipline)
	s.subschool = Discipline.archetype_name(s.discipline, s.archetype)
	# "req" in extras overrides the single requirement: {discipline: rank, ...}. The unit needs all of them.
	s.requirements = extras.get("req", {s.discipline: int(r[4])})
	if s.requirements.size() > 1:
		var names: Array[String] = []
		for d: StringName in s.requirements.keys():
			names.append(Discipline.display_name(d))
		s.school = " + ".join(names)
		s.subschool = "Hybrid"
	s.roll = r[5]
	s.stat = r[6]
	s.save_stat = r[7]
	s.damage_type = r[8]
	s.damage_dice = r[9]
	s.scaling_grade = r[10]
	s.range_tiles = r[11]
	s.area_radius = r[12]
	s.charge_speed = r[13]
	s.cooldown_turns = r[14]
	s.ap_cost = r[15]
	s.slot_level = 0
	s.memory_cost = clampi(int(extras.get("mem", 1)), 1, 3)
	s.accuracy = int(extras.get("accuracy", 75))
	s.effect_text = String(extras.get("effect", ""))
	s.apply_status = extras.get("status", &"")
	s.apply_status_turns = int(extras.get("turns", 1))
	s.vs_status = extras.get("vs", &"")
	s.vs_status_mult = float(extras.get("vs_mult", 1.0))
	return s
