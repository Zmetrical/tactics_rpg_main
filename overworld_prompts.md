# Voxel Diorama Overworld: Prompt Pack v2 (reference-matched)

Changes from v1: measured reference spec added to CORE; mesa cliffs, tan roads, ruin-capped plateaus, dense lowland forest, shallow dripping underside, beige tilt-shift look; Image gate now compares against the reference image.

## How to use

1. Save CORE as `docs/CORE.md`, STATE as `docs/STATE.md`, and the reference image as `docs/reference.png`.
2. Start each session: `Read docs/CORE.md and docs/STATE.md, then do: STEP <id>`.
3. Steps marked **[attach image]** need `reference.png` attached to that session.
4. Do steps in order. Don't continue until "Done when" passes.
5. Run the Image gate after 3c, 6c, 7c, 8d. Attach reference.png and your screenshot. Paste any "no" back as the next prompt.
6. On failure paste only the error, the one function, and the step ID.

---

## CORE (docs/CORE.md)

```
PROJECT: Godot 4.7 GDScript, GL Compatibility. Procedural voxel floating-island diorama overworld, tabletop miniature, pastel highlands. Target = docs/reference.png "grown larger".
ORDER: terrain first, then nodes, then paths. Nodes are discovered on terrain, never terrain flattened to fit nodes.
BIOME: single. Mint-to-pine greens, lavender/pink blossom, peach clay cliffs, grey stone ruins, tan paths, light-blue water. No snow/sand/lava/marsh/biomes.
REGIONS: DEEP_FOREST, CLIFF_TERRACES, RIVER_VALLEY, LAVENDER_GROVE, VILLAGE_BASIN, RUINED_HILL.
SCALE: fixed voxel size. Bigger map = more terrain.

REFERENCE SPEC (measured from image):
- Massing: few tall MESA blocks (8-14 voxels above lowland), flat grass-capped tops, vertical peach cliff faces. Mesas hold ruined castles, towers, broken walls. Lowlands between them hold villages, forest and rivers. Hills/terraces elsewhere step 3-6 voxels.
- Cliffs: peach clay, SUBTLE strata (low-contrast darker/lighter bands, slight wobble, not stripes), thin mint grass lip, occasional small ledges with bushes.
- Rivers: light blue, wind between mesas through lowlands, 1-3 wide, fall off the rim as thin waterfalls with foam pile.
- Paths: TAN/cream, flat on ground, stairs up mesas and terraces. Roads wider+lighter, trails narrow+darker tan. Cross water by small wooden bridges.
- Density: lowlands densely covered by clumped trees (lavender/pink blossom mixed with round green and pine), clear gaps for villages and paths. Mesa tops mostly bare grass + ruins.
- Villages: clusters of small peach/timber houses with pitched roofs, around a lane.
- Underside: shallow taper, flat-ish brown rock bottom, ragged edge, dark drips/roots hanging below the rim, small loose rock bits. Not a deep cone.
- View: fixed isometric-style angle, soft beige background, gentle tilt-shift blur at top/bottom, pastel but value-separated.

PATHS: axis-aligned only, never diagonal. ROAD 2-3 wide (edge touches story node SHOP/CAMPFIRE/BOSS/START). TRAIL 1 wide (battle-battle). Terrain-aware A* (slope, water, cliff, forest, turns), merge with existing paths. Rise = stairs, water = bridge/ford, ridge = tunnel/switchback. Wiggle from cost, never random noise.
NODES (RunMap read-only): SHOP=village, CAMPFIRE=shrine, BOSS=fortress on a mesa, START=landing camp. BATTLE=banner/campfire/signpost/stone circle, ELITE=ruined tower/braziers. Story = landmark + flat footprint + walls; battle = small marker in clearing/crossing.

RULES:
- Never edit map_generator.gd, run_map.gd, run_tuning.gd. Every RunMap edge must end as a walkable path.
- Don't touch battle code, TileMapLayer3D, battle terrain.
- Keep run_map_view.gd, map_furniture.gd, map_top_bar.gd working every step. Before changing an API list the fields they read (terrain meta levels/min/max, is_land, is_water, biome_at, region_name_at, bridge_cells, footprints, door cells, corridor cells, height_fn) and keep or adapt them.
- Pure logic = RefCounted, no nodes. Meshing/scene in separate files.
- Tunables only in data/run/overworld_*.gd.
- Determinism: seed ^ STAGE_SALT, local RandomNumberGenerator or seeded FastNoiseLite, no global randf/randi, sort Dictionary keys.
- Every step: debug toggle for its layer, per-stage timing, build-twice hash check.
- DO NOT: flat plane, noise-only blobs, path outlines on surface, diagonals, floating markers, identical repeated trees/props, scatter ignoring terrain, unbridged water/cliff crossing, washed-out palette (path, ground, node, water, cliff separate in grayscale).
- Output: code + 5-line report only. Small steps.
- END OF EVERY STEP: overwrite docs/STATE.md (max 200 words): files changed, API signatures, meta kept, constants file, hash, known gaps, unverified items.
```

