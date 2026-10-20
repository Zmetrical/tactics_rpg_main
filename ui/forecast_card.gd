extends VBoxContainer
## One Fire Emblem-style forecast: attacker | stat labels | defender.
## Call show_forecast() after the node is in the tree.

const SideTint = preload("res://ui/side_tint.gd")
const Unit = preload("res://scripts/battle/unit.gd")

const COLUMNS := 3
const LEFT := 0
const MIDDLE := 1
const RIGHT := 2
const ROW_NAME := 0
const ROW_HP := 1
const ROW_DMG := 2
const ROW_HIT := 3
const ROW_CRIT := 4
const ROW_WEAPON := 5
const NONE_TEXT := "--"

@onready var _grid: GridContainer = %Grid
@onready var _note: Label = %Note

func show_forecast(f: Dictionary) -> void:
	var attacker: Unit = f["attacker"]
	var defender: Unit = f["defender"]
	_name(ROW_NAME, LEFT, attacker)
	_name(ROW_NAME, RIGHT, defender)
	_cell(ROW_HP, LEFT).text = str(attacker.hp)
	_cell(ROW_HP, MIDDLE).text = "HP"
	_cell(ROW_HP, RIGHT).text = str(defender.hp)
	_cell(ROW_DMG, LEFT).text = str(int(f["dmg"]))
	_cell(ROW_DMG, MIDDLE).text = "Dmg"
	_cell(ROW_HIT, LEFT).text = _percent(int(f["hit"]))
	_cell(ROW_HIT, MIDDLE).text = String(f["chance_label"])
	_cell(ROW_CRIT, LEFT).text = _percent(int(f["crit"]))
	_cell(ROW_CRIT, MIDDLE).text = "Crit"
	_cell(ROW_WEAPON, LEFT).text = String(f["weapon"])
	_cell(ROW_WEAPON, MIDDLE).text = String(f["mode_name"])
	# Nothing counterattacks in this game, so the defender's side stays empty, as in Fire Emblem
	# when a unit cannot retaliate.
	for row in [ROW_DMG, ROW_HIT, ROW_CRIT, ROW_WEAPON]:
		_cell(row, RIGHT).text = NONE_TEXT
	_note.text = String(f["note"])

func _cell(row: int, col: int) -> Label:
	return _grid.get_child(row * COLUMNS + col) as Label

func _name(row: int, col: int, unit: Unit) -> void:
	var label := _cell(row, col)
	label.text = unit.unit_name
	label.add_theme_color_override("font_color", SideTint.color_for(unit.side))

func _percent(value: int) -> String:
	return NONE_TEXT if value < 0 else "%d%%" % value
