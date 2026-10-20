class_name CombatLog
extends PanelContainer
## Scrolling log above the current-unit panel (bottom left), styled as a Game Boy Color dialog box:
## the newest line types out one character at a time and a blinking ▼ waits at the bottom right
## once it is finished. Newest line at the bottom; the view is sized for ~8 lines and older lines
## stay reachable by scrolling.

## Lines kept in memory.
@export var history_lines: int = 100
## Typewriter speed for the newest line. 0 shows every line instantly.
@export var chars_per_second: float = 60.0
## Seconds per blink step of the ▼ arrow.
@export var arrow_blink_seconds: float = 0.5

@onready var _log: RichTextLabel = %Log

var _lines: Array[String] = []
var _type_from: int = 0
var _progress: float = 0.0
var _typing: bool = false
var _arrow: Label = null
var _blink: Timer = null

func _ready() -> void:
	set_process(false)
	_arrow = Label.new()
	_arrow.text = "\u25bc"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PanelContainer lays every child over its content area; these flags park the arrow at the bottom right.
	_arrow.size_flags_horizontal = Control.SIZE_SHRINK_END
	_arrow.size_flags_vertical = Control.SIZE_SHRINK_END
	_arrow.visible = false
	add_child(_arrow)
	_blink = Timer.new()
	_blink.wait_time = arrow_blink_seconds
	_blink.autostart = true
	_blink.timeout.connect(_on_blink)
	add_child(_blink)

func add_line(text: String) -> void:
	_lines.append(text)
	while _lines.size() > history_lines:
		_lines.pop_front()
	_log.clear()
	var last := _lines.size() - 1
	for i in _lines.size():
		if i > 0:
			_log.newline()
		if i == last:
			_type_from = _log.get_total_character_count()
		_log.add_text(_lines[i])
	_start_typing()

## Skips the typewriter so the whole newest line is visible.
func finish_typing() -> void:
	_typing = false
	_log.visible_characters = -1
	set_process(false)
	_update_arrow(true)

func _start_typing() -> void:
	if chars_per_second <= 0.0 or not is_inside_tree():
		finish_typing()
		return
	_typing = true
	_progress = 0.0
	_log.visible_characters = _type_from
	_update_arrow(false)
	set_process(true)

func _process(delta: float) -> void:
	_progress += delta * chars_per_second
	var shown := _type_from + int(_progress)
	if shown >= _log.get_total_character_count():
		finish_typing()
	else:
		_log.visible_characters = shown

func _on_blink() -> void:
	if _arrow != null and not _typing and not _lines.is_empty():
		_arrow.visible = not _arrow.visible

func _update_arrow(visible_now: bool) -> void:
	if _arrow != null:
		_arrow.visible = visible_now and not _lines.is_empty()
		if _blink != null:
			_blink.start()
