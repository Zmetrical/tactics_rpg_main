extends RefCounted
## The read-only world a spell behaviour looks at. No Battle reference, so behaviours stay pure
## and the preview can run them without touching any game state.

const Ability = preload("res://scripts/battle/ability.gd")
const Grid = preload("res://scripts/battle/grid.gd")
const Unit = preload("res://scripts/battle/unit.gd")

var grid: Grid
var units: Array = []
var caster: Unit
var spell: Ability
var tier: int = 1

func _init(p_grid: Grid, p_units: Array, p_caster: Unit, p_spell: Ability, p_tier: int = 1) -> void:
	grid = p_grid
	units = p_units
	caster = p_caster
	spell = p_spell
	tier = clampi(p_tier, 1, int(spell.get("max_tier")) if spell.get("max_tier") != null else 3)

## The living unit on a cell, or null.
func unit_at(cell: Vector2i) -> Unit:
	for u: Unit in units:
		if u.is_alive() and u.cell == cell:
			return u
	return null

func is_hostile(u: Unit) -> bool:
	return u != null and u.side != caster.side
