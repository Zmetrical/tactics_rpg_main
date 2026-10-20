class_name TurnOrderBar
extends PanelContainer
## Top-left strip of upcoming units. Fed by battle_view with the forecast; no game logic here.

const Unit = preload("res://scripts/battle/unit.gd")
const TurnChip = preload("res://ui/turn_chip.gd")
const TurnForecast = preload("res://ui/turn_forecast.gd")
const CHIP_SCENE: PackedScene = preload("res://ui/turn_chip.tscn")

@export var max_chips: int = 7

@onready var _chips: HBoxContainer = %Chips

var _last_sig: Array = []

## entries come from TurnForecast.predict_timeline(): turns and charged-spell releases in the
## order they will happen. The first turn entry is the current unit (NOW); later turns are numbered
## 2, 3, ...; a release shows the spell name on its caster's chip, marked RELEASE.
func update_order(entries: Array[Dictionary]) -> void:
	# battle_view refreshes on nearly every event; the forecast is usually identical, so keep the chips.
	var sig: Array = []
	for i in mini(entries.size(), max_chips):
		var e := entries[i]
		sig.append([e["kind"], e["unit"], String(e["spell"])])
	if sig == _last_sig and not _chips.get_child_count() == 0:
		return
	_last_sig = sig
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	visible = not entries.is_empty()
	var turn_no := 0
	for i in mini(entries.size(), max_chips):
		var e := entries[i]
		var chip := CHIP_SCENE.instantiate() as TurnChip
		_chips.add_child(chip)
		if e["kind"] == TurnForecast.KIND_RELEASE:
			chip.set_release(e["unit"] as Unit, String(e["spell"]))
		else:
			turn_no += 1
			chip.set_entry(e["unit"] as Unit, "NOW" if turn_no == 1 else str(turn_no))
