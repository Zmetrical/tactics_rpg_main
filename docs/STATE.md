# STATE
Last step done: 2a-4 (base height; untested in engine, no Godot in sandbox). 2a-2/2a-3 (mask) before it.
Files (new): scripts/run/overworld/island_height.gd, scripts/tools/island_height_test.gd
Files (changed): data/run/overworld_style.gd (ISLAND_H_*)
Public API: IslandHeight.build(mask, seed) -> {vox (voxels, 0 on water), levels (vox/level_vox, int), rungs, rung, min_vox, max_vox, level_vox 2, meta, timings}; height_at(x,z), apply_meta(obj), validate() -> Array[String] (empty = ok), step_histogram(), to_image() (height ramp), difference(), content_hash().
Method: coast-distance base + fbm hills, snapped to a seeded rung ladder (3-6 voxels apart), small patches merged, neighbour step <= 6. Land neighbours differ by 0 or 3-6 voxels: vertical cliffs only.
Meta (terrain names): levels, x0, z0, nx, nz, land, min, max (Vector3 world box, y = voxels * 0.25), + heights_vox, level_vox. Old OverworldTerrain, Layout, run_map_view untouched; not wired.
Island outline: NOT WRITTEN (2a-1 needs reference.png); mask uses brief defaults.
Hash / timing: run island_height_test (seeds 1..20).
Known gaps / unverified: GDScript unrun. Mesas 8-14 voxels come in 2b. docs/CORE.md missing from zip.
Next step: 2b
