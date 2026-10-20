extends Button
## One square of the bottom hotbar. Two kinds:
##   ACTION  an ability (weapon action or spell). Click picks it. Greyed when the unit can't pay for it.
##   GEAR    a worn item (hands, armor, rings, amulet). Click opens the equipment window.
## An ACTION slot given an empty dictionary is a blank cell, so the grid keeps its shape.
## Hovering shows a tooltip card (tooltip_card.gd) built from the data's "tip".
## Display only: the Hotbar decides what a click means.

signal picked(key: int)

enum Kind { ACTION, GEAR }

const Palette = preload("res://ui/theme/gbc_palette.gd")
const TooltipCard = preload("res://ui/hud/tooltip_card.gd")
const HudStyle = preload("res://ui/hud/hud_style.gd")

const THIN := 2
const THICK := 4

var kind: int = Kind.ACTION
## Ability id (index into unit.abilities) for ACTION, Equipment.Slot for GEAR. -1 for a blank cell.
var key := -1
## Border colour of a usable slot (weapon actions use the ink colour, spells the accent colour).
var accent: Color = Palette.INK

## AP this ability spends (0 for blank / gear cells). The hotbar previews it on the AP bar.
var ap_cost := 0.0
## AP cost per tier, index 0 = Base. One entry for anything without tiers.
var tier_costs: Array[float] = []

var _tip := {}
var _cooldown := 0
var _blank := true
var _usable := true
var _has_item := true
var _aiming := false
var _aim_tier := 1
var _cursor := false
var _locked := false
var _icon: TextureRect
var _label: Label
var _cost: Label

func setup(p_kind: int, p_size: Vector2) -> void:
	kind = p_kind
	custom_minimum_size = p_size
	focus_mode = Control.FOCUS_NONE
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	add_child(_icon)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)
	_cost = Label.new()
	_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cost.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cost.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cost.offset_right = -3
	_cost.offset_bottom = -1
	add_child(_cost)
	pressed.connect(_on_pressed)
	set_data({})

## Fills the slot. {} = a blank cell.
func set_data(d: Dictionary) -> void:
	_blank = d.is_empty()
	if _blank:
		key = -1
		ap_cost = 0.0
		tier_costs = []
		_tip = {}
		_icon.texture = null
		_label.text = ""
		_cost.text = ""
		_cooldown = 0
		_usable = false
		_has_item = false
		tooltip_text = ""
	else:
		key = int(d["id"]) if kind == Kind.ACTION else int(d["slot"])
		_tip = d.get("tip", {})
		ap_cost = float(d.get("ap_cost", 0.0))
		tier_costs.assign(d.get("tier_costs", [ap_cost]))
		var tex: Texture2D = d.get("icon")
		_icon.texture = tex
		_label.text = "" if tex != null else String(d.get("short", ""))
		_cooldown = int(d.get("cooldown", 0))
		_cost.text = _cooldown_text()   # the AP cost is not drawn on the slot (tooltip and AP bar preview show it); turns of cooldown left are
		_usable = bool(d.get("usable", true))
		_has_item = bool(d.get("has_item", true))
		# Any non-empty text turns the tooltip on; _make_custom_tooltip draws the real card.
		tooltip_text = String(_tip.get("title", "")) if not _tip.is_empty() else ""
	_apply_style()

## Turns of cooldown left, drawn in the corner; empty when ready.
func _cooldown_text() -> String:
	return str(_cooldown) if _cooldown > 0 else ""

func is_blank() -> bool:
	return _blank

func is_usable() -> bool:
	return not _blank and _usable

## Highest tier this ability can be cast at (1 = no tiers).
func max_tier() -> int:
	return maxi(tier_costs.size(), 1)

## AP cost at `tier` (1 = Base), clamped to the tiers the ability has.
func cost_for_tier(tier: int) -> float:
	if tier_costs.is_empty():
		return ap_cost
	return tier_costs[clampi(tier, 1, tier_costs.size()) - 1]

## This is the ability being aimed right now, at `tier`. The slot is drawn inverted; the tier is NOT written on it
## (the forecast box above the HUD names the spell and its tier while it is selected).
func set_aiming(value: bool, tier := 1) -> void:
	var changed := _aiming != value
	_aiming = value
	_aim_tier = tier if value else 1
	_cost.text = _cooldown_text()
	if changed:
		_apply_style()

## The bar is not accepting this slot right now (text playing, window open, aiming, confirming). Drawn greyed out like an
## unaffordable ability, with no hover outline. Tooltips still work.
func set_locked(value: bool) -> void:
	if _locked != value:
		_locked = value
		_apply_style()

## The keyboard cursor is on this slot.
func set_cursor(value: bool) -> void:
	if _cursor != value:
		_cursor = value
		_apply_style()

func _make_custom_tooltip(_for_text: String) -> Object:
	if _tip.is_empty():
		return null
	return TooltipCard.build(_tip)

func _on_pressed() -> void:
	if _blank:
		return
	if kind == Kind.ACTION and not _usable:
		return
	picked.emit(key)

func _apply_style() -> void:
	if _icon == null:
		return
	var live := not _blank
	var dim := live and (_locked or (kind == Kind.ACTION and not _usable) or (kind == Kind.GEAR and not _has_item))
	var border: Color = accent if live and not dim else Palette.INK_LIGHT
	var text_color: Color = Palette.INK_LIGHT if dim else Palette.INK
	var bg: Color = Palette.PANEL if live else Palette.BG
	var width := THIN
	if live and _cursor:
		border = Palette.INK
		width = THICK
	if live and _aiming:
		border = Palette.INK
		bg = Palette.INK
		text_color = Palette.PANEL
		width = THICK
	var normal := HudStyle.box(bg, border, 1 if not live else width)
	var hover := HudStyle.box(bg, Palette.INK, THICK) if live and not _locked else normal
	var pressed := HudStyle.box(Palette.INK, Palette.INK, THICK) if live and not _locked else normal
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("hover_pressed", pressed if _locked else HudStyle.box(Palette.INK, Palette.INK, THICK))
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_label.add_theme_color_override("font_color", text_color)
	_cost.add_theme_color_override("font_color", text_color)
	_icon.modulate = Color(1, 1, 1, 0.45) if dim else Color.WHITE
