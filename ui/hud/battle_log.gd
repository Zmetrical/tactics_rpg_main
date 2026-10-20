extends PanelContainer
## Pokemon-style dialog box for the bottom-center slot: 2-3 visible lines, typewriter text, and a
## blinking ▼ while a finished line waits to be advanced.
##
## Lines are queued with push_line(). Each line types out, waits (a press advances at once; with
## wait_for_input off it also advances by itself after auto_advance_seconds), then the next line
## starts. The newest lines stay on the page; the page clears when the queue runs dry and
## `finished` fires exactly once per burst of lines. is_busy() is true from the first push until then.

signal finished

const ARROW := "\u25bc"
## Visible lines are set by the box height in the scene (3 lines of the 16 px font plus the frame).
@export var chars_per_second := 60.0
## true = every line waits for a press (strict Pokemon). false = lines advance on their own.
@export var wait_for_input := false
@export var auto_advance_seconds := 0.7
## true = the LAST line of a burst waits for a press even when the lines before it advance by themselves, so the
## box never closes on its own (a player's attack: the HUD only comes back when the player says so).
@export var hold_last := false
@export var arrow_blink_seconds := 0.35

@onready var _text: RichTextLabel = %Text
@onready var _arrow: Label = %Arrow

var _queue: Array[String] = []
var _page: Array[String] = []
var _type_from := 0
var _progress := 0.0
var _typing := false
var _waiting := false
var _wait_left := 0.0
var _blink := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.text = ARROW
	_arrow.visible = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.scroll_following = true
	_text.get_v_scroll_bar().modulate.a = 0.0
	_text.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func push_line(text: String) -> void:
	_queue.append(text)
	if not _typing and not _waiting:
		_start_next()

func is_busy() -> bool:
	return _typing or _waiting or not _queue.is_empty()

## A press while the box is showing text. Finishes typing, or advances a waiting line.
## Returns true when the press was used.
func advance_input() -> bool:
	if _typing:
		_finish_typing()
		return true
	if _waiting:
		_advance()
		return true
	return false

## True while the box sits on a finished line waiting for a press (not just blinking its arrow).
func is_holding() -> bool:
	return _waiting and not _auto_advances()

func arrow_visible() -> bool:
	return _arrow.visible

func visible_text() -> String:
	return _text.get_parsed_text()

func _start_next() -> void:
	_page.append(_queue.pop_front())
	while _page.size() > 3:
		_page.pop_front()
	_text.clear()
	for i in _page.size():
		if i > 0:
			_text.newline()
		if i == _page.size() - 1:
			_type_from = _text.get_total_character_count()
		_text.add_text(_page[i])
	_arrow.visible = false
	_progress = 0.0
	if chars_per_second <= 0.0:
		_finish_typing()
		return
	_typing = true
	_text.visible_characters = _type_from
	set_process(true)

func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	_waiting = true
	_wait_left = auto_advance_seconds
	_blink = 0.0
	_arrow.visible = true
	set_process(true)
	if _auto_advances() and auto_advance_seconds <= 0.0:
		_advance()

## Does the line that is waiting move on by itself? Not when lines need a press, nor for the held last line.
func _auto_advances() -> bool:
	return not wait_for_input and not (hold_last and _queue.is_empty())

func _advance() -> void:
	_waiting = false
	_arrow.visible = false
	if not _queue.is_empty():
		_start_next()
		return
	_page.clear()
	_text.clear()
	set_process(false)
	finished.emit()

func _process(delta: float) -> void:
	if _typing:
		_progress += delta * chars_per_second
		var shown := _type_from + int(_progress)
		if shown >= _text.get_total_character_count():
			_finish_typing()
		else:
			_text.visible_characters = shown
	elif _waiting:
		_blink += delta
		if _blink >= arrow_blink_seconds:
			_blink = 0.0
			_arrow.visible = not _arrow.visible
		if _auto_advances():
			_wait_left -= delta
			if _wait_left <= 0.0:
				_advance()
