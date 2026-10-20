# AI bundle: Tactics RPG (Godot 4.7, GDScript)
Read-only slim copy. Not runnable. Code and comments untouched.

## Removed
.godot/, addons/TileMapLayer3D (3rd-party; maps use its nodes), docs/screens, *.png *.ico *.svg *.fnt, *.uid, *.import, *.tmp, *.meta, *.asset.
Stripped from .tscn/.tres: `uid="uid://..."`, `unique_id=`, blank lines.
Restore: original zip.

## Entry
`project.godot` -> `scenes/battle.tscn` -> `scripts/battle/battle_view.gd` + `stage_3d.gd`.

## Map
- `scripts/battle/`: battle.gd (loop, state machine, no rendering), battle_view.gd, combat_director.gd, stage_3d.gd, unit.gd, rules.gd, combat_tuning.gd, grid.gd, map_loader.gd, terrain_tiles.gd
- `scripts/spells/`: spell_* (def, plan, targeting, behavior, registry), aeromancy/
- `scripts/inventory/`: item.gd, equipment.gd
- `ui/hud/`: current HUD. battle_ui.gd root, hotbar.gd, unit_view.gd
- `ui/` (top level): older panels, many superseded by `ui/hud/`
- `data/`: .tres units, abilities, items, biomes, tile_library
- `scenes/maps/<biome>/<size>/`: map scenes
- `shaders/`, `tools/` (asset bake scripts, not runtime)

## Docs: read by topic only
action_bar, action_points, combat_stats (hit chance, cooldowns, slots, scaling, stat effects, gear requirements), defense_system, hotbar, seamless_combat, spell_system, terrain_tileset, unit_sprites.
`docs/battle_ui_redesign.md`: 72 KB, historical. Skip unless editing HUD design. ActionMenu in it replaced by hotbar.
