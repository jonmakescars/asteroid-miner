class_name ShipLostOverlay
extends Control
## Full-screen overlay for a lost ship: plays the burning-up animation (frames in res://art/burnup, drawn from the
## sprite samples: a craft that glows, then breaks up in a fireball) and then shows a "Ship lost" popup.
## Tap anywhere to skip the animation. Without animation (burn = false) only the popup is shown.
## Call play(text, burn); the overlay frees itself when the popup is closed.

signal finished

const FRAME_PATH := "res://art/burnup/lander_%03d.png"
const FRAME_COUNT := 120
const FPS := 12.0

var _picture: TextureRect
var _hint: Label
var _dialog: AcceptDialog
var _text := ""
var _time := 0.0
var _frame := -1
var _playing := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05, 0.92)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_picture = TextureRect.new()
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	_hint = Label.new()
	_hint.text = "Tap to skip"
	_hint.modulate = Color(1, 1, 1, 0.5)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y -= 40.0
	add_child(_hint)
	_dialog = AcceptDialog.new()
	_dialog.title = "Ship lost"
	_dialog.dialog_autowrap = true
	_dialog.confirmed.connect(_close)
	_dialog.canceled.connect(_close)
	add_child(_dialog)


func play(text: String, burn: bool) -> void:
	_text = text
	if burn and ResourceLoader.exists(FRAME_PATH % 0):
		_playing = true
		_time = 0.0
		_show_frame(0)
	else:
		_show_popup()


func _process(delta: float) -> void:
	if not _playing:
		return
	_time += delta
	var index := int(_time * FPS)
	if index >= FRAME_COUNT:
		_show_popup()
	else:
		_show_frame(index)


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if _playing and pressed:
		_show_popup()


func _show_frame(index: int) -> void:
	if index == _frame:
		return
	_frame = index
	_picture.texture = load(FRAME_PATH % index) as Texture2D


func _show_popup() -> void:
	_playing = false
	_picture.texture = null
	_hint.visible = false
	_dialog.dialog_text = _text
	var width := int(minf(480.0, get_viewport_rect().size.x - 40.0))
	_dialog.min_size = Vector2i(width, 0)
	_dialog.size = Vector2i(width, 0)
	_dialog.popup_centered(Vector2i(width, 0))


func _close() -> void:
	finished.emit()
	queue_free()
