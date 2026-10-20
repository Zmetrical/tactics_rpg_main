extends RefCounted
## Tiny pixel-art strings for the overworld's trees and rocks (and the map's compass), turned into textures at runtime.
## One character = one pixel; '.' is transparent. Colours come from gbc_palette.gd (see key_colors()).
## Drawn at Stage3D.PIXEL_SIZE (1/16 world unit per pixel), like the unit sprites.

const Palette = preload("res://ui/theme/gbc_palette.gd")

## 12 x 16: two-tier crown (o outline, g leaf, l highlight) on a trunk (t).
const TREE: PackedStringArray = [
	"....oooo....",
	"..oogllgoo..",
	".ogglgggggo.",
	"oggggggglggo",
	"ogglgggggggo",
	".oggggggggo.",
	"..oooooooo..",
	".oggglggggo.",
	"oggggggglggo",
	".oooooooooo.",
	"....otto....",
	"....otto....",
	"....otto....",
	"....otto....",
	"...otttto...",
	"...oooooo...",
]

## 10 x 8: o outline, w light face, r body.
const ROCK: PackedStringArray = [
	"...oooo...",
	"..owwwrro.",
	".owwwrrrro",
	"owwrrrrrro",
	"orrrrrrrro",
	"orrrrrrrro",
	"orrrrrrroo",
	".oooooooo.",
]

## 16 x 16 placeholder compass, north up: o ring, w face, n north needle (red), r south needle, o hub.
const COMPASS: PackedStringArray = [
	".......oo.......",
	"....ooowwooo....",
	"...owwwnnwwwo...",
	"..owwwwnnwwwwo..",
	".owwwwnnnnwwwwo.",
	".owwwwnnnnwwwwo.",
	".owwwnnnnnnwwwo.",
	"owwwwnnoonnwwwwo",
	"owwwwrroorrwwwwo",
	".owwwrrrrrrwwwo.",
	".owwwwrrrrwwwwo.",
	".owwwwrrrrwwwwo.",
	"..owwwwrrwwwwo..",
	"...owwwrrwwwo...",
	"....ooowwooo....",
	".......oo.......",
]

## 32 x 14 mist cloud, drawn translucent: m body, b paler fringe. Ragged outline, nothing touches the sprite's
## border and no edge runs straight for more than 3 pixels.
const MIST: PackedStringArray = [
	"................................",
	"..............b.b...............",
	"...........bbbmbmb..............",
	".......bb.bmmmmmmmbbb...........",
	".....bbmmbmmmmmmmmmmmbbb........",
	"....bmmmmmmmmmmmmmmmmmmmbb......",
	"....bmmmmmmmmmmmmmmmmmmmmb.bbb..",
	"...bbmmmmmmmmmmmmmmmmmmmmmbmb...",
	".....bmmmmmbmmmmmmmmmmmmmmmb....",
	"....bmmmmmb.bmbmmmmmmmbmmbb.b...",
	".....bmmmb...b.bbbmmmb.bb.......",
	"......bbb.........bbb...........",
	"................................",
	"................................",
]

static var _cache := {}

## Texture of a named sprite: "tree", "rock", "compass" or "mist" (cached, use nearest filtering). null for an unknown name.
static func sprite(kind: String) -> ImageTexture:
	match kind:
		"tree":
			return texture(TREE)
		"rock":
			return texture(ROCK)
		"compass":
			return texture(COMPASS)
		"mist":
			return texture(MIST)
	push_error("MapPixels.sprite: unknown sprite '%s'" % kind)
	return null

## char -> Color. Palette colours only; the trunk is the palette's orange pushed dark.
static func key_colors() -> Dictionary:
	return {
		"o": Palette.INK,
		"g": Palette.HP_GREEN,
		"l": Palette.HP_YELLOW,
		"t": Palette.ARMOR_SHRED.darkened(0.5),
		"w": Palette.DISABLED_FILL,
		"r": Palette.INK_LIGHT,
		"n": Palette.HP_RED,
		"m": Palette.PANEL,
		"b": Palette.BG,
	}

## ImageTexture for TREE or ROCK (cached). Use with nearest filtering.
static func texture(rows: PackedStringArray) -> ImageTexture:
	var key := rows[0] + str(rows.size())
	if _cache.has(key):
		return _cache[key]
	var colors := key_colors()
	var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row := rows[y]
		for x in row.length():
			var ch := row[x]
			if colors.has(ch):
				img.set_pixel(x, y, colors[ch])
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
