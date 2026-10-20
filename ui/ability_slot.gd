class_name AbilitySlot
extends Button
## One square on the action bar. Placeholder icon text: "AA" = weapon action, "SS" = spell action.
## A slot with no ability is an empty, disabled square so the grid keeps its shape.

const Ability = preload("res://scripts/battle/ability.gd")
const AbilityText = preload("res://ui/ability_text.gd")

const Palette = preload("res://ui/theme/gbc_palette.gd")

const SLOT_SIZE := Vector2(48, 48)
## Thin outline normally; thick outline plus a ▶ cursor when hovered or being aimed.
const THIN := 2
const THICK := 4

var ability: Ability = null
var _border: Color = Palette.INK_LIGHT
var _aiming: bool = false
var _cursor: Label = null

func setup(a: Ability) -> void:
	ability = a
	custom_minimum_size = SLOT_SIZE
	focus_mode = Control.FOCUS_NONE
	_ensure_cursor()
	if a == null:
		text = ""
		disabled = true
		_border = Palette.INK_LIGHT
	else:
		var spell := AbilityText.is_spell(a)
		text = "SS" if spell else "AA"
		_border = Palette.ACCENT if spell else Palette.INK
	_apply_styles(false)

## usable: the unit can pay for it right now. aiming: this is the ability being targeted.
func set_state(usable: bool, aiming: bool) -> void:
	if ability == null:
		return
	disabled = not usable
	_apply_styles(aiming)

func _apply_styles(aiming: bool) -> void:
	_aiming = aiming
	add_theme_stylebox_override("normal", _box(Palette.PANEL, _border, THICK if aiming else THIN))
	add_theme_stylebox_override("hover", _box(Palette.PANEL, _border, THICK))
	add_theme_stylebox_override("pressed", _box(Palette.INK, Palette.INK, THICK))
	add_theme_stylebox_override("hover_pressed", _box(Palette.INK, Palette.INK, THICK))
	add_theme_stylebox_override("disabled", _box(Palette.PANEL, Palette.INK_LIGHT, THIN))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_color_override("font_color", _border if _border != Palette.INK_LIGHT else Palette.INK_LIGHT)
	add_theme_color_override("font_hover_color", Palette.INK)
	add_theme_color_override("font_pressed_color", Palette.PANEL)
	add_theme_color_override("font_hover_pressed_color", Palette.PANEL)
	add_theme_color_override("font_disabled_color", Palette.INK_LIGHT)
	_update_cursor()

func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	# Hard pixel corners: no radius. Same content margins in every state so text never shifts; the
	# extra top margin drops the label below the ▶ cursor that sits in the top-left corner.
	b.content_margin_left = 6
	b.content_margin_right = 6
	b.content_margin_top = 10
	b.content_margin_bottom = 2
	return b

# --- ▶ cursor -----------------------------------------------------------------

func _ensure_cursor() -> void:
	if _cursor != null:
		return
	_cursor = Label.new()
	_cursor.text = "\u25b6"
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.position = Vector2(6, 4)
	_cursor.add_theme_color_override("font_color", Palette.INK)
	_cursor.visible = false
	add_child(_cursor)
	mouse_entered.connect(_update_cursor)
	mouse_exited.connect(_update_cursor)

func _update_cursor() -> void:
	if _cursor == null:
		return
	_cursor.visible = ability != null and not disabled and (_aiming or is_hovered())
