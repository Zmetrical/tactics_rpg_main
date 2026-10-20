extends Control
## Victory / defeat summary: seed, nodes cleared, gold, gear worn by each unit. New Run -> title.
## Same script for both scenes; `victory` picks the heading.

const Equipment = preload("res://scripts/inventory/equipment.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const RunUi = preload("res://scripts/run/run_ui.gd")
const RunMapView = preload("res://scripts/run/run_map_view.gd")

@export var victory := true

@onready var box: VBoxContainer = $Center/Panel/Box

func _ready() -> void:
	if not RunState.active:
		RunState.new_run(randi())  # scene launched on its own
	var heading := RunUi.label(box, "VICTORY" if victory else "DEFEAT", Palette.ACCENT if victory else Palette.HP_RED)
	heading.theme_type_variation = &"BannerLabel"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(RunUi.divider())
	var stats := GridContainer.new()
	stats.columns = 2
	box.add_child(stats)
	_stat(stats, "Seed", str(RunState.seed))
	_stat(stats, "Nodes cleared", str(_nodes_cleared()))
	_stat(stats, "Gold", str(RunState.gold))
	RunUi.label(box, "Gear worn")
	for member in RunState.party:
		var names: Array[String] = []
		for slot in Equipment.ARMOR_SLOTS + Equipment.GEAR_SLOTS:
			var item = member.equipment.get_item(slot)
			if item != null:
				names.append(item.display_name)
		var card := RunUi.card()
		var col := VBoxContainer.new()
		card.add_child(col)
		RunUi.label(col, member.unit_data.display_name, Palette.ACCENT)
		var gear := RunUi.label(col, ", ".join(names) if not names.is_empty() else "nothing", Palette.INK_LIGHT)
		gear.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gear.custom_minimum_size.x = 380.0
		box.add_child(card)
	var button := Button.new()
	button.text = "New Run"
	button.pressed.connect(_on_new_run)
	box.add_child(button)

## The map view records every node entered. After a defeat the last one was the lost fight.
func _nodes_cleared() -> int:
	var entered: int = RunMapView._visited.size()
	return entered if victory else maxi(0, entered - 1)

func _stat(grid: GridContainer, key: String, value: String) -> void:
	var k := RunUi.label(grid, key, Palette.INK_LIGHT)
	k.custom_minimum_size.x = 160.0
	RunUi.label(grid, value)

func _on_new_run() -> void:
	RunState.end_run()
	RunFlow.go("title")
