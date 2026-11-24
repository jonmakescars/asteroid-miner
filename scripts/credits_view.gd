extends Control
## Credits screen, opened from the menu. Each credit is one entry in CREDITS (heading and text); add new ones there.

const MOBILE_UI_SCALE := 2.0
const MENU_SCENE := "res://menu.tscn"
const NOTE_COLOUR := Color(0.6, 0.65, 0.75)
const CREDITS: Array = [
	{
		"heading": "NASA",
		"text": "The star background (the Milky Way and the stars behind the map) is made from the Deep Star Maps of NASA's Scientific Visualization Studio (NASA/Goddard Space Flight Center Scientific Visualization Studio, Deep Star Maps 2020). The images are in the public domain. NASA does not endorse this game.",
	},
]


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = MOBILE_UI_SCALE
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	UserSettings.apply_text_scale(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Credits"
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
	for credit: Dictionary in CREDITS:
		var heading := Label.new()
		heading.text = str(credit["heading"])
		heading.add_theme_font_size_override("font_size", UserSettings.text_px(20))
		rows.add_child(heading)
		var text := Label.new()
		text.text = str(credit["text"])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_color_override("font_color", NOTE_COLOUR)
		rows.add_child(text)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(160, 48)
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	column.add_child(back_button)
