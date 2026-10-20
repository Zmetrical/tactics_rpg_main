# Terrain tileset

Terrain blocks are drawn from `art/tilesets/adventure_begins/AdventureBegins_Demo.png` (16x16 tiles)
by `shaders/terrain_block.gdshader`. Which tiles each block uses is the `TILES` table in
`scripts/battle/terrain_tiles.gd` (rects are in tile units from the sheet's top-left).

- `top`: tiles picked per cell for the top face (use seamless interior tiles).
- `side`: cliff tiles; row 0 is the top edge, the last row repeats downward.
- `tint`: brightness multiplier (the sheet is bright; the default is `DEFAULT_TINT`).

After editing `TILES`, re-bake the editor library so map scenes match:

    godot --headless -s tools/bake_tile_library.gd

## Side faces

The face, the tile column and the hash all come from `flat` varyings, and sampling is done in whole
texels. Do not hash an interpolated value (the normal, a UV): the hash is chaotic, so one-ulp
interpolation error picks a different tile per pixel and the face tears into sub-texel noise.
A face taller than the `side` rows keeps going by ping-ponging over the lower half of the last row
instead of restarting the tile (which would repeat the grass fringe halfway down a cliff).
