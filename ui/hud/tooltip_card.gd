extends RefCounted
## Builds the hover tooltip for a hotbar slot from plain data (see AbilityText.tooltip and
## UnitView.hotbar). Layout, top to bottom: title, subtitle, stats, rank, then (for an ability, i.e. when there
## are stats) each text block and the tier rows, with a divider before every group, then any number of sections (a coloured marker, a heading and
## bullet lines), then footer lines.
##
## An ability that uses [Keyword]s also gets one small card per keyword, stacked to the right of the main
## card, so a rule shared by many abilities is written once (scripts/spells/keywords.gd).
##
## tip = {
##   "title": String, "subtitle": String, "stats": String, "rank": String, "body": String,
##   "blocks": Array of Array[String]  groups of bullets above the tiers, a divider before each group.
##   "rules": Array[String]            bullets below the tiers (save, what it builds).
##   "tiers": Array[String]            one line per tier, Base first. "" skips a tier.
##   "keywords": Array[String]         glossary names, drawn as their own cards.
##   "sections": [{"heading": String, "marker": Color, "lines": Array[String]}],
##   "footer": Array[String],
## }
## Every key is optional; empty text and empty sections are skipped.

const Palette = preload("res://ui/theme/gbc_palette.gd")
const UiTheme = preload("res://ui/theme/tactics_theme.tres")
const HudStyle = preload("res://ui/hud/hud_style.gd")
const Keywords = preload("res://scripts/spells/keywords.gd")

const WIDTH := 300.0
## Width the text can use: the card minus the frame's left / right content margin (10 each, see _card()).
## Every wrapping label gets this as its minimum width. Without it the labels start out near zero wide, count one
## word per line, and make the tooltip popup as tall as the screen.
const TEXT_W := WIDTH - 20.0
## A section heading sits next to a 12 px marker with an 8 px gap.
const HEADING_W := TEXT_W - 20.0
## Fixed tag columns: "T1" on a tier row, "-" on a bullet row. A 4 px gap, then the wrapping text.
const TIER_TAG_W := 36.0
const BULLET_TAG_W := 16.0
## Keyword cards beside the main card.
const KEYWORD_WIDTH := 260.0
const KEYWORD_TEXT_W := KEYWORD_WIDTH - 20.0
const CARD_GAP := 4

static func build(tip: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var card := _card(WIDTH, box)

	_add_text(box, String(tip.get("title", "")), Palette.INK, true, true)
	_add_text(box, String(tip.get("subtitle", "")), Palette.ACCENT, true, false)
	var stats := String(tip.get("stats", ""))
	_add_text(box, stats, Palette.INK_LIGHT, true, false)
	_add_text(box, String(tip.get("rank", "")), Palette.INK_LIGHT, true, false)
	var body := String(tip.get("body", ""))
	# An ability card (it has a stats line) is ruled into groups of bullets, each group behind a divider:
	# timing and aim, effect, the tiers, then the rules (save, what it builds) always last.
	var ruled := stats != ""
	if ruled:
		for group: Array in tip.get("blocks", []):
			_add_group(box, group)
	elif body != "":
		box.add_child(_gap(2))
		_add_text(box, body, Palette.INK, false, false)
	var tiers: Array = tip.get("tiers", [])
	var has_tier := false
	for t in tiers:
		has_tier = has_tier or String(t) != ""
	if has_tier:
		box.add_child(_separator())
		for i in tiers.size():
			if String(tiers[i]) != "":
				_add_row(box, "T%d" % (i + 1), Palette.ACCENT, String(tiers[i]), TIER_TAG_W)
	_add_group(box, tip.get("rules", []))
	for section: Dictionary in tip.get("sections", []):
		var lines: Array = section.get("lines", [])
		if lines.is_empty():
			continue
		box.add_child(_gap(2))
		var heading := String(section.get("heading", ""))
		if heading != "":
			var head := HBoxContainer.new()
			head.add_theme_constant_override("separation", 8)
			head.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var marker := ColorRect.new()
			marker.color = section.get("marker", Palette.INK_LIGHT)
			marker.custom_minimum_size = Vector2(12, 12)
			marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			head.add_child(marker)
			_add_text(head, heading, Palette.INK, false, false, HEADING_W)
			box.add_child(head)
		for line in lines:
			_add_text(box, "- %s" % String(line), Palette.INK, false, false)
	var footer: Array = tip.get("footer", [])
	if not footer.is_empty():
		box.add_child(_gap(2))
		for line in footer:
			_add_text(box, String(line), Palette.INK_LIGHT, false, false)

	var words: Array = tip.get("keywords", [])
	if words.is_empty():
		return card
	return _with_keywords(card, words)

## The main card with one small card per keyword stacked on its right. Both stay top-aligned.
static func _with_keywords(card: Control, words: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CARD_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", CARD_GAP)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for word in words:
		var definition := Keywords.definition(String(word))
		if definition != "":
			column.add_child(_keyword_card(String(word), definition))
	row.add_child(column)
	return row

static func _keyword_card(word: String, definition: String) -> Control:
	var box := VBoxContainer.new()
	var card := _card(KEYWORD_WIDTH, box)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_add_text(box, word.to_upper(), Palette.ACCENT, false, false, KEYWORD_TEXT_W)
	_add_text(box, definition, Palette.INK, false, false, KEYWORD_TEXT_W)
	return card

## A framed panel `width` wide with `box` inside it.
static func _card(width: float, box: VBoxContainer) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme = UiTheme
	card.add_theme_stylebox_override("panel", HudStyle.frame(10.0, 8.0))
	card.custom_minimum_size = Vector2(width, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	return card

## A divider, then one bullet row per non-empty line.
static func _add_group(parent: Control, lines: Array) -> void:
	var any := false
	for line in lines:
		any = any or String(line) != ""
	if not any:
		return
	parent.add_child(_separator())
	for line in lines:
		if String(line) != "":
			_add_row(parent, "-", Palette.INK, String(line), BULLET_TAG_W)

## A tag ("-" or "T2") in a fixed column with the text wrapping beside it, so a long line indents under itself.
static func _add_row(parent: Control, tag_text: String, tag_color: Color, text: String, tag_w: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := _add_text(row, tag_text, tag_color, false, false, tag_w)
	tag.size_flags_horizontal = Control.SIZE_FILL
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_add_text(row, text, Palette.INK, false, false, TEXT_W - tag_w - 4.0)
	parent.add_child(row)

static func _add_text(parent: Control, text: String, color: Color, centered: bool, title: bool, width: float = TEXT_W) -> Label:
	if text == "":
		return null
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if title:
		label.theme_type_variation = &"TitleLabel"
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

static func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Palette.INK_LIGHT
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

## A divider with a little air above and below it. Splits one kind of information from the next.
static func _separator() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_gap(3))
	box.add_child(_divider())
	box.add_child(_gap(3))
	return box

static func _gap(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap
