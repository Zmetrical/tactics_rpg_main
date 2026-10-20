# Skills: disciplines, archetypes and learning requirements

Code: `scripts/skills/` (`discipline.gd`, `skill_def.gd`, `skill_catalog.gd`). Learning gate: `Unit.learn_block_reason`.
Test: `godot --headless -s tests/test_skills.gd`

## Requirements
A `SkillDef` is an `Ability` with a primary `discipline`, an `archetype` and `requirements` (discipline id -> rank). A unit
can learn it when it meets **every** listed rank. Most skills list one ("Requires 2 Rogue"). Hybrids list several
("Requires 2 Cinder, 1 Torrent"): Steam Burst, Storm Surge, Mudslide and Thorn Volley. The primary discipline sets the
stat and the first part of the school label; hybrids read "CINDER + TORRENT . HYBRID". Attribute scores are not checked.
Set a hybrid with `"req": {&"cinder": 2, &"torrent": 1}` in the catalog row's extras.

Ranks live in `UnitData.discipline_ranks` (`{ &"rogue": 2 }`) and `Unit.discipline_ranks`. There is no class lock:
any unit with the rank can learn any discipline's skills. `Unit.learn()` returns false when blocked;
`Unit.learn_block_reason(a)` gives the message ("Death Mark needs 2 Rogue (has 1)."). The tooltip shows
"Requires 2 Rogue (you: 1)." and the subtitle reads e.g. ROGUE . ASSASSIN.

## Learned vs memory slots
`Unit.learn()` always learns a skill that passes the rank check. It goes into a memory slot if one is free
(`skill_slots`), otherwise into the library. Only memorized skills reach the hotbar. `memorize(a)` / `unmemorize(a)` swap them,
`learned_skills()` / `memorized_skills()` read them. The inventory window's Skills tab shows both and lets you click to swap.

## Skill Attributes (code name: disciplines)
| Branch | Stat | Discipline | Archetypes |
|---|---|---|---|
| Combat | STR | Warrior | Vanguard, Sentinel |
| Techniques | DEX | Rogue | Assassin, Skirmisher |
| Techniques | DEX | Ranger | Deadeye, Pathfinder |
| Arcane | INT | Tempest, Torrent, Cinder | (one school each) |
| Divine | WIS | Verdant, Tremor | (one school each) |

## What a skill can do today
Dice, damage type, scaling grade, area, charge time (used for traps / quakes), cooldown, AP, plus two riders on `SkillDef`:
- `apply_status` / `apply_status_turns`: puts `exposed`, `restrained` or `wet` on each victim that was hit (not missed, did not save).
  Exposed and Restrained already give attackers Advantage (`Rules.get_roll_mode`).
- `vs_status` / `vs_status_mult`: victims with that status take multiplied damage (Glacial Spike vs Wet).

## Not implemented yet (needs new engine features)
Leaps / vaults / repositioning, pushes into hazards, taunt and intercept, stealth, Overwatch reactions, terrain
creation (pillars, mud, difficult ground, burning tiles), healing and cleanse, Resolve buffs, updrafts.
The catalog only uses what exists, and tooltips only describe what the skill really does. The archetype blurbs in
`discipline.gd` keep the design intent.

## Adding a skill
Append a row to `SkillCatalog._rows()`. Everything else (school label, requirement line, learning gate) follows.
`BattleView.grant_class_skills` (default on) gives each player unit every catalog skill it qualifies for until its slots fill.

## Inventory window UI
The stats panel of the equipment window (`ui/equipment_window.gd`) has two tabs.
- **Stats:** vitals, attributes, then a Status section (title, rule, icon row) with the unit's status effects and Armor Shred / Fracture stacks (`ui/status_text.gd`). The corner number is turns left, or the stack count.
- **Skills:** a Memory section (one square per skill slot, empty ones blank) and a Learned section (every learned skill; ones in memory are drawn inverted). On your own units a click memorizes a skill or takes it out of memory; enemy previews are read-only.
The Stats page keeps `PAGE_MIN_HEIGHT`. The Skills page fills the same space, wraps its rows and hint text, and scrolls vertically when there are many skills.