---

## STATE template (docs/STATE.md)

```
# STATE (max 200 words, overwrite each step)
Last step done:
Files (new/changed/deleted):
Public API (signatures):
Meta / contract kept:
Constants files:
Hash (seed 1):
Timing (ms):
Known gaps / unverified:
Next step:
```

---

## Phase 0: Audit (no code, paste once)

```
CONTEXT (current code):
- overworld_layout.gd places rooms on a grid and runs corridor A* FIRST; overworld_terrain.gd builds terrain around them (heights blend to level 1 near rooms/corridors). Backwards.
- Terrain = 2.5D heightfield, one slab mesh, one height per cell (levels 0-3 + massifs). No stairs/tunnels/overhangs/underside.
- 3 biomes (meadow/forest/rock) from 2x2 coarse regions. Conflicts with single-biome rule.
- Corridors = flat 1-cell strips drawn as boxes (ROAD_HEIGHT 0.2) by overworld_decor.gd. Bridges are planks over pre-carved river cells.
- Props = 3-9 box primitives (map_models.gd), one mesh per kind. GBC palette. No sun shadows, no SSAO.
- MUST SURVIVE: deterministic seed salts, RunMap read-only (8 layers x 4 cols + boss, edges never cross), token travel along corridor cells, hover picking on room footprints, rotatable camera/zoom/pan, mist, seed plate.

STEP 0 (attach reference.png): Read scripts/run/overworld_layout.gd, overworld_terrain.gd, overworld_decor.gd, run_map_view.gd, map_furniture.gd, data/run/overworld_style.gd, map_models.gd, map_pixels.gd, scenes/run/run_map.tscn. NO code. Report:
1. Pipeline file by file + exact data contract run_map_view/map_furniture consume.
2. RunMap node type -> story/battle mapping; edge -> road/trail; flag edges that would break.
3. VOXEL_SIZE + grid size so full generation incl. A* is < ~2.5 s. Show arithmetic. Must be fine enough for the reference's detail (houses ~4-6 voxels wide, ruins towers ~3 wide, mesas 8-14 tall). Say how camera framing, token size, labels, hover boxes scale.
4. Palette: separate overworld palette file, battle untouched. Include tan path colours.
5. Does ps1_post.gd fit the tilt-shift look? Keep/option/disable.
6. File plan: rewritten / kept / deleted / new (one line each).
7. Top 5 risks (performance, determinism, edge crossing, token height on stairs, mesh size) + mitigation.
8. Compare reference.png to the current screenshot: list the 5 biggest gaps.
End with recommended phase-order changes.
Done when: I've read the report and resolved open questions.
```

---

## Phase 1: Voxel world and mesher

### 1a. VoxelWorld + hash
```
STEP 1a: VoxelWorld (RefCounted), no meshing.
Column store (ground height + short list of material runs) + sparse Dictionary Vector3i -> material id for edits (stairs, tunnels, bridges, prefabs, props, waterfalls). Material ids = small ints mapped to palette keys.
API: get, set, height_at, surface_material_at, bounds, hash() (stable, sorted).
Fill from current OverworldTerrain output.
Done when: hash identical across two builds; get/set round-trips; timing printed.
```

### 1b. Chunk mesher
```
STEP 1b: Chunk mesher (separate file), 16x16 columns per chunk. Hidden-face culling, vertex colour from material id, one ArrayMesh per chunk, rebuild one chunk on edit. Leave vertex-colour hook for AO/shadow (8b/8c). Debug: chunk wireframe.
Done when: one chunk rebuilds alone; triangle count + ms per chunk printed.
```

### 1c. Parity swap
```
STEP 1c: Render today's terrain via VoxelWorld + mesher. Keep OverworldTerrain.build() API and meta unchanged; run_map_view only swaps mesh source.
Done when: same screen as before; tokens, hover, camera framing, mist work; hash + timing printed.
```

