# Action bar (bottom center)

`ui/action_bar.tscn` replaces the old command menu (`command_menu.*` is now unused). Same API:
`update_commands(unit, can_act, targeting, can_end_turn)`, `ability_pressed`, `end_turn_pressed`.

- **Weapon actions** (3 x 2 squares, icon text `AA`) and **spell actions** (4 x 2 squares, icon text `SS`).
  A spell is any ability with magical damage or a spell level (`AbilityText.is_spell`). Empty squares keep the size.
- **Description box**: short and simple. Shows the hovered ability, else the one being aimed, else a hint:
  name, one line of numbers (`1 AP | Range 6 | 5 ticks`), one line of effect (`DEX save | 2d6 magical`).
  Wording lives in `AbilityText.brief()`.
- **Aim controls** (inside the description box, only while aiming): a **Tier** row (`1  1 AP`, `2  2.5 AP`,
  `3  4.5 AP`) for tiered spells, and a **Lock** row (`Tile` / `Unit`) for charged spells. Plain attacks show neither.
  Keys 1 / 2 / 3 still pick the tier. Unaffordable tiers are greyed out. The bar emits `tier_selected(tier)` and
  `lock_mode_changed(lock_on_unit)`; battle_view owns the state and pushes it back with `set_aim(tier, lock_on_unit)`.
- **Equipment (I) button** in its own box to the right of the description. It opens the full Equipment window
  (same as pressing I). The action bar emits `equipment_pressed`; battle_view opens the window.
- Swap the `AA` / `SS` text for real icons in `ui/ability_slot.gd` (`setup`).

The attack preview panel (bottom right) no longer has Tier or Lock controls. It only reports the forecast:
title with tier and AP, roll line, target cards, friendly-fire warning and a one-line charge note.
