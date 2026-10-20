extends Node
## Autoload "RunFlow". Scene switching for the run loop.

const SCENES := {
	"title": "res://scenes/run/title.tscn",
	"map": "res://scenes/run/run_map.tscn",
	"battle": "res://scenes/battle.tscn",
	"reward": "res://scenes/run/reward.tscn",
	"campfire": "res://scenes/run/campfire.tscn",
	"shop": "res://scenes/run/shop.tscn",
	"victory": "res://scenes/run/victory.tscn",
	"defeat": "res://scenes/run/defeat.tscn",
}

func go(state_name: String) -> void:
	if not SCENES.has(state_name):
		push_error("RunFlow.go: unknown state '%s'" % state_name)
		return
	get_tree().change_scene_to_file(SCENES[state_name])