---

## Phase 2: Terrain (no nodes, no paths)

### 2a. Island mask + base height **[attach image]**
```
STEP 2a: Terrain must NOT know nodes or paths.
Island mask: domain-warped noise on distorted ellipse, aspect ~2:1 along layer axis, irregular ragged outline like reference.png. Remove 1-cell spurs, one landmass.
Base height: low continental base + rolling hills, hill/terrace steps 3-6 voxels, vertical cliff faces (no slopes).
Debug: height colour ramp. Params in overworld_style.gd.
Done when: two seeds give clearly different islands; meta levels/min/max/is_land valid.
```

### 2b. Mesas + regions **[attach image]**
```
STEP 2b: Mesas: place 2-4 mesa centres by seeded rule (spread, not clustered, at least one near the east end for the boss). Each mesa = irregular blob (warped), flat top, raised 8-14 voxels above surrounding lowland, VERTICAL faces, optional 1-2 small ledges on the sides. Keep gaps between mesas for river valleys.
Regions: 6-9 centres tagged with the 6 characters (see CORE). RUINED_HILL and CLIFF_TERRACES bias to mesa tops and edges; VILLAGE_BASIN flat lowland between mesas; RIVER_VALLEY follows gaps. biome_at() and region_name_at() keep working (name list in overworld_style.gd).
Debug: region colours + mesa mask.
Done when: debug heightmap shows tall flat-topped mesas with lowlands between, like the reference; all 6 characters appear.
```

### 2c. Water + surface materials **[attach image]**
```
STEP 2c: Rivers start high (mesa foot / highland), lowest-cost descent through valleys between mesas, winding, carve 1-3 voxel channel, end at island rim (future waterfall) or pond. 1-3 small ponds in basins. Water sits below banks.
Surface: mint grass on tops and lowlands, peach clay on cliff faces, grey stone on steep rocky patches and ruin zones.
Output water mask + river list. Debug: water only.
Done when: at least one river runs between mesas and reaches the rim; is_water meta correct.
```

---

## Phase 3: Diorama shape

### 3a. Rim + strata **[attach image]**
```
STEP 3a: Cliff walls (mesa faces and island rim): peach clay with SUBTLE strata by absolute height (2-3 close tones, bands 2-4 voxels thick, slight wobble, low contrast). Thin mint grass lip on top. Occasional small ledges with bush voxels.
Done when: all four 90-degree yaws show finished walls; strata subtle, not striped.
```

### 3b. Underside **[attach image]**
```
STEP 3b: Shallow taper below rim: depth ~25-35% of island width, narrowing gently to a flat-ish brown rock bottom with a ragged edge. Add dark drip/root voxel strands hanging from the rim (varied length, sparse clusters) and a few small loose rock voxels below. Deterministic. Update meta min/max so camera framing includes underside. Plain soft background, no floor plane.
Done when: underside looks finished from all four angles; camera framing fits.
```

### 3c. Waterfalls + slice view **[attach image]**
```
STEP 3c: Every river reaching the rim falls as a thin light-blue voxel column down the cliff, with foam voxel pile at the end. Debug: cross-section slice at chosen row; toggle to hide props.
Done when: bare island screenshot matches reference massing. Run Image gate.
```

---

## Phase 4: Node placement (RunMap read-only)

### 4a. Candidate scoring
```
STEP 4a: For each RunMap node compute ideal anchor from layer/column (west to east, boss at east end). Score candidate sites in a search radius:
- BOSS: largest flat mesa top near east end, cliff on >= 3 sides.
- SHOP: flattest large VILLAGE_BASIN in lowland, near water or a road corridor.
- CAMPFIRE: quiet clearing, LAVENDER_GROVE or hilltop edge.
- BATTLE/ELITE: clearings, river crossings, ridge saddles, mesa feet; ELITE prefers RUINED_HILL or mesa top.
- START: low west edge.
Hard rules: not in water, not on cliff face, min spacing, west-east layer order.
Debug: score heatmap + chosen sites. Weights in data/run/overworld_sites.gd.
Done when: scores explain every choice; deterministic tie-breaks.
```

### 4b. Selection + edge-crossing check
```
STEP 4b: Pick sites from 4a. Check no two RunMap edges cross as straight lines between chosen sites; on failure re-pick deterministically (next-best candidates).
Done when: 20 seeds pass.
```

