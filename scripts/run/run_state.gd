extends Node
## Autoload "RunState". Everything that lives for one run. No rendering.

const Inventory = preload("res://scripts/inventory/inventory.gd")
const Equipment = preload("res://scripts/inventory/equipment.gd")
const RunTuning = preload("res://scripts/run/run_tuning.gd")
const UnitData = preload("res://scripts/battle/unit_data.gd")

class PartyMember extends RefCounted:
	var unit_data: UnitData
	var current_hp: int = 0
	var equipment: Equipment

var seed: int = 0
var rng := RandomNumberGenerator.new()
var gold: int = 0
var party: Array[PartyMember] = []
var bag: Inventory = Inventory.new()
## Filled in a later phase.
var map = null
var current_node = null
var active := false

func new_run(p_seed: int) -> void:
	seed = p_seed
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	gold = RunTuning.START_GOLD
	bag = Inventory.new()
	map = null
	current_node = null
	party = []
	for path in RunTuning.STARTING_PARTY:
		var member := PartyMember.new()
		member.unit_data = load(path)
		member.current_hp = member.unit_data.max_hp
		member.equipment = Equipment.new()
		for item in member.unit_data.starting_equipment:
			member.equipment.try_equip(item)
		party.append(member)
	active = true

func end_run() -> void:
	active = false
