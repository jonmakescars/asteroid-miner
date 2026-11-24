extends Control
## Settings screen, opened from the menu. Every row writes its value to UserSettings at once.
## Rows are made by the _add_* helpers (section heading, slider, check box, drop-down list).

const MOBILE_UI_SCALE := 2.0
const MENU_SCENE := "res://menu.tscn"
const NOTE_COLOUR := Color(0.6, 0.65, 0.75)

var _refreshers: Array = []   # one Callable per row: shows the current value again (after a reset)
var _change_listener: Callable


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = MOBILE_UI_SCALE
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	UserSettings.apply_text_scale(self)
	# The text size changes at once while the sliders are moved (the headings and notes follow when the screen is opened again).
	_change_listener = _on_setting_changed
	UserSettings.on_changed(_change_listener)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", UserSettings.text_px(28))
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 14)
	scroll.add_child(rows)

	_add_section(rows, "Background")
	_add_slider(rows, "milkyway_brightness", "Milky Way brightness", 0.0, 1.0, 0.05)
	_add_slider(rows, "milkyway_black_level", "Milky Way haze cut", 0.0, 0.3, 0.01,
			"Raises the black level of the Milky Way image: more removes the grey haze, but also the faint outer parts of the band.")
	_add_slider(rows, "star_brightness", "Star brightness", 0.0, 1.0, 0.05)
	_add_slider(rows, "parallax_strength", "Parallax strength", 0.0, 1.0, 0.05,
			"How far the stars follow the movement of the map and slightly its zoom. 0 keeps the background fixed.")
	_add_slider(rows, "pan_parallax", "Background movement when panning", 0.0, 1.0, 0.05,
			"How much the sky follows dragging the map. It also depends on the zoom: none when zoomed out as far as the view of the body goes, full when zoomed in as far as possible. 0 = never.")
	_add_section(rows, "Text size")
	_add_slider(rows, "text_scale", "Menu and panel text", 0.7, 2.0, 0.05,
			"The menus, the panels and the ship design screen; this screen follows at once.")
	_add_slider(rows, "map_label_scale", "Map labels", 0.7, 2.0, 0.05,
			"Body names, the ship name and the numbers in the top bar.")
	_add_section(rows, "Orbit lines")
	_add_slider(rows, "line_brightness", "Brightness", 0.25, 2.0, 0.05)
	_add_slider(rows, "line_width", "Thickness", 0.5, 3.0, 0.1)
	_add_section(rows, "Effects")
	_add_slider(rows, "effects_intensity", "Plasma, hull glow and engine flame", 0.0, 1.0, 0.05,
			"0 switches them off, 1 is full strength.")
	_add_section(rows, "Colours")
	_add_check(rows, "colour_blind", "Colour-blind-friendly colours",
			"Replaces the orange and red of warnings and the green and blue of the ship orbit and the planned course.")
	_add_section(rows, "Labels")
	_add_check(rows, "show_body_names", "Show body names")
	_add_check(rows, "show_moon_orbits", "Show the orbits of moons")
	_add_check(rows, "show_tiny_rings", "Show the rings round tiny bodies")
	_add_section(rows, "Behaviour")
	_add_check(rows, "animations", "Animations",
			"Crashes, launches and similar events. Only the burn-up animation exists so far; when it is off only the message is shown.")
	_add_check(rows, "ship_sprites", "Ship sprites",
			"When off, ships are always an icon on the map, even when zoomed in.")
	_add_section(rows, "Display")
	_add_choice(rows, "orientation", "Screen orientation", [["auto", "Automatic"], ["portrait", "Portrait only"], ["landscape", "Landscape only"]],
			"Phones and tablets only.")
	_add_choice(rows, "frame_cap", "Frame rate limit", [[30.0, "30 fps"], [60.0, "60 fps"]])
	_add_check(rows, "lighting_shader", "Lighting shader",
			"When off, the bodies and the ship are drawn flat, without light and shadow (a fallback). Takes effect when the map is opened again.")
	_add_section(rows, "Units")
	_add_choice(rows, "units", "Units", [["metric", "Metric"], ["imperial", "Imperial"]],
			"Imperial: miles, feet, pounds and US tons, also in the input boxes. Heat (MJ, MW) and g stay as they are. Takes effect when the map or the ship design screen is opened again.")

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var reset_button := Button.new()
	reset_button.text = "Reset to defaults"
	reset_button.custom_minimum_size = Vector2(200, 48)
	reset_button.pressed.connect(_on_reset)
	buttons.add_child(reset_button)
	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(160, 48)
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	buttons.add_child(back_button)


func _exit_tree() -> void:
	UserSettings.remove_listener(_change_listener)


func _on_setting_changed(key: String) -> void:
	if key == "text_scale" or key == "":
		UserSettings.apply_text_scale(self)
	if key == "orientation" or key == "frame_cap" or key == "":
		UserSettings.apply_display()


func _add_section(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UserSettings.text_px(20))
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	parent.add_child(label)


## A grey line of explanation under a row.
func _add_note(block: Control, note: String) -> void:
	if note == "":
		return
	var note_label := Label.new()
	note_label.text = note
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.add_theme_font_size_override("font_size", UserSettings.text_px(14))
	note_label.add_theme_color_override("font_color", NOTE_COLOUR)
	block.add_child(note_label)


## A slider with its number next to it (so that values found in play can become the defaults).
func _add_slider(parent: Control, key: String, label_text: String, low: float, high: float, step: float, note := "") -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	parent.add_child(block)
	var label := Label.new()
	label.text = label_text
	block.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	block.add_child(row)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(160, 32)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	var show_current := func() -> void:
		var current := UserSettings.number(key)
		slider.set_value_no_signal(current)
		value_label.text = "%.2f" % current
	show_current.call()
	_refreshers.append(show_current)
	slider.value_changed.connect(func(value: float) -> void:
		var snapped_value := snappedf(value, step)
		UserSettings.set_value(key, snapped_value)
		value_label.text = "%.2f" % snapped_value)
	_add_note(block, note)


func _add_check(parent: Control, key: String, label_text: String, note := "") -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	parent.add_child(block)
	var check := CheckBox.new()
	check.text = label_text
	block.add_child(check)
	var show_current := func() -> void:
		check.set_pressed_no_signal(UserSettings.flag(key))
	show_current.call()
	_refreshers.append(show_current)
	check.toggled.connect(func(pressed: bool) -> void: UserSettings.set_value(key, pressed))
	_add_note(block, note)


## A row with a drop-down list. options: [[saved value, shown text], ...]; note: a small grey line under the row (or "").
func _add_choice(parent: Control, key: String, label_text: String, options: Array, note := "") -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	parent.add_child(block)
	var row := HBoxContainer.new()
	block.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(200, 44)
	for option: Array in options:
		picker.add_item(str(option[1]))
	row.add_child(picker)
	var show_current := func() -> void:
		var current: Variant = UserSettings.get_value(key)
		for i in options.size():
			if options[i][0] == current:
				picker.select(i)
	show_current.call()
	_refreshers.append(show_current)
	picker.item_selected.connect(func(index: int) -> void: UserSettings.set_value(key, options[index][0]))
	_add_note(block, note)


func _on_reset() -> void:
	UserSettings.reset_all()
	for refresh: Callable in _refreshers:
		refresh.call()