### 4c. Flatten + footprints
```
STEP 4c: Flatten footprint to one height (cut/fill), stone retaining walls where cut > 1 voxel, 1-2 voxel apron. Record footprint Rect2i, door candidates, site traits per node in the old layout's shape (picking/tokens keep working).
Done when: every node sits on flat ground; picking and tokens work; hash stable.
```

---

## Phase 5: Path routing

### 5a. A* only
```
STEP 5a: No voxel changes. Per RunMap edge: 4-dir A*, state (cell, heading). ROAD if either end is story node else TRAIL.
Costs: step 1; rise small=cheap, large=high, > MAX_STAIR_RISE forbidden (unless tunnel); water forbidden unless bridge <= MAX_BRIDGE_SPAN; cliff forbidden; forest density; turn penalty; discount on existing path cells. Routes to mesa tops must find a stair-able slope or ledge route.
Output per-edge cell list + class in the structure run_map_view reads. Constants in data/run/overworld_paths.gd.
Debug: colour by class. Print A* ms per edge.
Done when: all edges routed on 20 seeds incl. mesa-top nodes, no diagonals, equal hashes.
```

### 5b. Voxelize roads, trails, stairs **[attach image]**
```
STEP 5b: Roads 2-3 wide light tan, trails 1 wide darker tan, painted as surface material, no raised outlines. Height changes = stairs, 1 voxel per step, axis-aligned, landing every N steps, stair cut into mesa slope with side walls like reference. Output height per cell so tokens follow stairs.
Done when: tokens walk every edge over stairs; roads vs trails distinct and both tan.
```

### 5c. Bridges, tunnels, headroom **[attach image]**
```
STEP 5c: Roads cross water on small wooden bridges with railings; trails use ford stones. Ridge: tunnel if cheaper, else switchbacks. 2 voxels headroom above every path. Update bridge_cells meta.
Debug: stair/bridge/tunnel overlay.
Done when: no unbridged water crossing; tokens traverse bridges.
```

### 5d. Validator
```
STEP 5d: Fail loudly with rule name: every edge has a path, axis-aligned steps, no path over water without bridge, rise <= limit, every node reachable from START.
Done when: passes on 20 seeds.
```

---

## Phase 6: Landmarks and markers

### 6a. Prefab format + loader
```
STEP 6a: Data-driven prefabs in data/run/prefabs/: layered text grids with palette keys, pivot, entrance side, footprint. 90-degree rotation + mirroring. Preview scene.
Done when: sample prefab loads, rotates, mirrors, previews.
```

### 6b. Story + ruin prefabs **[attach image]**
```
STEP 6b: 3 variants each:
- village: 4-7 small peach/timber houses (4-6 voxels wide, pitched roofs), lane, well or stall, low walls.
- shrine: stone ring or small temple with lanterns.
- fortress: ruined castle like the mesa tops in reference: crenellated grey stone keep, 2-4 towers, broken walls, ramp or stair entrance.
Scenery ruins (placed by terrain, not nodes): ruined arch, broken wall run, lone tower (3 wide, 8-12 tall), standing-stone circle, stepped ruin terraces.
Done when: all preview correctly; no floating voxels; fortress reads as a ruined castle.
```

### 6c. Markers + stamping + ruin scatter
```
STEP 6c: Battle markers: banner, campfire, stone circle, signpost; larger ELITE variant (ruined tower base/braziers). Stamp on 4c footprints, entrance facing the 5 door cell, retaining walls on cut sides, stair/path to entrance. Variant + rotation from seed. Replace old landmarks in map_models.gd.
Scenery ruins: scatter 6-12 on mesa tops and RUINED_HILL by seeded rule, away from paths and footprints.
Every prefab column reaches ground.
Done when: nodes readable at default zoom; mesa tops carry ruins; no two villages identical. Run Image gate.
```

---

## Phase 7: Dressing and life

### 7a. Tree/prop variants **[attach image]**
```
STEP 7a: Species: round green tree, tall pine, lavender/pink blossom tree, bush, flower patch, boulder cluster, fence, lantern, mushroom. 5-8 mesh variants per species from seeded rule (trunk height, crown size/shape, colour tier). Blossom crowns are chunky clustered voxel balls like reference. MultiMeshInstance3D per species and chunk.
Done when: variant preview grid; no neighbouring identical trees.
```

