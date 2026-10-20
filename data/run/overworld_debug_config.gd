extends RefCounted
## Tunables for the overworld harness (overworld_debug.gd, overworld_cache.gd).
const PRINT_TIMING := true
## Whole-build budget the brief asks for (interactive speed), milliseconds.
const BUDGET_MS := 2500.0
## Key that cycles OverworldDebug.Layer in the view (wired in a later phase).
const LAYER_KEY := KEY_F3
## Maps kept in the static cache; oldest dropped first.
const CACHE_MAX := 2
## island_mask_test.gd saves the black/white island mask of each seed as a PNG under user:// (debug view of step 2a-2).
const SAVE_ISLAND_MASK_PNG := true
## Pixels per cell in that PNG.
const ISLAND_MASK_PNG_SCALE := 6
