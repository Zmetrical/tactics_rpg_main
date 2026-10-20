# Action Points (AP)

AP replaced the old Action / Bonus / Reaction pips and spell slots. Every weapon attack and spell spends AP.

## Rules (all numbers in `scripts/battle/combat_tuning.gd`)
| Rule | Value |
|---|---|
| Max AP per unit | 8 (`AP_MAX`) |
| Recovered at the start of each unit's own turn | +2 (`AP_REGEN`), capped at the max |
| Starting AP | 0, so a unit's first turn begins with 2 |
| Weapon attack or spell, Base | 1.5 (`AP_ATTACK_COST`, per-ability override: `Ability.ap_cost`) |
| Spell at Tier 2 | +1.5 = 3 total (`AP_TIER2_SURCHARGE`) |
| Spell at Tier 3 | +3.5 = 5 total (`AP_TIER3_SURCHARGE`) |
| Opportunity attack | costs the reactor's melee attack (1.5 AP); the reactor needs the AP |
| Charged spells | AP is paid at commit and never refunded (fizzle, caster death, target death) |

All values are multiples of 0.5, so float math is exact.

## Pacing (the intent behind the numbers)
- **Base 1.5, +2 per turn**: one Base spell per turn with 0.5 left over; three Base spells every two turns (3 of 4 AP).
- **Tier 2 = Base + 1.5 (3 total)**: ready after 2 turns of saving (4 AP, 1 left over).
- **Tier 3 = Base + 3.5 (5 total)**: ready after 3 turns of saving (6 AP, 1 left over).
- The 8 AP cap fits Tier 3 + Tier 2 (8 exactly).
- The surcharges were not changed when the Base cost went from 1 to 1.5, so the tier totals went up by 0.5 as well.
To retune, change only `AP_MAX`, `AP_REGEN`, `AP_ATTACK_COST` and the two surcharges in `combat_tuning.gd`.

## Choosing the tier
The tier is a per-cast decision, not a learned level. While aiming a spell, press **1 / 2 / 3** to change it
(the aim restarts because each tier has different aim steps). An unaffordable tier is refused with a log line.
The preview panel title shows `Spell - Tier N - X AP`. The tier is stored in `SpellPlan.tier`, committed with
the cast, and the resolution (even when charged) uses it.

## Code map
- `Unit`: `ap`, `max_ap`, `start_turn()` (+regen), `can_afford(cost)`, `can_use(a)` (Base cost),
  `max_affordable_tier(a, max_tier)`, `spend(a, tier)`.
- `Ability.ap_cost_for_tier(tier)`.
- `Battle.use_ability` / `_use_spell` / `_commit_cast` check and spend AP; `Battle.spell_context(user, spell, tier)`.
- UI: `ActiveUnitPanel` (AP readout and cost line), `AbilityText.cost_name` ("1.5 / 3 / 5 AP"),
  `TargetPreviewPanel.show_preview(..., tier)`.

## Removed
`Unit.action / bonus / reaction`, `Unit.slots`, `Unit.spell_tiers`, `UnitData.slots`, `UnitData.spell_tiers`,
`Ability.Cost`, `Ability.cost`, `BattleView.sample_spell_tier`. `Ability.slot_level` stays as a label
(>0 means "this is a spell") and no longer spends anything.

## Not done yet
- Enemy AI still makes one attack per turn (it will bank AP, which only feeds its opportunity attacks).
- No Tier selection for plain `Ability` spells like Burning Burst (they have no tiers).
- Breach / Overload still need `apply_cascading_status()` wired into `Battle._apply_damage`.
