class_name TargetPreviewPanel
extends PanelContainer
## Shown above the hover panel (bottom right) only while targeting. Fire Emblem-style battle forecast:
## one card per target (attacker | labels | defender), or a plain message when there is no target.
## Tier and Lock onto live on the action bar, so this panel only reports what the aim would do.

enum Status { OUT_OF_RANGE, NO_TILE, NO_TARGET, NO_UNIT, CHARGE_LOCK, TARGETS }

const Ability = preload("res://scripts/battle/ability.gd")
const ForecastCard = preload("res://ui/forecast_card.gd")
const CARD_SCENE: PackedScene = preload("res://ui/forecast_card.tscn")

## Cards shown at once; extra targets are summarised as "+N more".
@export var max_cards: int = 4
## The panel never grows taller than this; longer content scrolls.
@export var max_height: float = 400.0

@onready var _scroll: ScrollContainer = %Scroll
@onready var _rows: VBoxContainer = %Rows
@onready var _title: Label = %Title
@onready var _roll_type: Label = %RollType
@onready var _status: Label = %Status
@onready var _cards: VBoxContainer = %Cards
@onready var _warning: Label = %Warning
@onready var _charge_note: Label = %ChargeNote

func _ready() -> void:
	_rows.minimum_size_changed.connect(_fit_height)

## rows are AttackForecast.build() dictionaries (TARGETS, or CHARGE_LOCK as a "whoever is there
## now" estimate). dc: the caster's spell DC, shown for SAVE abilities.
## lock_on_unit: the Tile / Unit choice (picked on the action bar), only used for charged abilities.
func show_preview(ability: Ability, status: Status, rows: Array[Dictionary], dc: int, lock_on_unit: bool, tier: int = 1) -> void:
	visible = true
	var cost := ability.ap_cost_for_tier(tier)
	var max_tier: Variant = ability.get("max_tier")
	var is_tiered: bool = max_tier != null and int(max_tier) > 1
	_title.text = ("%s - Tier %d - %s AP" % [ability.display_name, tier, _ap(cost)]) if is_tiered else ("%s - %s AP" % [ability.display_name, _ap(cost)])
	_roll_type.text = _roll_text(ability, dc)
	_status.text = _status_text(ability, status)

	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var friendly: Array[String] = []
	for i in rows.size():
		var row: Dictionary = rows[i]
		if i < max_cards:
			var card := CARD_SCENE.instantiate() as ForecastCard
			_cards.add_child(card)
			card.show_forecast(row)
		if row["attacker"].side == row["defender"].side:
			friendly.append(row["defender"].unit_name)
	if rows.size() > max_cards:
		_status.text = "+%d more targets" % (rows.size() - max_cards)
	_status.visible = _status.text != ""

	_warning.text = ("Friendly fire: %s" % ", ".join(friendly)) if not friendly.is_empty() else ""
	_warning.visible = not friendly.is_empty()

	_charge_note.text = ""
	if status == Status.CHARGE_LOCK:
		var lock := "Follows this unit" if lock_on_unit else "Locks this tile"
		_charge_note.text = "%s, resolves in %d ticks" % [lock, ability.charge_ticks()]
	_charge_note.visible = _charge_note.text != ""

## 1.5 -> "1.5", 3.0 -> "3".
static func _ap(v: float) -> String:
	return String.num(v, 1).trim_suffix(".0")

func hide_preview() -> void:
	visible = false

func _roll_text(ability: Ability, dc: int) -> String:
	match ability.roll:
		Ability.Roll.ATTACK:
			return "Attack roll"
		Ability.Roll.SAVE:
			return "%s save, DC %d" % [Ability.Stat.keys()[ability.save_stat], dc]
	return "No roll (automatic)"

func _status_text(ability: Ability, status: Status) -> String:
	match status:
		Status.OUT_OF_RANGE:
			return "Hover a target within range %d." % ability.range_tiles
		Status.NO_TILE:
			return "No tile here."
		Status.NO_TARGET:
			return "No valid target here."
		Status.NO_UNIT:
			return "No unit on this tile to lock onto."
	return ""

## Grow with the content up to max_height, then scroll.
func _fit_height() -> void:
	_scroll.custom_minimum_size.y = minf(_rows.get_combined_minimum_size().y, max_height)