### 7b. Placement + exclusions **[attach image]**
```
STEP 7b: Placement by region + noise clumping:
- DEEP_FOREST: dense canopy, clearings, camps.
- LAVENDER_GROVE: blossom trees + open meadow + standing stones.
- RIVER_VALLEY / lowlands: dense clumped mixed trees along banks.
- CLIFF_TERRACES: sparse trees on lips, flower strips.
- VILLAGE_BASIN: fields, fences, few trees.
- RUINED_HILL / mesa tops: bare grass, bushes, broken stone.
Target tree cover on lowland ~45-60%, mesa tops ~5%.
Exclusions: paths +1, stairs, bridges, footprints +2, water, steep faces. Props on ground height.
Report draw calls + instance counts.
Done when: lowlands look densely forested like reference with clean clearings; nothing on paths.
```

### 7c. Animation
```
STEP 7c: Cheap shader animation: water shimmer, waterfall flow, flag sway. Smoke from chimneys/campfires. Adapt mist in map_furniture.gd to new bounds.
Done when: interactive; draw calls reported. Run Image gate.
```

---

## Phase 8: Look and lighting (bake into vertex colours, no SSAO)

### 8a. Palette file **[attach image]**
```
STEP 8a: data/run/overworld_palette.gd. Sample colours from reference.png. 3 value tiers (light/mid/dark) per material: grass, peach clay, stone, road tan (light), trail tan (darker), water, wood, roof, blossom foliage, green foliage, dark rock underside, drip/root. Overworld only, battle palette untouched.
Done when: every material reads from this file; swatch debug view.
```

### 8b. Baked AO
```
STEP 8b: Per-vertex AO from neighbouring voxel heights in the mesher. Darken concave corners, cliff bases, overhangs, inside stairs, tree/ruin bases.
Done when: visible contact shading; chunk rebuild still fast.
```

### 8c. Baked sun shadow
```
STEP 8c: March fixed sun direction over heightfield + edits, soft 2-3 voxel falloff, stored in vertex colour. Mesa shadows fall into valleys. Props use per-instance ground-shadow value. Keep directional face shading (top lightest, left mid, right darkest).
Done when: shadows consistent from all four yaws.
```

### 8d. Post effect + grayscale **[attach image]**
```
STEP 8d: Soft beige background colour from reference. Distance haze with slight desaturation. Tilt-shift: subtle blur + soft vignette band at top and bottom, reusing the Ps1Post pattern. PS1 effect becomes an option, off for this map. Debug key: grayscale.
Done when: path, ground, node, water, cliff separable by value alone. Run Image gate.
```

---

## Phase 9: Robustness

### 9a. Validator + retry
```
STEP 9a: Full-build validator: every edge has a path, all nodes reachable from START, nodes on land outside water, no diagonal, no unbridged water path, stairs within rise limit, no overlapping footprints, no floating voxels, at least 2 mesas present. Retry with seed ^ ATTEMPT_SALT up to N attempts, deterministic. Print failed rule.
Done when: 20 seeds validate.
```

### 9b. Overrides
```
STEP 9b: Resource or JSON keyed by seed: pin node to cell, force river start, carve/forbid path cell, stamp prefab at cell, change region tag, force mesa centre. Runs inside the pipeline so validation applies.
Done when: each override type has a working example and still validates.
```

### 9c. Threading + tests
```
STEP 9c: Generate on a WorkerThread with loading state; rebuild only dirty chunks. Print timing per stage + total, triangles, draw calls. scripts/tools/ test: 3 seeds built twice, assert equal hashes of voxels, node sites, paths. Keep seed plate and region plate working.
Done when: test passes; timing meets Phase 0 budget.
```

---

## Image gate (after 3c, 6c, 7c, 8d)

Attach `reference.png` and your screenshot at default camera. Answer yes/no for each; paste any "no" back as the next prompt.

1. Are there 2+ tall flat-topped mesas (8-14 voxels) with vertical peach faces?
2. Is strata subtle (low contrast), with a thin grass lip on top?
3. Do mesa tops carry ruined castles, towers or walls?
4. Does a river wind between mesas and fall off the rim at least once?
5. Are roads and trails tan (not grey), roads wider and lighter?
6. Are paths axis-aligned with stairs on slopes and at least one bridge?
7. Are lowlands densely forested with 4+ tree variants and clearings, mesa tops mostly bare?
8. Is there a village of small pitched-roof houses on flat lowland?
9. Is the underside a shallow, ragged taper with dark drips, finished from all four angles?
10. Is the background soft beige with gentle tilt-shift?
11. In grayscale, can you separate path, ground, water, cliff?
12. Does it read as the reference grown larger, not a different game?
