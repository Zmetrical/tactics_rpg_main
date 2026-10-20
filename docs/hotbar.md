# Hotbar (bottom of the battle screen)

Replaces the old layered action menu (`ui/hud/action_menu.*` is deleted). Layout only; it keeps the
existing look (palette, frames, fonts).

```
    [ AP ]  [   MOVE   ]                                      <- two tabs, no bottom edge, open into the box
 [hands MH OH] <> [weapon actions] <> [        spells        ]   [ END TURN ]  [armor] <> [rings]
   2 x 2 cells      2 cols x 2 rows     6 cols x 2 rows           [Esc][ I ]     2 x 2     R1 R2
                                                                   [ + ][ - ]               AM
```
`<>` is a divider (`ui/hud/hud_divider.gd`: ink groove with diamond end caps and a centre stud).

- **Boxes** use the unit panel's frame (`ui/theme/gbc_frame.png`, the double line) through `ui/hud/hud_style.gd`
  (`frame()`), with a tighter content margin. Slots and buttons are flat like the theme's buttons: usable slots
  white with an ink / accent border, unusable ones grey, empty ones flat BG, the aimed ability ink-filled. No bevel.
- **Tabs**: the AP bar and the movement bar each sit in their own container (`HudStyle.tab()`: the frame without
  its bottom edge). The tabs overlap the main box's top border by `FRAME_PX`, so the border is open under them and
  they read as tabs of the box. The tabs line up with the box: the AP tab starts at its left edge and its bar is as wide as hands + weapon actions; the movement tab ends at its right edge and its bar is as wide as the spells; the gap between the tabs sits over the middle divider. The AP tab is taller (bar 26 px), the movement tab shorter (bar 14 px).
- **Hands**: Main Hand and Off Hand, two big slots side by side (each 2 x 2 cells).
- **Weapon actions**: abilities granted by worn weapons. 2 columns x 2 rows.
- **Spells**: every other ability. 6 columns x 2 rows (12 max; raise `SPELL_COLS` if a unit has more).
- **AP bar** (`ui/hud/ap_bar.gd`): in the left tab, over hands + weapon actions. One block per AP, each split in two so half points show; ink-outlined pips, white empty, green filled, all the same size.
- **Movement bar** (`ui/hud/movement_bar.gd`): in the right tab, over the spells. Hover a blue tile on the map and the segments that
  walk would spend turn dark gray. No number label on the bar (hover for the tooltip). Nothing is spent until the click, then the bar drops by the whole
  cost at once (`Battle.move_unit` pays `path.size()` up front; no per-step update).
- **Spent previews** (all dark gray, `Palette.SPENT_PREVIEW`): the movement bar (hovered walk), the AP bar (the ability under the mouse, else the aimed one, else the keyboard cursor; the halves it would empty turn gray) and, on the target panel, the HP / Magic Barrier / Armor bars (the part of the average roll each would lose; armor or shield soaks first, the rest hits HP, same order as `Unit.take_damage`).
- **Gear box**: the leftmost box (before the hands). A row of empty slots on top (2 over the armor, 2 over the rings + amulet; `SPARE_COLS_LEFT` / `SPARE_COLS_RIGHT`),
  a horizontal divider (`GEAR_ROW_GAP` above and below), then the armor and ring rows. The top slots are blank cells (flat BG, grey border) and do nothing yet.
- **End box**: END TURN (ends the turn at once, no confirmation), Esc, I (equipment), + / - (zoom).
- Sizes: `WEAPON_COLS`, `SPELL_COLS`, `ARMOR_COLS`, `JEWELRY_COLS`, `ROWS`, `CELL` in `ui/hud/hotbar.gd`.

## Tooltips replace the description box

Hovering any slot shows a compact card (300 px wide, `WIDTH` in `ui/hud/tooltip_card.gd`): title, subtitle (school, or WEAPON ATTACK / SPELL),
a stats line (`RANGE 6 . 1.5 / 3 / 5 AP`), a divider, one short paragraph, then one row per tier (`T1`, `T2`, `T3`). The card holds only
what is unique to that ability. Worn items show their kind, description, defense and the attack they grant.

**Keywords.** A rule shared by several abilities is a `[Keyword]` in the text (`[Bounce]`, `[Spread]`, `[Pierce]`;
obvious rules like charge, save, fracture and shred are plain words, not keywords). Each keyword used by the ability is drawn as its own small card stacked to the
right of the main card. Definitions live once in `scripts/spells/keywords.gd` (`DEFS`); numbers in them come from the tuning files.
To add one: add an entry to `DEFS`, then write `[Name]` in any ability text.

**Where the words come from.** `AbilityText.body_text()` writes the paragraph from the ability's numbers: bullets in dividers-separated groups, always in this order: timing and aim (`Charge: 5 ticks.` / `Charge: instant.`, `Target: ...`), effect (`Deals 2d6 magic damage to the target.`),
the tiers, then the rules at the very bottom (`DEX save (DC INT).` `Builds Fracture.` or `Attack roll (STR).` `Builds Armor Shred.`). An `effect_text` with `\n` in it is several bullets. The effect sentence is `Ability.effect_text`
(optional; `{dmg}` becomes the dice, `{echo}` / `{last}` / `{f1len}` ... come from `Keywords.tokens()`). With no `effect_text` a default is
written from roll and radius. Tier lines are `SpellDef.tier_text`.
The wording lives in `AbilityText.tooltip()` and `UnitView._gear_tip()`; both return plain dictionaries.
The AP bar, movement bar, END TURN and the small buttons use ordinary text tooltips.

