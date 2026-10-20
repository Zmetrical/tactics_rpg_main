extends RefCounted
## Which tiles of the terrain sheet draw which block, and the MeshLibrary built from that.
##
## Both the live battle (stage_3d.gd) and the library the map scenes are authored with
## (data/maps/tile_library.tres) come from build_library(), so editor and game always match.
## After changing TILES, regenerate the .tres:
##     godot --headless -s tools/bake_tile_library.gd
##
## Sheet: "Adventure Begins" demo tileset by Zaebucca, 16x16 tiles (see art/tilesets/.../LICENSE.txt).
## All rects are in TILES (x, y, width, height), counted from the sheet's top-left corner.
##
##   top   Rect2i  tiles a block's top may use. One is picked per cell (stable, hashed from the
##                 cell). Choose seamless interior tiles: the sheet's edge pieces would draw a
##                 frame around every cell.
##   side  Rect2i  tiles for the four side faces. Columns are picked per face; row 0 is the top
##                 edge of the cliff, later rows continue down (the last row repeats).
##   flip  bool    flip / rotate top tiles at random for more variety (turn off for tiles with a
##                 lit side or text).
##   tint  Color   optional (default DEFAULT_TINT): multiplies the tile colours, to brighten / darken a block.
##   color Color   flat colour, only used if the sheet cannot be loaded.

const SHEET_PATH := "res://art/tilesets/adventure_begins/AdventureBegins_Demo.png"
const SHADER_PATH := "res://shaders/terrain_block.gdshader"

## false = plain flat colour per block (each tile's "color" below), no texture sheet or shader.
## true = the tileset textures. After changing this, re-bake the editor library:
##     godot --headless -s tools/bake_tile_library.gd
const USE_TEXTURES := false

## Index = block id = GridMap item id in every map scene: 0-3 are height levels, 4 is a wall.
const TILES: Array[Dictionary] = [
	{"name": "height_0", "top": Rect2i(2, 5, 1, 1), "side": Rect2i(1, 11, 3, 1), "flip": true,
		"color": Color(0.35, 0.60, 0.35)},   # plain meadow grass (seamless interior tile) on a mossy earth face
	{"name": "height_1", "top": Rect2i(9, 4, 1, 2), "side": Rect2i(1, 11, 3, 1), "flip": true,
		"color": Color(0.55, 0.65, 0.35)},   # leafy grass (interior tiles only), same earth face
	{"name": "height_2", "top": Rect2i(9, 12, 3, 1), "side": Rect2i(1, 17, 3, 1), "flip": true,
		"color": Color(0.72, 0.66, 0.40)},   # sand ripples (no edge pieces) on a golden boulder face
	{"name": "height_3", "top": Rect2i(2, 15, 1, 1), "side": Rect2i(1, 19, 3, 1), "flip": true,
		"tint": Color(0.40, 0.40, 0.40),
		"color": Color(0.82, 0.72, 0.52)},   # pale cobble cap on boulders
	{"name": "wall", "top": Rect2i(5, 7, 4, 1), "side": Rect2i(13, 14, 3, 1), "flip": false,
		"color": Color(0.50, 0.50, 0.56)},   # cobbled stone cap on a mossy stone wall
]

## The sheet is much brighter than the flat colours the terrain used to have, and the battle's sun
## plus ambient light would blow it out. Multiplied into every tile unless a block sets its own tint.
const DEFAULT_TINT := Color(0.52, 0.52, 0.52)

## Block id of the wall (the last entry); every earlier id is its own height level.
const WALL_BLOCK := 4

## One box per block, from -base_depth up to the block's top. The mesh origin sits at the cell's
## x/z centre, so cell (x, z) lands at world (x, z).
##   step        world units per height level (Stage3D.STEP)
##   base_depth  how far blocks reach below y = 0 (Stage3D.BASE_DEPTH)
##   wall_level  height level a wall is drawn at (Stage3D.WALL_LEVEL)
static func build_library(step: float, base_depth: float, wall_level: int) -> MeshLibrary:
	var sheet := _load_sheet() if USE_TEXTURES else null
	var shader: Shader = load(SHADER_PATH) if USE_TEXTURES else null
	var lib := MeshLibrary.new()
	for id in TILES.size():
		var def: Dictionary = TILES[id]
		var level := wall_level if id == WALL_BLOCK else id
		var top := level * step
		var height := top + base_depth
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, height, 1.0)
		mesh.material = _material(def, sheet, shader, height)
		lib.create_item(id)
		lib.set_item_name(id, str(def["name"]))
		lib.set_item_mesh(id, mesh)
		lib.set_item_mesh_transform(id, Transform3D(Basis.IDENTITY, Vector3(0.0, (top - base_depth) * 0.5, 0.0)))
	return lib

static func _material(def: Dictionary, sheet: Texture2D, shader: Shader, height: float) -> Material:
	if sheet == null or shader == null:
		var flat := StandardMaterial3D.new()
		flat.albedo_color = def["color"]
		flat.roughness = 1.0
		flat.metallic_specular = 0.0
		return flat
	var top: Rect2i = def["top"]
	var side: Rect2i = def["side"]
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("atlas", sheet)
	mat.set_shader_parameter("top_rect", Vector4i(top.position.x, top.position.y, top.size.x, top.size.y))
	mat.set_shader_parameter("side_rect", Vector4i(side.position.x, side.position.y, side.size.x, side.size.y))
	mat.set_shader_parameter("top_flip", def["flip"])
	mat.set_shader_parameter("block_height", height)
	mat.set_shader_parameter("tint", def.get("tint", DEFAULT_TINT))
	return mat

static func _load_sheet() -> Texture2D:
	if not ResourceLoader.exists(SHEET_PATH):
		push_warning("terrain_tiles: %s is missing, drawing flat colours instead" % SHEET_PATH)
		return null
	return load(SHEET_PATH) as Texture2D
