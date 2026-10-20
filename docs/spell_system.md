# Spell system (framework + Aeromancy / Electric sample)

A spell is an `Ability` (so AP cost, range, dice, the action bar and the preview panel all keep working)
plus a **behaviour** that knows how to aim and resolve it. Nothing about plain weapon attacks changed.

## Pieces (`scripts/spells/`)
| File | Job |
|---|---|
| `spell_def.gd` | `SpellDef extends Ability`: school, subschool, `tier_text`, `spell_id`. `format_entry()` prints the design format. The effect sentence is `Ability.effect_text`. |
| `keywords.gd` | Glossary of rules worth explaining (`[Bounce]`, `[Spread]`, `[Pierce]`). Each is defined once and shown as its own tooltip card. |
| `spell_behavior.gd` | Base class. Override `aim_steps()` and `resolve()`. Stateless and pure. |
| `aim_step.gd` | One decision: `UNIT`, `TILE`, `DIRECTION`, `PIVOT`, `PATH`, `FORK`. A spell is an ordered list of these. |
| `spell_plan.gd` | The player's answers, committed with the cast and resolved later. |
| `spell_result.gd` | Hits (`unit`, `scale`, `tag`) and tiles. Feeds BOTH the real resolve and the hover preview. |
| `spell_targeting.gd` | Aiming session the view drives: hover / click / skip (Enter) / back (right click). |
| `spell_geometry.gd` | Pure grid maths: 8-way snap, rays, line of effect, crosses, path validation. |
| `spell_tuning.gd` | Every number: cast-tick conversion, 33% echo, arm counts, shockwave sizes, fork lengths. |
| `spell_registry.gd` | `spell_id -> behaviour`. |

Engine hooks: `Battle.use_ability(user, spell, cell, lock, plan)`, `PendingCast.plan`, `_resolve(..., scales)`
(one damage roll, different fraction per victim), `SpellPlan.tier`, `Unit.learn()`, `Ability.is_charged()`.

## How spells work (plain version)

**Cost.** Every spell costs Action Points (AP). You pick the tier each time you cast: click the spell on the hotbar again
while aiming (2nd click = Tier 2, 3rd click = Tier 3) or press 1 / 2 / 3. Esc drops a raised tier back to Base.

| Tier | Cost | Why it exists |
|---|---|---|
| Base | 1 AP | Two per turn (you get 2 AP each turn). |
| Tier 2 | 2.5 AP | Gives up 1.5 spells to make one spell play better. Takes 2 turns of saving. |
| Tier 3 | 4.5 AP | Gives up 3.5 spells. Takes 3 turns of saving. |

Changing the tier restarts your aim, because higher tiers add aiming steps. Details: `docs/action_points.md`.

**Cast time.** Most spells charge. You choose the target now, the AP is spent now (never refunded), and the spell lands a
few ticks later. "5 ticks" means it resolves after 5 clock ticks. If the caster dies, the cast is cancelled.
- Locking a **tile** hits whoever is standing there when the spell lands.
- Locking a **unit** makes the spell follow that unit. If the unit dies, the cast is cancelled.

**Rules every spell follows**
- One cast never hits the same unit twice.
- The caster is never hit. Allies in the area are hit, so aim carefully.
- Extra hits (bounces, shockwaves, side lines, forks) use a percentage of the same damage roll.
- Each victim makes a saving throw; a passed save halves the damage.

## Spell list: Aeromancy / Electric

Damage is magical, so it hits the target's Magic Barrier first. Dice below are placeholders. Tune them in `electric_spells.gd`
and the shapes and percentages in `spell_tuning.gd`.

| Spell | Cast time | Range | Damage / save | How you aim |
|---|---|---|---|---|
| Chain Arc | 5 ticks | 6 | 2d6, DEX | Pick one enemy |
| Thunder | 9 ticks | 6 | 3d6, DEX | Pick a tile or a unit |
| Bolt | 4 ticks | 8 | 2d8, DEX | Pick a compass direction |
| Surge | 5 ticks | 8 | 2d8, DEX | Draw a path, tile by tile |

### Chain Arc
A shot at one enemy that can bounce off it to hit others.
- You need a clear line to the target. The shot stops at the first wall or unit in its way, so you cannot lock a target with
  something standing in front of it.
- If a unit steps into the line while the spell charges, that unit is hit instead, and the bounce comes off it.
- A bounce is a 2-tile line that sticks out from the target in a direction you choose (8 directions). It can hit up to 2 units for 33%.

| Tier | What changes |
|---|---|
| Base | One hit on the target. No bounce. |
| Tier 2 | You choose the bounce direction. One bounce line. |
| Tier 3 | Two bounce lines on opposite sides of the target. Turning one turns the other. |

