class_name InspectPanel
extends ActiveUnitPanel
## Bottom-right hover info, a fixed-size box that is always on screen:
##   unit under the cursor -> laid out exactly like the current-unit panel
##   empty tile            -> the tile's description
##   nothing hovered       -> a short placeholder
## Display only: the whole subtree ignores the mouse so map hover keeps working underneath.

@onready var _unit_view: Control = $Rows
@onready var _tile_view: Control = %TileView
@onready var _tile_title: Label = %TileTitle
@onready var _tile_info: Label = %TileInfo

func _ready() -> void:
	super._ready()
	clear()

func show_hover(unit: Unit) -> void:
	_unit_view.visible = true
	_tile_view.visible = false
	update_unit(unit)

## tile_lines are written by battle_view (they need the grid).
func show_tile(title: String, tile_lines: Array[String]) -> void:
	_show_text(title, "\n".join(tile_lines))

func clear() -> void:
	_show_text("Hover", "Hover a unit or a tile to see its details.")

func _show_text(title: String, body: String) -> void:
	visible = true
	_unit_view.visible = false
	_tile_view.visible = true
	_tile_title.text = title
	_tile_info.text = body
