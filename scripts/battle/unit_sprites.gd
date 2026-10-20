extends RefCounted
## Which character of the sprite sheet draws which unit, and which frame to show.
##
## Sheet layout (RPG-Maker style, "Adventure Begins" characters): every frame is 32x32 with the
## character's feet on the bottom row. A character is a block of 3 frames across (0 and 2 are the
## two walking steps, 1 is standing) by 4 rows down: front (faces the camera), left, right, back.
## `block` is the block's top-left corner in FRAMES (column, row) on its sheet.
##
## To give a unit other art, change its entry in CHARACTERS (key = the unit .tres file name).
## Units without an entry get the generated placeholder blob from stage_3d.gd.

const FRAME := 32
const FRAMES_ACROSS := 3
const IDLE_FRAME := 1
const STEP_FRAMES: Array[int] = [0, 2]

enum Row { FRONT, LEFT, RIGHT, BACK }

const SHEET := "res://art/units/Adv_Adv_demo.png"
## Same sheet block for the goblin, hue-shifted green (tools/make_goblin_green.py).
const SHEET_GOBLIN_GREEN := "res://art/units/Adv_Adv_demo_goblin_green.png"

## Not used by any unit yet: the pink-hat mushroom monster at block (3, 4) and the hooded figure at (9, 0).
const CHARACTERS := {
	"fighter": {"sheet": SHEET, "block": Vector2i(0, 4)},        # armored knight (helm, red cape)
	"mage": {"sheet": SHEET, "block": Vector2i(0, 0)},           # blue-haired mage in robes
	"ranger": {"sheet": SHEET, "block": Vector2i(3, 0)},         # the girl with the red hair
	"orc": {"sheet": SHEET, "block": Vector2i(6, 0)},            # stocky brown brute
	"goblin": {"sheet": SHEET, "block": Vector2i(6, 4)},         # gold goblin
	"goblin_archer": {"sheet": SHEET_GOBLIN_GREEN, "block": Vector2i(0, 0)},
}

## sheet path -> Texture2D, and (sheet path + block) -> visible height in pixels.
static var _textures: Dictionary = {}
static var _body_px: Dictionary = {}

static func has_character(file_name: String) -> bool:
	return CHARACTERS.has(file_name)

## The sheet texture for a unit, or null when it has no entry / the file is missing or not imported yet.
static func sheet_for(file_name: String) -> Texture2D:
	if not CHARACTERS.has(file_name):
		return null
	var path: String = CHARACTERS[file_name]["sheet"]
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]

## Region of the sheet to show: `row` is a Row, `frame` 0..2.
static func frame_rect(file_name: String, row: int, frame: int) -> Rect2:
	var block: Vector2i = CHARACTERS[file_name]["block"]
	return Rect2((block.x + frame) * FRAME, (block.y + row) * FRAME, FRAME, FRAME)

## Height of the drawn character in pixels (top opaque row of the standing front frame down to the
## feet), used to aim hits and numbers at the chest instead of at the middle of the 32 px frame.
static func body_height_px(file_name: String) -> int:
	var tex := sheet_for(file_name)
	if tex == null:
		return FRAME
	var path: String = CHARACTERS[file_name]["sheet"]
	var key := "%s:%s" % [path, CHARACTERS[file_name]["block"]]
	if _body_px.has(key):
		return _body_px[key]
	var height := FRAME
	var img := tex.get_image()
	if img != null and not img.is_empty():
		var r := frame_rect(file_name, Row.FRONT, IDLE_FRAME)
		for y in FRAME:
			var seen := false
			for x in FRAME:
				if img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.0:
					seen = true
					break
			if seen:
				height = FRAME - y
				break
	_body_px[key] = height
	return height

## Which Row shows a unit heading `facing` (world x/z direction) to a camera looking along `cam_forward`
## (world x/z, normalised). Only the front and back rows are used: a unit heading away from the camera
## shows its back, anything else shows its front. The sheet's left / right rows are ignored on purpose.
static func row_for(facing: Vector2, cam_forward: Vector2) -> int:
	return Row.BACK if facing.dot(cam_forward) > 0.05 else Row.FRONT