## How it works

- `UnitView.hotbar(unit, can_act)` builds all the data (the bar never sees a Unit).
- `ui/hud/hotbar.gd` builds the nodes once and updates the slots in place, so a tooltip stays up while the
  numbers refresh. Signals: `ability_chosen`, `gear_chosen`, `end_turn_pressed`, `end_turn_answered`,
  `back_pressed`, `inventory_pressed`, `zoom_requested`.
- `Mode` decides what is clickable: READY (everything), AIMING (abilities + Esc), CONFIRM (Esc, YES / NO),
  LOCKED (nothing; text playing or the equipment window is open). Tooltips always work.
- Clicking an ability goes straight to target selection. While aiming, clicking another ability switches to it.
- **Tiers by clicking.** Clicking the spell you are already aiming goes up a tier: first click Base, second click Tier 2,
  third click Tier 3 (`BattleUI.aim_tier_up_requested` -> `BattleView._on_aim_tier_up`). It stops at the spell's `max_tier`
  (weapon attacks and Burning Burst have no tiers, so a second click does nothing), and a tier the unit can't pay for is
  refused with a log line ("Tier 2 needs 3 AP, X has 2"). The aimed slot (ink-filled) (any selected action, spell or weapon) wears a `T1` / `T2` / `T3` badge under its initials, and the attack preview box no longer repeats the tier. The AP bar previews that tier's cost; hovering the aimed
  slot previews the next tier's cost (what one more click buys). Keys 1 / 2 / 3 still pick a tier directly.
- **Esc resets it.** Esc / right click / the Esc button goes up one layer: undo an aim step, else drop a raised tier back to
  Base (the spell stays aimed), else leave targeting.
- Clicking a worn item opens the equipment window.
- Keyboard: the first arrow key shows a cursor over the usable abilities, arrows move it, Enter picks.
- The old ATTACK_MENU state is gone from `BattleUI` (ROOT_MENU goes straight to TARGET_SELECT).
- The battle log now sits above the hotbar instead of replacing the menu; the bar is locked while it plays.
- Not on the bar yet: the B / K / G / M / L buttons from the reference.

## Tile / Unit lock buttons (forecast box)

Charged casts (Burning Burst, Thunder...) show a **[TILE] [UNIT]** row at the bottom of the forecast box,
while aiming and while the target panel is open. Same choice as the `L` key.
- `ForecastBox` only displays it and emits `lock_mode_changed(lock_on_unit)`; `BattleUI` re-emits it.
- `battle_view._set_lock_mode()` owns `lock_on_unit`, switches the pending cast (so no re-aim is needed) and pushes
  the result back with `hud.set_lock_mode(lock_on_unit, unit_available)`.
- UNIT is greyed out when the picked tile has nobody on it. The footer line (`LOCKS TILE 6T` / `FOLLOWS UNIT 6T`) is
  composed by the box from the forecast's `lockable` / `lock_ticks`; battle_view only sends warnings like `FRIENDLY FIRE`.
- Test: `godot --headless -s tests/test_forecast_lock.gd`

## Target panel buttons follow the tilt

CONFIRM / CANCEL are drawn inside the target panel's flat viewport (`UnitPanel3D.set_footer`), in a transparent strip
under the card, so `pseudo3d_panel.gdshader` bends them with it. Controls behind a shader can't take the mouse, so
`TargetPanel._input` maps each mouse event back through the tilt (`UnitPanel3D.to_flat`, the shader's math reversed)
and hit-tests the buttons in flat coordinates. Hover selects, press + release on the same button chooses it; events
that are not on a button pass through to the map. Test: `godot --headless -s tests/test_target_buttons_tilt.gd`

## After a player's attack

- The attack's log is part of the attack: while it plays (`LOG_PLAYING` with `_attack_active`) the HUD face is
  EXECUTING, so the hotbar and forecast box stay hidden, like on an enemy turn. The log sits at the bottom.
- `BattleLog.hold_last` (set on CONFIRM, cleared in `_finish_attack`): lines inside the burst still advance by
  themselves, but the last line waits with its blinking arrow. **Enter or a click** closes it; only then does the
  HUD come back (`_on_log_finished` -> `_finish_attack`). Enemy-turn logs are unchanged and still auto-advance.
- `_finish_attack` returns to **aiming the same ability** (tier back to 1) when the unit can still use it; otherwise to the plain
  menu. A charged cast or an empty AP bar falls back to the menu through battle_view's `aim_cancelled()`.
- The floating "Thunder 8" cast label above a charging tile is gone (the purple tiles remain).
  `Stage3D.set_cast_labels()` is still there, unused.
- Tests: `tests/test_battle_log_hold.gd`, and the REQ1 / REQ6 section of `tests/test_battle_ui.gd`.
