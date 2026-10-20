# Combat stats, cooldowns and gear requirements

All numbers live in `scripts/battle/combat_tuning.gd`. Change them there only.

## Hit chance and advantage

- ATTACK rolls use a d100. Hit chance = `Ability.accuracy` + DEX mod x 2, clamped to 5-95%. Armor never changes it.
- A miss deals 0 damage and adds no Armor Shred or Fracture. A hit on a roll of 5 or under is a critical (dice doubled, flat bonus not).
- Advantage rolls twice and keeps the better die (75% becomes 94%), disadvantage keeps the worse (75% becomes 56%). They cancel each other and never stack. `Rules.get_roll_mode` is the only place that decides them.
- Advantage: target exposed, stunned, silenced or restrained; attacker flanking (behind or beside the target's `Unit.facing`); ranged attack from high ground.
- Disadvantage: ranged attack with an enemy adjacent, attacking uphill, target obscured.
- SAVE spells still use d20 + stat mod + PROF against the spell DC.

## Cooldowns

- `Ability.cooldown_turns`: 0 = none, 1 = unusable on the user's next turn.
- Using the ability calls `Unit.spend`, which starts the cooldown. `Unit.start_turn` ticks it. `can_use` and `max_affordable_tier` refuse while it runs.
- Weapon attacks have no cooldown.

## Skill slots

- `UnitData.skill_slots` caps learned skills and spells (-1 uses `DEFAULT_SKILL_SLOTS`, 4). `Unit.learn()` returns false when full.
- Weapon attacks and gear use no slots. The Mage has 6.

## Scaling grades

- `Ability.scaling_grade` (NONE, E, D, C, B, A, S) scales the ability's `stat`.
- Flat damage = floor(stat mod x multiplier). Multipliers: E 0.25, D 0.5, C 0.75, B 1.0, A 1.5, S 2.0.
- A negative mod adds nothing (no penalty). The bonus is added once per hit and is not doubled on a crit.
- It applies to ATTACK, SAVE and AUTO abilities. The hit forecast includes it.

## Stat effects

Only positive mods count.

| Stat | Side | Effect | Per point |
|------|------|--------|-----------|
| STR | attacker | Shred bonus: physical impact into Armor Shred | +10% |
| DEX | attacker | Pierce: share of physical damage that skips Physical Armor | 5% (max 50%) |
| INT | attacker | Magic Pen: share of magical damage that skips Magic Barrier | 5% (max 50%) |
| WIS | defender | Resolve: less impact taken, so stacks build slower | -5% (max 50%) |
| CON | defender | Fracture bonus: magical impact needed per Fracture stack | +8% (max 50%) |

Pierced damage goes straight to Core Health but still feeds the impact pools. DEX also sets hit chance.

## Gear requirements

- `Item.req_str`, `req_dex`, `req_con`, `req_int`, `req_wis` are minimum stat mods. 0 = none.
- `Equipment.mods` is set by `Unit`. `try_equip` and `preview` fail with "<item> needs STR 2 (has 1)." when a mod is too low. An `Equipment` with empty mods skips the check.
- Tooltips show a REQUIRES section.
- Current gear: Greataxe STR 2, Tower Shield STR 2, Iron Cuirass STR 1, Iron Greaves STR 1, Longsword STR 1, Shortbow DEX 1, Spellbook INT 2.

## UI

- Hotbar slots show the turns of cooldown left in the corner and grey out. Tooltips add the cooldown, the scaling line and an "On cooldown" footer.
- The unit panel shows skill slots as `SK used/max`.
