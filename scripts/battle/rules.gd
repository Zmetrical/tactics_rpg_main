extends RefCounted
## All dice and roll logic. Static, RNG passed in so tests can seed it.

const Ability = preload("res://scripts/battle/ability.gd")
const Grid = preload("res://scripts/battle/grid.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const Tuning = preload("res://scripts/battle/combat_tuning.gd")

enum Mode { NORMAL, ADV, DIS }

static func mode_name(mode: int) -> String:
	match mode:
		Mode.ADV:
			return "Advantage"
		Mode.DIS:
			return "Disadvantage"
	return "Normal"

static func roll_d20(rng: RandomNumberGenerator, mode: int = Mode.NORMAL) -> int:
	var a := rng.randi_range(1, 20)
	if mode == Mode.NORMAL:
		return a
	var b := rng.randi_range(1, 20)
	return maxi(a, b) if mode == Mode.ADV else mini(a, b)

## "2d6" -> sum of two d6. Crit doubles the dice, not the bonus.
static func roll_dice(rng: RandomNumberGenerator, dice: String, double_dice: bool = false) -> int:
	if dice == "":
		return 0
	var parts := dice.to_lower().split("d")
	var count := parts[0].to_int()
	var sides := parts[1].to_int()
	if double_dice:
		count *= 2
	var total := 0
	for i in count:
		total += rng.randi_range(1, maxi(sides, 1))
	return total

## `attacker` adds the scaling bonus; null = none.
static func roll_damage(rng: RandomNumberGenerator, ability: Ability, double_dice: bool, attacker: Unit = null) -> int:
	return maxi(roll_dice(rng, ability.damage_dice, double_dice) + ability.damage_bonus + scaling_bonus(attacker, ability), 0)

## Flat damage from the ability's scaling grade: floor(max(stat mod, 0) * grade multiplier).
static func scaling_bonus(attacker: Unit, ability: Ability) -> int:
	if attacker == null or ability.scaling_grade == Ability.Grade.NONE:
		return 0
	return floori(maxi(attacker.mod(ability.stat), 0) * Tuning.grade_multiplier(ability.scaling_grade))

## Percent chance to land one strike: accuracy + DEX. Armor and resistances are not part of it.
static func hit_chance(attacker: Unit, ability: Ability) -> int:
	var raw := ability.accuracy + attacker.mod(Ability.Stat.DEX) * Tuning.ACCURACY_PER_DEX
	return clampi(raw, Tuning.HIT_CHANCE_MIN, Tuning.HIT_CHANCE_MAX)

## Chance after Advantage (two rolls, keep the success: 75 -> 94) or Disadvantage (keep the failure: 75 -> 56).
static func chance_with_mode(chance: int, mode: int) -> int:
	var p := chance / 100.0
	match mode:
		Mode.ADV:
			p = 1.0 - (1.0 - p) * (1.0 - p)
		Mode.DIS:
			p = p * p
	return roundi(p * 100.0)

## True when `attacker` stands behind or beside `defender` (not in the front half of its facing).
static func is_flanking(attacker: Unit, defender: Unit) -> bool:
	if defender.facing == Vector2i.ZERO:
		return false
	var v := attacker.cell - defender.cell
	return v.x * defender.facing.x + v.y * defender.facing.y <= 0

## The single place that decides advantage / disadvantage. Add new sources here only.
## Sources never stack; one of each cancels to NORMAL.
## ADV: target Exposed / Stunned / Silenced, flanking, restrained target, ranged from high ground.
## DIS: ranged while an enemy is adjacent, attacking uphill, target obscured (smoke / fog / foliage).
static func get_roll_mode(attacker: Unit, target: Unit, ability: Ability, all_units: Array) -> Mode:
	var adv := false
	var dis := false
	for id: StringName in Tuning.ADV_VS_STATUSES:
		if target.has_status(id):
			adv = true
	if target.has_status(Tuning.STATUS_RESTRAINED) or is_flanking(attacker, target):
		adv = true
	var diff := attacker.height - target.height
	if diff >= 1 and ability.range_tiles > 1:
		adv = true
	elif diff <= -1:
		dis = true
	if target.has_status(Tuning.STATUS_OBSCURED):
		dis = true
	if ability.range_tiles > 1:
		for u: Unit in all_units:
			if u.is_alive() and u.side != attacker.side and Grid.distance(u.cell, attacker.cell) == 1:
				dis = true
				break
	if adv and dis:
		return Mode.NORMAL
	if adv:
		return Mode.ADV
	if dis:
		return Mode.DIS
	return Mode.NORMAL

static func attack_roll(rng: RandomNumberGenerator, attacker: Unit, target: Unit, ability: Ability, mode: int) -> Dictionary:
	var roll := rng.randi_range(1, 100)
	if mode != Mode.NORMAL:
		var other := rng.randi_range(1, 100)
		# Hit = roll <= chance, so the lower die is the better one.
		roll = mini(roll, other) if mode == Mode.ADV else maxi(roll, other)
	return resolve_attack(rng, roll, attacker, target, ability)

## d100 <= hit chance hits. A miss rolls no damage. Roll <= CRIT_ROLL on a hit doubles the dice.
static func resolve_attack(rng: RandomNumberGenerator, roll: int, attacker: Unit, _target: Unit, ability: Ability) -> Dictionary:
	var chance := hit_chance(attacker, ability)
	var hit := roll <= chance
	var crit := hit and roll <= Tuning.CRIT_ROLL
	var damage := 0
	if hit:
		damage = roll_damage(rng, ability, crit, attacker)
	return {"roll": roll, "chance": chance, "hit": hit, "crit": crit, "damage": damage}

static func spell_dc(caster: Unit, ability: Ability) -> int:
	return 8 + caster.prof + caster.mod(ability.stat)

static func save_throw(rng: RandomNumberGenerator, caster: Unit, target: Unit, ability: Ability) -> Dictionary:
	return resolve_save(roll_d20(rng, Mode.NORMAL), caster, target, ability)

## d20 + stat mod + PROF >= DC.
static func resolve_save(d20: int, caster: Unit, target: Unit, ability: Ability) -> Dictionary:
	var dc := spell_dc(caster, ability)
	var total := d20 + target.mod(ability.save_stat) + target.prof
	return {"d20": d20, "total": total, "dc": dc, "success": total >= dc}

## Passed save halves (rounded down), failed save is full damage.
static func save_damage(base: int, success: bool) -> int:
	return base >> 1 if success else base