### Thunder
A strike on a tile that ignores walls and cover. A tile only has to exist to be hit.
- The centre and the four tiles touching it (a plus shape, 5 tiles) take full damage.
- Every extra tile added by the tiers takes 33%.

| Tier | Shape |
|---|---|
| Base | Plus shape, 5 tiles. |
| Tier 2 | Each arm is 1 tile longer: 9 tiles. |
| Tier 3 | Each arm is 2 tiles longer, and the 4 corner tiles are filled: 17 tiles. |

### Bolt
A shot in a straight line that passes through every unit and stops at a wall or the map edge. Allies on the line are hit too.

| Tier | What changes |
|---|---|
| Base | Full damage to every unit on the line. |
| Tier 2 | The last unit on the line takes 33% extra. Pushing enemies against a wall pays off. |
| Tier 3 | Same, plus two 3-tile lines run alongside the bolt, one on each side of the last unit, for 33% damage. |

### Surge
A bolt you steer. You draw the path one tile at a time, up to 8 tiles, and it hits the first unit on the path, allies included.
- The path starts next to the caster, moves up, down, left or right only, cannot cross a wall, and cannot revisit a tile.
- Extra paths (forks) start from the unit just hit and only hit units that were not already hit.

| Tier | What changes |
|---|---|
| Base | One path, one victim. |
| Tier 2 | Draw a 6-tile fork from the first victim. It hits the first new unit for 50%. |
| Tier 3 | Also draw a 4-tile fork from the fork's victim. It hits the first new unit for 25%. |

## Terms used in code

The plain wording above is what players and designers should read. The code and tests use these names.

| Plain description | Code name | Where |
|---|---|---|
| Pick one unit | `AimStep.Kind.UNIT` | `aim_step.gd` |
| Pick a tile | `AimStep.Kind.TILE` | `aim_step.gd` |
| Pick a compass direction | `AimStep.Kind.DIRECTION` | `aim_step.gd` |
| Draw a path | `AimStep.Kind.PATH` (Vector Pathing) | `aim_step.gd` |
| Choose the bounce direction around the target | `AimStep.Kind.PIVOT` (Pivot Targeting) | `aim_step.gd` |
| Draw a branch from the unit just hit | `AimStep.Kind.FORK` (Manual Fork) | `aim_step.gd` |
| Stops at the first wall or unit | Line of Effect, `Geo.ray` / `Geo.line` | `spell_geometry.gd` |
| Ignores walls, only needs the tile to exist | Spread | `thunder.gd` |
| Number of ticks | `Ability.charge_speed`: ticks = ceil(100 / charge_speed) | `ability.gd` |
| Chosen tier | `SpellPlan.tier` | `spell_plan.gd` |

Engine hooks: `Battle.use_ability(user, spell, cell, lock, plan)`, `PendingCast.plan`, `SpellContext.tier`,
`Ability.is_charged()`.

## Where this differs from the original design brief
- The first spell had no name in the brief. It is called **Chain Arc**.
- **Cast times** use the same system as Burning Burst (charge speed 17 = 6 ticks): Chain Arc 5, Thunder 9, Bolt 4, Surge 5 ticks.
  The brief's numbers (3 / 4 / 2 / 3) are not used. Say if you want those instead.
- **Chain Arc** has no bounce at Base. Tier 2 adds one bounce line and Tier 3 mirrors it. The brief gave Base one bounce,
  made Tier 2 the mirrored version, and made Tier 3 a longer 3-tile bounce.
- **Bolt Tier 3** adds two side lines beside the last unit. The brief described a T-shape of 3 tiles across the end of the line.
- **Surge Tier 3** is a second 4-tile fork for 25%. The brief gave two separate 6-tile forks from the first target for 50% each.
- Tier 2 and Tier 3 are no longer "learned". The player chooses the tier on every cast and pays AP for it.

## Adding a spell
1. `scripts/spells/<school>/<spell>.gd` extending `spell_behavior.gd`: `aim_steps()` + `resolve()`.
2. Register its id in `spell_registry.gd`.
3. A `SpellDef` (see `aeromancy/electric_spells.gd`): `effect_text` (one sentence, `[Keyword]`s and `{dmg}`) and three short `tier_text` lines. Add any new shared rule to `keywords.gd`.
4. Tests in `tests/test_spells.gd` (`godot --headless -s tests/test_spells.gd`).

## Known follow-ups
- `CombatDirector` stages Thunder as a radius-1 burst at every tier and every spell as one orb. Give it `SpellResult.cells`
  (and per-hit tags) to telegraph the real shape and play bounces / forks as separate beats.
- Sample spells are granted to player casters by `BattleView.grant_sample_spells` (default on) so you can try them live.
- Enemy AI ignores SpellDefs (they need a plan).
