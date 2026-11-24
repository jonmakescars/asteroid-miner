extends Control
## Settings screen, opened from the menu. Every row writes its value to UserSettings at once.
## Rows are made by the _add_* helpers; more settings (visual, behaviour, display) come with the next steps.

const MOBILE_UI_SCALE := 2.0
const MENU_SCENE := "res://menu.tscn"

var _refreshers: Array = []   # one Callable per row: shows the current value again (after a reset)


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = MOBILE_UI_SCALE
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
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
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 14)
	scroll.add_child(rows)

	_add_choice(rows, "units", "Units", [["metric", "Metric"], ["imperial", "Imperial"]],
			"Saved already; the screens show imperial units from step 12c on.")

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
	if note != "":
		var note_label := Label.new()
		note_label.text = note
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.add_theme_font_size_override("font_size", 14)
		note_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		block.add_child(note_label)


func _on_reset() -> void:
	UserSettings.reset_all()
	for refresh: Callable in _refreshers:
		refresh.call()
