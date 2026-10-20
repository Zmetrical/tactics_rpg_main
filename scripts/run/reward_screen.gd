extends Control
## After a won fight: gold, the rolled gear (added to RunState.bag), and the existing equipment window
## so gear can be changed before the next node. No rules here beyond calling Loot.

const Equipment = preload("res://scripts/inventory/equipment.gd")
const Item = preload("res://scripts/inventory/item.gd")
const Loot = preload("res://scripts/run/loot.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const RunMap = preload("res://scripts/run/run_map.gd")
const RunUi = preload("res://scripts/run/run_ui.gd")
const Unit = preload("res://scripts/battle/unit.gd")

@onready var gold_label: Label = $Center/Panel/Box/GoldLabel
@onready var cards: VBoxContainer = $Center/Panel/Box/Cards
@onready var equip_button: Button = $Center/Panel/Box/Buttons/EquipButton
@onready var continue_button: Button = $Center/Panel/Box/Buttons/ContinueButton
@onready var window = $EquipmentWindow

var _units: Array[Unit] = []
var _is_boss := false

func _ready() -> void:
	if not RunState.active:
		RunState.new_run(randi())  # scene launched on its own
	var node := RunMap.MapNode.new()  # layer 0 battle, used only when there is no current node
	if RunState.map != null and RunState.current_node != null:
		node = RunState.map.nodes[int(RunState.current_node)]
	_is_boss = node.type == RunMap.NodeType.BOSS

	var gold := Loot.gold_for(node, RunState.rng)
	RunState.gold += gold
	gold_label.text = "Gold +%d   (total %d)" % [gold, RunState.gold]

	var bonus := Loot.rarity_bonus_for(node)
	for i in Loot.rolls_for(node):
		var item := Loot.roll_item(RunState.rng, node.layer, bonus)
		var added := RunState.bag.add(item) != null
		cards.add_child(_make_card(item, added))

	for member in RunState.party:
		_units.append(_make_unit(member))
	window.set_party(_units)
	window.unit_requested.connect(_open_unit)
	window.equipment_changed.connect(_sync_unit)
	window.closed.connect(_sync_all)
	equip_button.disabled = _units.is_empty()
	equip_button.pressed.connect(func() -> void: _open_unit(_units[0]))
	continue_button.pressed.connect(_on_continue)

func _make_card(item: Item, added: bool) -> PanelContainer:
	var panel := RunUi.card()
	var box := VBoxContainer.new()
	panel.add_child(box)
	RunUi.label(box, item.display_name, RunUi.RARITY_COLORS[int(item.get_meta("rarity", 0))])
	RunUi.label(box, "Slot: %s" % item.kind_label(), Palette.INK_LIGHT)
	if not item.defense_summary().is_empty():
		RunUi.label(box, item.defense_summary(), Palette.INK_LIGHT)
	if item.ability != null and not item.ability.damage_dice.is_empty():
		RunUi.label(box, "Damage: %s%+d" % [item.ability.damage_dice, item.ability.damage_bonus], Palette.INK_LIGHT)
	var reqs := item.requirement_summary()
	RunUi.label(box, "Requires: %s" % (reqs if not reqs.is_empty() else "nothing"), Palette.INK_LIGHT)
	if added:
		RunUi.label(box, "Added to bag", Palette.ACCENT)
	else:
		RunUi.label(box, "Bag full - Discard", Palette.HP_RED)
	return panel

## The window edits Units, so each party member gets one with its HP and worn gear.
func _make_unit(member) -> Unit:
	var u := Unit.new(member.unit_data, Unit.Side.PLAYER, Vector2i.ZERO)
	for slot in Equipment.ALL_SLOTS:
		u.equipment.unequip(slot)
	for slot in Equipment.ALL_SLOTS:
		var worn: Item = member.equipment.get_item(slot)
		if worn != null:
			u.equipment.try_equip(worn, slot)
	u.hp = clampi(member.current_hp, 1, u.max_hp)
	return u

func _open_unit(u: Unit) -> void:
	window.open(u, RunState.bag, true)

## Copies what a Unit wears back into its RunState party member.
func _sync_unit(u: Unit) -> void:
	var i := _units.find(u)
	if i < 0:
		return
	var worn := Equipment.new()
	for slot in Equipment.ALL_SLOTS:
		var item: Item = u.equipment.get_item(slot)
		if item != null:
			worn.try_equip(item, slot)
	RunState.party[i].equipment = worn

func _sync_all() -> void:
	for u in _units:
		_sync_unit(u)

func _on_continue() -> void:
	_sync_all()
	RunFlow.go("victory" if _is_boss else "map")
