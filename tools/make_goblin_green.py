"""Writes art/units/Adv_Adv_demo_goblin_green.png: the sheet's gold goblin (block at cell 6,4,
3 frames x 4 facings of 32x32) hue-shifted to green, so the goblin archer is not a clone of the goblin.
Run from the project root:  python3 tools/make_goblin_green.py   (needs Pillow)"""
import colorsys
from PIL import Image

SRC = "art/units/Adv_Adv_demo.png"
DST = "art/units/Adv_Adv_demo_goblin_green.png"
BLOCK_COL, BLOCK_ROW, FRAME = 6, 4, 32
HUE_SHIFT = 55 / 360.0   # gold (~50 deg) -> green (~105 deg)

sheet = Image.open(SRC).convert("RGBA")
block = sheet.crop((BLOCK_COL * FRAME, BLOCK_ROW * FRAME, (BLOCK_COL + 3) * FRAME, (BLOCK_ROW + 4) * FRAME))
px = block.load()
for y in range(block.height):
    for x in range(block.width):
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.15:          # outlines / near-black / near-white stay as they are
            continue
        r2, g2, b2 = colorsys.hsv_to_rgb((h + HUE_SHIFT) % 1.0, min(s * 1.05, 1.0), v)
        px[x, y] = (round(r2 * 255), round(g2 * 255), round(b2 * 255), a)
block.save(DST)
print("wrote", DST, block.size)
