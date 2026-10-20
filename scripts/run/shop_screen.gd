extends Control
## Shop: shows the node's stock (rolled once, kept on the MapNode), buy buttons, gold. No selling.

const Item = preload("res://scripts/inventory/item.gd")
const RunMap = preload("res://scripts/run/run_map.gd")
const RunUi = preload("res://scripts/run/run_ui.gd")
const Palette = preload("res://ui/theme/gbc_palette.gd")
const ShopLogic = preload("res://scripts/run/shop_logic.gd")

const BUY_W := 110.0

@onready var gold_label: Label = $Center/Panel/Box/GoldLabel
@onready var rows: VBoxContainer = $Center/Panel/Box/Rows
@onready var leave_button: Button = $Center/Panel/Box/LeaveButton

var _stock: Array = []
var _buttons: Array[Button] = []

func _ready() -> void:
	if not RunState.active:
		RunState.new_run(randi())  # scene launched on its own
	var node := RunMap.MapNode.new()  # no map node: a throwaway shop at layer 0
	if RunState.map != null and RunState.current_node != null:
		node = RunState.map.nodes[int(RunState.current_node)]
	_stock = ShopLogic.stock_for(node, RunState.rng)
	for entry in _stock:
		rows.add_child(_make_row(entry))
	leave_button.pressed.connect(func() -> void: RunFlow.go("map"))
	_refresh()

func _make_row(entry: Dictionary) -> PanelContainer:
	var item: Item = entry.item
	var card := RunUi.card()
	var row := HBoxContainer.new()
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	RunUi.label(text, "%s  (%s)" % [item.display_name, item.kind_label()], RunUi.RARITY_COLORS[int(item.get_meta("rarity", 0))])
	RunUi.label(text, _details(item), Palette.INK_LIGHT)
	var button := Button.new()
	button.custom_minimum_size.x = BUY_W
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_on_buy.bind(entry))
	row.add_child(button)
	_buttons.append(button)
	return card

func _details(item: Item) -> String:
	var parts: Array[String] = []
	if not item.defense_summary().is_empty():
		parts.append(item.defense_summary())
	if item.ability != null and not item.ability.damage_dice.is_empty():
		parts.append("%s%+d" % [item.ability.damage_dice, item.ability.damage_bonus])
	var reqs := item.requirement_summary()
	if not reqs.is_empty():
		parts.append("Req " + reqs)
	return "  |  ".join(parts) if not parts.is_empty() else "-"

func _on_buy(entry: Dictionary) -> void:
	RunState.gold = ShopLogic.buy(entry, RunState.gold, RunState.bag)
	_refresh()

func _refresh() -> void:
	gold_label.text = "Gold: %d" % RunState.gold
	for i in _stock.size():
		var entry: Dictionary = _stock[i]
		_buttons[i].text = "Sold" if entry.sold else "Buy %dg" % entry.price
		_buttons[i].disabled = not ShopLogic.can_buy(entry, RunState.gold, RunState.bag)
