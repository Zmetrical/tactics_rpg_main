extends Resource
## One data type for weapon attacks, class skills and spells.

const CombatTuning = preload("res://scripts/battle/combat_tuning.gd")

enum Roll { ATTACK, SAVE, AUTO }
enum Stat { STR, DEX, CON, INT, WIS }
## Which defense pool soaks the hit (Physical Armor vs Magic Barrier) and which impact pool it feeds.
enum DamageType { PHYSICAL, MAGICAL }
## Scaling grade of `stat` into damage. NONE = no scaling, then E (weakest) up to S (strongest). See CombatTuning.GRADE_MULTIPLIER.
enum Grade { NONE, E, D, C, B, A, S }

@export var display_name: String = ""
## Action Points spent at Base tier. Weapon attacks and spells both use this; spells add a tier
## surcharge on top (see CombatTuning.tier_surcharge).
@export var ap_cost: float = CombatTuning.AP_ATTACK_COST
## 0 = weapon / at-will. 1..3 = the spell's power level. Labels it as a spell; it no longer
## spends a slot (Action Points replaced spell slots).
@export var slot_level: int = 0
## Manhattan tiles. 1 = melee.
@export var range_tiles: int = 1
## 0 = single target. >0 = every unit within this radius of the target tile.
@export var area_radius: int = 0
## FFT-style cast velocity. 0 = instant. Otherwise the spell is committed to a TILE and
## resolves ceil(100 / charge_speed) CT ticks later (higher = faster). Caster SPD is ignored.
@export var charge_speed: int = 0
@export var roll: Roll = Roll.ATTACK
## Caster stat: attack modifier (ATTACK) and spell DC (SAVE).
@export var stat: Stat = Stat.STR
## Stat the target rolls for a SAVE. A passed save halves the damage.
@export var save_stat: Stat = Stat.DEX
## Base hit chance in percent, before the attacker's DEX. Weapon type sets it. Only ATTACK rolls use it.
@export_range(5, 95) var accuracy: int = 75
## Turns the user must wait before using this again. 0 = no cooldown. 1 = unusable for the user's
## next turn. Weapon attacks leave this at 0.
@export var cooldown_turns: int = 0
## How strongly `stat` adds flat damage: floor(stat mod * grade multiplier). Negative mods add nothing. Applies to ATTACK, SAVE and AUTO.
@export var scaling_grade: Grade = Grade.NONE
@export var damage_dice: String = ""
@export var damage_bonus: int = 0
@export var damage_type: DamageType = DamageType.PHYSICAL
## Optional tooltip sentence for what this does, e.g. "Deals {dmg} to every unit in the [Spread]."
## A "\n" starts a new bullet. [Keyword] marks a glossary entry (scripts/spells/keywords.gd). {dmg} is filled from the dice, other
## {tokens} from the tuning files. Empty = AbilityText writes a plain default from the numbers above.
@export var effect_text: String = ""
## Optional tooltip sentence for how it is aimed, e.g. "Target: a direction (1 of 8)." Shown with the charge time,
## above a divider, apart from the effect. Same [Keyword] / {token} rules as effect_text.
@export var aim_text: String = ""

## Memory slots this skill / spell takes while memorized (1..3). Weapon attacks never use memory.
@export_range(1, 3) var memory_cost: int = 1

## AP needed to use this at `tier` (1 = Base). Weapons ignore the tier.
func ap_cost_for_tier(tier: int = 1) -> float:
	return ap_cost + CombatTuning.tier_surcharge(tier)

## True when the ability is committed now and resolves later.
func is_charged() -> bool:
	return charge_speed > 0

## Ticks between commit and resolution. 0 = instant.
func charge_ticks() -> int:
	if charge_speed <= 0:
		return 0
	return ceili(100.0 / charge_speed)
