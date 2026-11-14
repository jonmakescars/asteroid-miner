class_name TopBar
extends PanelContainer
## The bar along the top edge of the orbital screens: time controls, a screen-specific view button,
## navigation to the other screens, and the game date with the pause / time flow status.
## A screen can add its own rows below with add_row() / box.
## Time itself is advanced by the screen (GameState.advance); the bar only changes the controls
## and shows the state. Call refresh() every frame.

signal navigate(scene_path: String)
signal view_pressed

const SCREENS := [
	["Map", "res://main.tscn"],
	["Ship design", "res://ship_design.tscn"],
	["Menu", "res://menu.tscn"],
]

const MAX_HEIGHT_PORTRAIT := 0.7    # share of the screen height the bar may use before it scrolls
const MAX_HEIGHT_LANDSCAPE := 0.55

var scroll: ScrollContainer
var box: VBoxContainer
var pause_button: Button
var view_button: Button
var design_button: Button
var date_label: Label
var status_label: Label
var ship_label: Label
var orbit_label: Label


## current_scene is the path of the screen the bar sits on (its own button is left out).
func setup(current_scene: String, view_text: String) -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Everything sits in a scroll area that is limited in height, so that on a low (landscape) screen the
	# bar does not cover the whole map: drag the content or use the scroll bar.
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.get_v_scroll_bar().custom_minimum_size.x = 16
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var row := HFlowContainer.new()
	box.add_child(row)
	_add_button(row, "Slower", func() -> void: GameState.change_warp(-1))
	pause_button = _add_button(row, "Pause", func() -> void: GameState.toggle_pause())
	_add_button(row, "Faster", func() -> void: GameState.change_warp(1))
	if view_text != "":   # a screen without a view button passes ""
		view_button = _add_button(row, view_text, func() -> void: view_pressed.emit())
	for screen in SCREENS:
		var path: String = screen[1]
		if path != current_scene:
			var button := _add_button(row, screen[0], func() -> void: navigate.emit(path))
			if path == "res://ship_design.tscn":
				design_button = button
				button.visible = false

	var time_row := HBoxContainer.new()
	box.add_child(time_row)
	date_label = Label.new()
	time_row.add_child(date_label)
	status_label = Label.new()
	time_row.add_child(status_label)
	ship_label = Label.new()
	time_row.add_child(ship_label)
	orbit_label = Label.new()
	orbit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(orbit_label)


## Adds a row of controls below the time row (before anything a screen adds later).
func add_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	box.add_child(row)
	return row


## The Ship design button is only offered where the ship is at a shipyard.
func set_design_visible(value: bool) -> void:
	if design_button != null:
		design_button.visible = value


func set_view_text(text: String) -> void:
	if view_button != null:
		view_button.text = text


func refresh() -> void:
	var screen := get_viewport_rect().size
	var limit := screen.y * (MAX_HEIGHT_LANDSCAPE if screen.x > screen.y else MAX_HEIGHT_PORTRAIT)
	var wanted := minf(box.get_combined_minimum_size().y, limit)
	if absf(scroll.custom_minimum_size.y - wanted) > 1.0:
		scroll.custom_minimum_size.y = wanted
	pause_button.text = "Resume" if GameState.paused else "Pause"
	date_label.text = GameState.date_text(GameState.time_jd)
	ship_label.text = "   Ship: %s" % GameState.ship_name
	orbit_label.text = GameState.orbit_status_text()
	if GameState.paused:
		status_label.text = "   Paused"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		status_label.remove_theme_color_override("font_color")
		status_label.text = "" if GameState.warp_index == 0 else "   Warp: %s" % GameState.WARP_LABELS[GameState.warp_index]


static func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
