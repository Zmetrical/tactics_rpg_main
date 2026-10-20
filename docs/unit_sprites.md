# Unit sprites

Units are billboarded `Sprite3D`s cut out of a character sheet (`art/units/Adv_Adv_demo.png`).
`scripts/battle/unit_sprites.gd` has the table of which character draws which unit
(key = the unit `.tres` file name) and the facing rules.

- Frames are 32x32, feet on the bottom row. A character is 3 frames across (0 and 2 step, 1 stands)
  by 4 rows: front, left, right, back.
- One sprite pixel is one terrain texel (`Stage3D.PIXEL_SIZE = 1/16`), so characters and ground match.
- Only the front and back rows are used; the sheet's left / right rows are ignored. A unit heading away
  from the camera shows its back, anything else shows its front. The row is picked every frame from the
  unit's heading and the camera yaw, so rotating the camera swaps front and back accordingly.
- Units face the nearest opponent at the start of a battle, face the way they walk, and face their
  target when attacking. They keep that facing when they stop.
- Walking alternates frames 0 and 2 on each hop; the unit stands on frame 1 when the move ends.
- Units with no entry in `CHARACTERS` (or whose sheet is not imported yet) get the placeholder blob.

To change a unit's art, edit its entry in `CHARACTERS`: `sheet` is the PNG, `block` is the top-left
frame (column, row) of its 3x4 block on that sheet. Open the project in the editor once after adding
a PNG so Godot imports it.
