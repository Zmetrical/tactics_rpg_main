class_name ChargeTracker
extends PanelContainer
## Right-side list of charging spells. Hidden when nothing is charging.

const Unit = preload("res://scripts/battle/unit.gd")
const ChargeRow = preload("res://ui/charge_row.gd")
const ROW_SCENE: PackedScene = preload("res://ui/charge_row.tscn")

@onready var _entries: VBoxContainer = %Entries

## rows: {"caster": Unit, "spell": String, "ticks": int}, oldest cast first.
func update_casts(rows: Array[Dictionary]) -> void:
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	visible = not rows.is_empty()
	for row: Dictionary in rows:
		var entry := ROW_SCENE.instantiate() as ChargeRow
		_entries.add_child(entry)
		entry.set_entry(row["caster"], String(row["spell"]), int(row["ticks"]))
