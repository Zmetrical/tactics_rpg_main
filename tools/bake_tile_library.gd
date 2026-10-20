extends SceneTree
## Rewrites data/maps/tile_library.tres (the MeshLibrary the map scenes' GridMaps use) from the
## tile table in scripts/battle/terrain_tiles.gd. Run it after changing TILES:
##     godot --headless -s tools/bake_tile_library.gd
## Item ids stay 0-3 = height level, 4 = wall, so existing map scenes keep working untouched.

const Stage3D = preload("res://scripts/battle/stage_3d.gd")
const TerrainTiles = preload("res://scripts/battle/terrain_tiles.gd")

const OUT_PATH := "res://data/maps/tile_library.tres"

func _initialize() -> void:
	var lib := TerrainTiles.build_library(Stage3D.STEP, Stage3D.BASE_DEPTH, Stage3D.WALL_LEVEL)
	var err := ResourceSaver.save(lib, OUT_PATH)
	if err != OK:
		push_error("bake_tile_library: could not save %s (error %d)" % [OUT_PATH, err])
		quit(1)
		return
	print("Baked %d blocks into %s" % [lib.get_item_list().size(), OUT_PATH])
	quit(0)
