extends Control
## Placeholder screen: a Label and one button that moves the run to `next_state`.

@export var title_text := ""
@export var button_text := "Continue"
@export var next_state := ""
## Title only: starts a new run before leaving.
@export var starts_run := false

@onready var _label: Label = $Center/Panel/Box/Label
@onready var _button: Button = $Center/Panel/Box/Button

func _ready() -> void:
	_label.text = title_text
	_button.text = button_text
	_button.pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if starts_run:
		RunState.new_run(randi())
	RunFlow.go(next_state)
