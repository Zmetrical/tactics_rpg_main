# Seamless on-map combat (grid-based attack execution)

No battle scene swap. The camera stays isometric, pushes in a little on the action, and every
attack plays out on the live tiles. All visuals are code-built placeholders (quads, spheres, rings,
particles, labels), so the sequencing and feel can be tuned before any art exists.

## Flow
`Battle` resolves an action instantly (rules never wait on visuals) and emits
`action_executed(user, ability, cell, results, tag)`. `CombatDirector` queues it and plays it while
`battle.presenting` is true. Input, enemy AI and turn changes wait on that flag.

    toast -> camera focus -> windup -> strike / projectile / spell -> impact -> recovery -> release

| Kind  | Picked when                              | Staging                                              |
|-------|------------------------------------------|------------------------------------------------------|
| MELEE | range 1                                  | lean back, lunge into target, slash streak           |
| ARROW | weapon (STR/DEX) at range               | draw, recoil, arrow flies on an arc                  |
| BOLT  | magic (slot / save / auto / INT+) at range | rune circle, caster rises, orb flies                |
| BURST | `area_radius > 0`                        | tiles light up, orb lobs in, shockwave, staggered hits |

Impact: tile flash, particle burst, white-hot flash, hit-stop (freeze), camera shake, knockback,
floating number (MISS / n / n! / RESIST), HP label updates on the beat, death fades after the freeze
plus slow-mo. Misses dodge sideways. A charged spell that finds nothing gets a FIZZLE beat.
Opportunity attacks play inside the move (the walk waits, then continues).

## Tuning (top of `scripts/battle/combat_director.gd`, or at runtime on `view.director`)
- `enabled` off = old instant behaviour. `camera_focus_enabled`, `hit_stop_enabled`, `shake_enabled`, `show_toast`.
- `speed` (1.0 normal). Hold SPACE for `fast_forward_mult` (2.5x).
- `focus_zoom` (0.78 = push in 22%). Long shots automatically stay wider.
- Timing constants (`MELEE_WINDUP`, `SPELL_WINDUP`, ...), hit feel (`STOP_*`, `SHAKE_*`, `KNOCKBACK_DIST`).

## Swapping in real art later
Replace only the bodies of the small helpers: `_fly`, `_burst`, `_slash`, `_ring`, `_magic_circle`,
`_flash_unit`, `_float_text`. Sequencing, gating and tests stay as they are.

## Files
New: `scripts/battle/combat_director.gd`, `tests/test_combat_director.gd`.
Changed: `battle.gd` (signal + `presenting` gate), `stage_3d.gd` (camera focus/shake + accessors),
`battle_view.gd` (creates the director; HUD and highlights hold still while an action plays).

Tests: `godot --headless -s tests/test_combat_director.gd`
