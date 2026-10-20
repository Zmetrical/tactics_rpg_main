extends Control
## Campfire: one choice. Rest heals the party once per visit, Continue returns to the map.

const CampfireLogic = preload("res://scripts/run/campfire_logic.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const StatBar = preload("res://ui/hud/stat_bar.gd")
const NAME_W := 110.0

@onready var rest_button: Button = $Center/Panel/Box/RestButton
@onready var report: VBoxContainer = $Center/Panel/Box/Report
@onready var continue_button: Button = $Center/Panel/Box/ContinueButton

var _rested := false

func _ready() -> void:
	if not RunState.active:
		RunState.new_run(randi())  # scene launched on its own
	rest_button.pressed.connect(_on_rest)
	continue_button.pressed.connect(func() -> void: RunFlow.go("map"))

func _on_rest() -> void:
	if _rested:
		return
	_rested = true
	rest_button.disabled = true
	for row in CampfireLogic.rest(RunState.party):
		report.add_child(_make_row(row))

## Name + the HUD's HP bar, filling from the old value to the healed one.
func _make_row(row: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = row.name
	name_label.custom_minimum_size.x = NAME_W
	line.add_child(name_label)
	var bar: StatBar = StatBar.new()
	bar.fill_color = Palette.hp_color(float(row.after) / maxf(float(row.max), 1.0))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.x = 240.0
	line.add_child(bar)
	bar.set_values(row.before, row.max, true)
	bar.set_values(row.after, row.max, false)
	return line
