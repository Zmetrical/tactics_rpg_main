# Dual-Pool Ablative Defense, Threshold Accumulator, Cascading Status

Code: `Unit.take_damage(amount, type)` and `Unit.apply_cascading_status(category)` in
`scripts/battle/unit.gd`. All numbers live in `scripts/battle/combat_tuning.gd`.
Tests: `godot --headless -s tests/test_defense.gd`

## Phase 1: `take_damage(amount, type)` (type = `Ability.DamageType.PHYSICAL | MAGICAL`)
Exact spec order. (Optional, off by default: `APPLY_RESISTANCE_IN_TAKE_DAMAGE` in `combat_tuning.gd` scales
damage by `1 - resistance` first. Until it is on, Disrupt lowers resistance but nothing reads it.)
1. Ablative: Physical Armor (physical) / Magic Barrier (magical) absorbs first; the remainder hits Core Health.
2. Accumulate: `dealt` (defense + core) is added to `physical_impact_pool` / `magic_impact_pool`.
   If the defender still had Physical Armor (physical hit) or Magic Barrier (magic hit) when the hit
   landed, only 70% is added (`IMPACT_RESIST_WHILE_DEFENDED` = 0.30). Damage taken is unchanged.
3. Stacks: one Armor Shred / Fracture per full 12% of `max_hp` in the pool, cap 7. Full thresholds are
   consumed even when the cap swallows the stack. The sub-threshold remainder stays in the pool across
   hits (small hits add up), but `Unit.start_turn()` wipes both pools, so unfinished progress is lost when
   the unit's turn begins. Earned stacks are kept.

Returns `{incoming, after_resistance, to_defense, to_core, stacks_gained}`.
Zero/negative damage and damage to dead units are ignored.

## Phase 2: `apply_cascading_status(category)` (call on the TARGET)
First match wins:

| Tier | Check (physical / magical) | Result |
|---|---|---|
| 3 Overload | `armor_shred_stacks` / `fracture_stacks` >= 5 | consume 5 stacks, record effect |
| 2 Breach | `armor_shred_stacks` / `fracture_stacks` >= 3 | record effect, no stacks consumed |
| 1 Disrupt | always | `magic_resistance` / `physical_resistance` -= 0.10 (floor -0.5) |

Returns `{tier, effect, stacks_consumed, resistance_delta}`. Overload/Breach effects are stored in
`Unit.statuses` (effect id -> turns left). Nothing consumes them yet.

## Integration
- `hp` / `max_hp` remain the Core Health fields; `current_core_health` / `max_core_health` alias them.
- `Ability.damage_type` (default PHYSICAL). Fire Bolt and Burning Burst are MAGICAL.
- `Battle._apply_damage` passes the ability's type and adds `report` to each result.
- `UnitData` gained `physical_armor`, `magic_barrier`, `physical_resistance`, `magic_resistance` (all default 0, so
  existing units behave exactly as before until you give them values).

## Gear: Physical Armor = physical health, Magic Barrier = magic health
`Item.physical_armor` / `Item.magic_barrier`, summed by `Equipment.total_defense(property)`. Gear sets the pool ceiling
(`max_physical_armor` / `max_magic_barrier`). A unit spawns full. Mid-battle equipping only raises the ceiling;
unequipping lowers it and clamps the current value. Re-equipping never refills, so swapping gear
can't heal. Gear does not touch resistance.

| Item | Physical Armor | Magic Barrier |
|---|---|---|
| Iron Cuirass | 8 | |
| Iron Greaves | 4 | |
| Iron Helm | 3 | |
| Tower Shield | 6 | |
| Leather Brace | 2 | |
| Sun Amulet | | 6 |
| Spellbook | | 4 |
| Jade Ring | | 3 |
| Silver Ring | | 3 |
| Copper Ring | | 2 |

Tooltips on equipment slots show the bonus (`Item.defense_summary()`).
`tests/test_combat_director.gd` zeroes gear defense in `mk_unit` because it asserts raw HP loss.
