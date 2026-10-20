extends RefCounted
## Every balance number for the Dual-Pool Ablative Defense / Threshold / Cascading Status system.
## Change numbers here only; unit.gd contains no magic values.

## Hits feed an impact pool (after the armor/barrier resist). One stack is earned per full
## THRESHOLD_FRACTION of max Core Health in the pool. Leftover progress below one threshold stays
## across hits, but is wiped when that unit starts its turn.
const THRESHOLD_FRACTION := 0.12
## Float safety margin so 3.0 / 3.0000000000000004 still counts as one full threshold.
const THRESHOLD_EPSILON := 0.000001
const MAX_STACKS := 7

## While the defender still has Physical Armor (physical hits) or Magic Barrier (magic hits) when the
## hit lands, this fraction of the damage is NOT counted toward Armor Shred / Fracture.
## 0.30 = 30% resist. Damage to the pools and Core Health is unaffected.
const IMPACT_RESIST_WHILE_DEFENDED := 0.30

# --- Hit chance / Advantage ---------------------------------------------------
## Hit chance is accuracy, not armor penetration: Ability.accuracy + DEX mod * ACCURACY_PER_DEX, in percent.
## A miss deals 0 damage and adds 0 Armor Shred / Fracture. Armor never changes hit chance.
const ACCURACY_PER_DEX := 2
const HIT_CHANCE_MIN := 5
const HIT_CHANCE_MAX := 95
## A hit whose d100 is at or under this is a critical hit (doubles the dice).
const CRIT_ROLL := 5

## Statuses read by Rules.get_roll_mode. Set them with Unit.statuses[id] = turns.
const STATUS_EXPOSED := &"exposed"
const STATUS_RESTRAINED := &"restrained"
const STATUS_OBSCURED := &"obscured"
## Attacking a target with any of these = Advantage. stun / silence come from Overload.
const ADV_VS_STATUSES: Array[StringName] = [&"exposed", &"stun", &"silence"]

# --- Skill slots ------------------------------------------------------------
## Learned skills and spells a unit can hold at once. UnitData.skill_slots overrides it per unit.
const DEFAULT_SKILL_SLOTS := 4

# --- Skills -----------------------------------------------------------------
## Statuses used by skills. exposed / restrained are read by Rules.get_roll_mode; wet is read by SkillDef.vs_status.
const STATUS_WET := &"wet"

# --- Scaling grades ---------------------------------------------------------
## Flat damage per point of stat mod, by Ability.Grade (index 0 = NONE). Damage bonus = floor(mod * this).
const GRADE_MULTIPLIER: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0]
const GRADE_LETTERS: Array[String] = ["-", "E", "D", "C", "B", "A", "S"]

static func grade_multiplier(grade: int) -> float:
	return GRADE_MULTIPLIER[clampi(grade, 0, GRADE_MULTIPLIER.size() - 1)]

static func grade_letter(grade: int) -> String:
	return GRADE_LETTERS[clampi(grade, 0, GRADE_LETTERS.size() - 1)]

# --- Stat effects (only positive mods count; a negative mod is the same as 0) ---
## STR (attacker): Shred bonus. Physical impact the hit feeds Armor Shred is x(1 + mod * this).
const SHRED_PER_STR := 0.10
## DEX (attacker): Pierce. This fraction of physical damage skips Physical Armor and hits Core Health.
const PIERCE_PER_DEX := 0.05
## INT (attacker): Magic Pen. This fraction of magical damage skips Magic Barrier and hits Core Health.
const MAGIC_PEN_PER_INT := 0.05
## Pierce and Magic Pen never exceed this fraction.
const PEN_MAX := 0.5
## WIS (defender): Resolve. Impact taken (both pools) is x(1 - mod * this), so stacks build slower.
const RESOLVE_PER_WIS := 0.05
const RESOLVE_MAX := 0.5
## CON (defender): Fracture bonus. The magical impact needed per Fracture stack is x(1 + mod * this).
const FRACTURE_THRESHOLD_PER_CON := 0.08
const FRACTURE_THRESHOLD_BONUS_MAX := 0.5

# --- Action Points ----------------------------------------------------------
## Every weapon attack and spell costs AP. Spells can be cast at Tier 1 (Base), 2 or 3 by paying a
## surcharge, so the tier is a per-cast choice, not something a unit "learns".
## All values are multiples of 0.5, which floats store exactly, so sums never drift.
const AP_MAX := 8.0
## AP recovered at the start of each unit's own turn (capped at AP_MAX).
const AP_REGEN := 2.0
## Default cost of any weapon attack or spell at Base tier. An Ability can override it with ap_cost.
const AP_ATTACK_COST := 1.5
const AP_TIER2_SURCHARGE := 1.5
const AP_TIER3_SURCHARGE := 3.5

## Extra AP a spell costs when cast at `tier` (1 = Base = no surcharge).
static func tier_surcharge(tier: int) -> float:
	match tier:
		2:
			return AP_TIER2_SURCHARGE
		3:
			return AP_TIER3_SURCHARGE
	return 0.0

## Stacks needed (and consumed) for Tier 3 Overload.
const OVERLOAD_STACK_COST := 5
## Armor Shred / Fracture stacks needed for Tier 2 Breach (stacks are not consumed).
const BREACH_STACK_REQUIREMENT := 3

## OFF = TakeDamage follows the spec exactly (ablative -> accumulate -> stacks) and resistance only
## exists as the thing Disrupt lowers. ON = damage is first scaled by (1 - resistance).
const APPLY_RESISTANCE_IN_TAKE_DAMAGE := false

## Resistance is a fraction: damage taken = amount * (1 - resistance).
const RESISTANCE_MAX := 0.9
const RESISTANCE_MIN := -0.5

## Tier 1 Disrupt: how much the OTHER resistance drops (physical status -> magic_resistance).
const DISRUPT_RESISTANCE_REDUCTION := 0.10

## Placeholder effect ids and durations (in turns). Nothing reads these yet except
## Unit.statuses; hook your stun / movement-cripple behavior to those ids.
const EFFECT_OVERLOAD := {0: &"stun", 1: &"silence"}          # keyed by StatusCategory
const EFFECT_BREACH := {0: &"movement_cripple", 1: &"cast_cripple"}
const OVERLOAD_TURNS := 1
const BREACH_TURNS := 2
