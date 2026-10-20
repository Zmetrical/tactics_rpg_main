class_name BattleBanner
extends Control
## Full-screen, mouse-transparent overlay: the slim map-info strip at top-center and the
## VICTORY / DEFEAT banner at screen center.

@onready var _map_info: Label = %MapInfo
@onready var _result_panel: PanelContainer = %ResultPanel
@onready var _result: Label = %Result

func set_map_info(biome: String, map_size: String, map_name: String, enemy_count: int, population: String) -> void:
	# Two short lines, like a Pokemon header box, instead of one long strip that wraps mid-phrase.
	_map_info.text = "Biome: %s | Size: %s\nMap: %s | %d enemies (%s)" % [biome, map_size, map_name, enemy_count, population]

func show_result(player_won: bool) -> void:
	_result.text = "VICTORY" if player_won else "DEFEAT"
	_result_panel.visible = true
