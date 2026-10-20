#!/usr/bin/env python3
"""Builds the Game Boy Color-style HUD art used by res://ui/theme/.

  python3 tools/make_gbc_assets.py

Writes (all hand-drawn here, no third-party font or art):
  ui/theme/fonts/gbc_font.png   white 5x7 pixel glyphs on transparent, drawn 2x (10x14 px)
  ui/theme/fonts/gbc_font.fnt   BMFont text descriptor (Godot imports it as a FontFile)
  ui/theme/gbc_frame.png        9-slice double-line frame with stepped (chamfered) corners

Lowercase letters share the uppercase glyphs, so every string in the HUD reads ALL CAPS
without touching the game's text.
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
THEME = os.path.join(ROOT, "ui", "theme")
FONTS = os.path.join(THEME, "fonts")

SCALE = 2           # one art pixel = SCALE x SCALE screen pixels
GLYPH_W, GLYPH_H = 5, 7
ADVANCE = 6         # art pixels per character cell (5 + 1 gap)
LINE = 8            # art pixels per line (7 + 1 gap)

# --- glyphs: 7 rows of 5 columns, '#' = ink ---------------------------------------------------
G = {}

def g(ch, *rows):
    assert len(rows) == 7 and all(len(r) == 5 for r in rows), ch
    G[ch] = rows

g("A", ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#")
g("B", "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####.")
g("C", ".###.", "#...#", "#....", "#....", "#....", "#...#", ".###.")
g("D", "####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####.")
g("E", "#####", "#....", "#....", "####.", "#....", "#....", "#####")
g("F", "#####", "#....", "#....", "####.", "#....", "#....", "#....")
g("G", ".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###.")
g("H", "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#")
g("I", ".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###.")
g("J", "..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##..")
g("K", "#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#")
g("L", "#....", "#....", "#....", "#....", "#....", "#....", "#####")
g("M", "#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#")
g("N", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#")
g("O", ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.")
g("P", "####.", "#...#", "#...#", "####.", "#....", "#....", "#....")
g("Q", ".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#")
g("R", "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#")
g("S", ".####", "#....", "#....", ".###.", "....#", "....#", "####.")
g("T", "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..")
g("U", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.")
g("V", "#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#..")
g("W", "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#")
g("X", "#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#")
g("Y", "#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#..")
g("Z", "#####", "....#", "...#.", "..#..", ".#...", "#....", "#####")

g("0", ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###.")
g("1", "..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###.")
g("2", ".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####")
g("3", ".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###.")
g("4", "...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#.")
g("5", "#####", "#....", "####.", "....#", "....#", "#...#", ".###.")
g("6", "..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###.")
g("7", "#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#...")
g("8", ".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###.")
g("9", ".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##..")

g(" ", ".....", ".....", ".....", ".....", ".....", ".....", ".....")
g(".", ".....", ".....", ".....", ".....", ".....", ".##..", ".##..")
g(",", ".....", ".....", ".....", ".....", ".##..", "..#..", ".#...")
g(":", ".....", ".##..", ".##..", ".....", ".##..", ".##..", ".....")
g(";", ".....", ".##..", ".##..", ".....", ".##..", "..#..", ".#...")
g("!", "..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#..")
g("?", ".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#..")
g("-", ".....", ".....", ".....", "#####", ".....", ".....", ".....")
g("+", ".....", "..#..", "..#..", "#####", "..#..", "..#..", ".....")
g("=", ".....", ".....", "#####", ".....", "#####", ".....", ".....")
g("/", "....#", "....#", "...#.", "..#..", ".#...", "#....", "#....")
g("\\", "#....", "#....", ".#...", "..#..", "...#.", "....#", "....#")
g("(", "...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#.")
g(")", ".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#...")
g("[", ".###.", ".#...", ".#...", ".#...", ".#...", ".#...", ".###.")
g("]", ".###.", "...#.", "...#.", "...#.", "...#.", "...#.", ".###.")
g("{", "..##.", ".#...", ".#...", "#....", ".#...", ".#...", "..##.")
g("}", ".##..", "...#.", "...#.", "....#", "...#.", "...#.", ".##..")
g("|", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..")
g("%", "##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##")
g("'", "..#..", "..#..", ".....", ".....", ".....", ".....", ".....")
g('"', ".#.#.", ".#.#.", ".....", ".....", ".....", ".....", ".....")
g("`", ".#...", "..#..", ".....", ".....", ".....", ".....", ".....")
g("*", ".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", ".....")
g("<", "...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#.")
g(">", ".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#...")
g("_", ".....", ".....", ".....", ".....", ".....", ".....", "#####")
g("#", ".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#.")
g("&", ".##..", "#..#.", "#..#.", ".##..", "#.#.#", "#..#.", ".##.#")
g("@", ".###.", "#...#", "#.###", "#.#.#", "#.###", "#....", ".###.")
g("$", "..#..", ".####", "#.#..", ".###.", "..#.#", "####.", "..#..")
g("^", "..#..", ".#.#.", "#...#", ".....", ".....", ".....", ".....")
g("~", ".....", ".....", ".##.#", "#.##.", ".....", ".....", ".....")

# Symbols the HUD uses as cursors / markers.
g("\u25b6", "#....", "##...", "###..", "####.", "###..", "##...", "#....")   # right arrow cursor
g("\u25c0", "....#", "...##", "..###", ".####", "..###", "...##", "....#")   # left arrow cursor
g("\u25bc", ".....", ".....", "#####", ".###.", "..#..", ".....", ".....")   # "next" arrow
g("\u25b2", ".....", ".....", "..#..", ".###.", "#####", ".....", ".....")
g("\u2642", "..###", "...##", ".###.", "#...#", "#...#", "#...#", ".###.")   # male glyph
g("\u2640", ".###.", "#...#", "#...#", ".###.", "..#..", ".###.", "..#..")   # female glyph
g("\u00b7", ".....", ".....", ".....", "..#..", ".....", ".....", ".....")   # middle dot
g("\u2022", ".....", ".....", ".##..", ".##..", ".....", ".....", ".....")   # bullet
g("\u2026", ".....", ".....", ".....", ".....", ".....", ".....", "#.#.#")   # ellipsis
g("\u2014", ".....", ".....", ".....", "#####", ".....", ".....", ".....")   # em dash
g("\u00d7", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", ".....")   # multiply sign
g("\u2192", ".....", "..#..", "...#.", "#####", "...#.", "..#..", ".....")   # right arrow
g("\u00b0", ".##..", "#..#.", "#..#.", ".##..", ".....", ".....", ".....")   # degree
g("\u25a0", ".....", ".###.", ".###.", ".###.", ".###.", ".###.", ".....")   # filled square

# char code -> glyph key (lowercase reuses uppercase)
CODES = {}
for ch in G:
    CODES[ord(ch)] = ch
for c in range(ord("a"), ord("z") + 1):
    CODES[c] = chr(c).upper()

def build_font() -> None:
    os.makedirs(FONTS, exist_ok=True)
    # one atlas cell per distinct glyph; lowercase chars alias the same cell
    keys = list(G.keys())
    cell_w = ADVANCE * SCALE
    cell_h = LINE * SCALE
    cols = 16
    rows = (len(keys) + cols - 1) // cols
    atlas = Image.new("RGBA", (cols * cell_w, rows * cell_h), (0, 0, 0, 0))
    where = {}
    for i, key in enumerate(keys):
        cx, cy = (i % cols) * cell_w, (i // cols) * cell_h
        where[key] = (cx, cy)
        for y, row in enumerate(G[key]):
            for x, px in enumerate(row):
                if px == "#":
                    for dy in range(SCALE):
                        for dx in range(SCALE):
                            atlas.putpixel((cx + x * SCALE + dx, cy + y * SCALE + dy), (255, 255, 255, 255))
    atlas.save(os.path.join(FONTS, "gbc_font.png"))

    size = LINE * SCALE
    base = GLYPH_H * SCALE
    lines = [
        'info face="GBC Pixel" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=0,0 outline=0' % size,
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0" % (size, base, atlas.width, atlas.height),
        'page id=0 file="gbc_font.png"',
        "chars count=%d" % len(CODES),
    ]
    for code in sorted(CODES):
        x, y = where[CODES[code]]
        lines.append(
            "char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15"
            % (code, x, y, GLYPH_W * SCALE, GLYPH_H * SCALE, ADVANCE * SCALE))
    with open(os.path.join(FONTS, "gbc_font.fnt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

# --- frame ------------------------------------------------------------------------------------
# Top-left 6x6 corner, X = ink, o = panel white, . = transparent. The frame is the Pokemon
# Gold/Silver text-box look: an outer line, a one-pixel gap, an inner line, corners cut in steps.
CORNER = [
    "..XXXX",
    ".Xoooo",
    "Xoo XXX".replace(" ", ""),
    "XoXooo",
    "XoXooo",
    "XoXooo",
]
CORNER_N = 6
FRAME_ART = 2 * CORNER_N + 1          # one stretchable centre row/column

def frame_pixel(x: int, y: int):
    """Colour of one art pixel of the frame, or None for transparent."""
    def corner_at(cx, cy):
        return CORNER[min(cy, CORNER_N - 1)][min(cx, CORNER_N - 1)]
    cx = x if x < CORNER_N else (FRAME_ART - 1 - x if x >= FRAME_ART - CORNER_N else CORNER_N - 1)
    cy = y if y < CORNER_N else (FRAME_ART - 1 - y if y >= FRAME_ART - CORNER_N else CORNER_N - 1)
    return {"X": (24, 24, 32, 255), "o": (248, 248, 248, 255), ".": None}[corner_at(cx, cy)]

def build_frame() -> None:
    n = FRAME_ART
    img = Image.new("RGBA", (n * SCALE, n * SCALE), (0, 0, 0, 0))
    for y in range(n):
        for x in range(n):
            c = frame_pixel(x, y)
            if c is None:
                continue
            for dy in range(SCALE):
                for dx in range(SCALE):
                    img.putpixel((x * SCALE + dx, y * SCALE + dy), c)
    img.save(os.path.join(THEME, "gbc_frame.png"))

if __name__ == "__main__":
    build_font()
    build_frame()
    print("wrote", FONTS, "and", os.path.join(THEME, "gbc_frame.png"))
