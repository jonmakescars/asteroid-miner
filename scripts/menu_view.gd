extends Control
## Start menu: opens the prototype screens.

const MOBILE_UI_SCALE := 2.0
const ENTRIES := [
	["Orbit map", "res://main.tscn"],
	["Ship design", "res://ship_design.tscn"],
]


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = MOBILE_UI_SCALE
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	centre.add_child(box)

	var title := Label.new()
	title.text = "Space Logistics Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Prototype"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	box.add_child(subtitle)

	for entry in ENTRIES:
		var path: String = entry[1]
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(320, 56)
		button.pressed.connect(func() -> void: get_tree().change_scene_to_file(path))
		box.add_child(button)

	if not OS.has_feature("mobile"):
		var quit_button := Button.new()
		quit_button.text = "Quit"
		quit_button.custom_minimum_size = Vector2(320, 56)
		quit_button.pressed.connect(func() -> void: get_tree().quit())
		box.add_child(quit_button)
