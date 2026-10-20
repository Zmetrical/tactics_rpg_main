class_name ReactionPrompt
extends Control
## Centered modal asking whether to take an opportunity attack. The full-screen root stops the
## mouse, so the map cannot be clicked while a decision is pending.

signal answered(take_it: bool)

const Unit = preload("res://scripts/battle/unit.gd")

@onready var _message: Label = %Message
@onready var _yes: Button = %Yes
@onready var _no: Button = %No

func _ready() -> void:
	_yes.pressed.connect(_answer.bind(true))
	_no.pressed.connect(_answer.bind(false))

func open(reactor: Unit, mover: Unit) -> void:
	_message.text = "%s may make an opportunity attack on %s." % [reactor.unit_name, mover.unit_name]
	visible = true

func close() -> void:
	visible = false

func _answer(take_it: bool) -> void:
	visible = false
	answered.emit(take_it)
