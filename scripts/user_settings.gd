class_name UserSettings
extends RefCounted
## The player's settings (the settings screen): one file, user://user_settings.json. Every change is saved at once and
## the listeners (on_changed) are told, so the screens can apply it immediately.
## (data/settings.json is something else: the starting conditions of a new game.)
## To add a setting: give it a default here and a row in settings_view.gd.

const PATH := "user://user_settings.json"
const DEFAULTS := {
	"units": "metric",   # "metric" or "imperial" (shown by the screens from step 12c on)
	"milkyway_brightness": 1.0,   # the star background itself comes in step 12d
	"star_brightness": 1.0,
	"parallax_strength": 0.5,
	"pan_parallax": 1.0,           # how much the sky follows the dragging of the map (on top of the parallax strength)
	"milkyway_black_level": 0.20,  # brightness of the Milky Way image that counts as black (cuts the grey haze)
	"text_scale": 1.0,        # menu and panel text
	"map_label_scale": 1.0,   # body names and the numbers in the top bar
	"line_brightness": 1.0,   # orbit lines and planned courses
	"line_width": 1.0,
	"effects_intensity": 1.0,   # plasma, hull glow and engine flame
	"colour_blind": false,
	"show_body_names": true,
	"show_moon_orbits": true,
	"show_tiny_rings": true,   # the rings round bodies that are too small to see
	"animations": true,        # the burn-up animation (more come later)
	"ship_sprites": true,      # false: ships are always an icon on the map
	"orientation": "auto",     # "auto", "portrait" or "landscape" (phones and tablets)
	"show_frame_rate": true,   # the frame rate in the info text of the orbit map
	"frame_cap": 60.0,         # frames per second: 30.0 or 60.0
	"lighting_shader": true,   # false: bodies and ship are drawn flat, without light and shadow
}

const BASE_FONT_SIZE := 16
## Colours that change with the colour-blind palette: [normal, colour-blind friendly] (see colour()).
static var _palette := {
	"warning": [Color(1.0, 0.55, 0.3), Color(0.94, 0.89, 0.26)],
	"paused": [Color(1.0, 0.3, 0.3), Color(0.8, 0.47, 0.65)],
	"ship_orbit": [Color(0.3, 1.0, 0.4), Color(0.94, 0.89, 0.26)],
	"course": [Color(0.4, 0.9, 1.0), Color(0.34, 0.71, 0.91)],
}

static var _values: Dictionary = {}
static var _loaded := false
static var _listeners: Array = []


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_values = DEFAULTS.duplicate()
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			var saved: Dictionary = parsed
			for key: String in DEFAULTS:
				# (a saved value of the wrong type, for example after a hand edit, is ignored)
				if saved.has(key) and typeof(saved[key]) == typeof(DEFAULTS[key]):
					_values[key] = saved[key]


static func get_value(key: String) -> Variant:
	_load()
	return _values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_load()
	if _values.get(key) == value:
		return
	_values[key] = value
	_save()
	_notify(key)


## Puts every setting back to its default (key "" in the notice: everything changed).
static func reset_all() -> void:
	_load()
	_values = DEFAULTS.duplicate()
	_save()
	_notify("")


static func number(key: String) -> float:
	return float(get_value(key))


static func flag(key: String) -> bool:
	return bool(get_value(key))


## A colour of the palette (see PALETTE), in the colour-blind version when that is switched on.
static func colour(name: String) -> Color:
	var pair: Array = _palette[name]
	var index := 1 if flag("colour_blind") else 0
	return pair[index] as Color


## A font size scaled by the text size setting (menu and panel text), and by the map label setting.
static func text_px(base: int) -> int:
	return maxi(roundi(float(base) * number("text_scale")), 8)


static func map_text_px(base: int) -> int:
	return maxi(roundi(float(base) * number("map_label_scale")), 8)


## Gives a screen the text size setting: every control below it that has no font size of its own uses it.
static func apply_text_scale(root: Control) -> void:
	var theme := Theme.new()
	theme.default_font_size = text_px(BASE_FONT_SIZE)
	root.theme = theme


## Applies the display settings that belong to the whole game: the frame rate cap and (on phones and tablets) the
## screen orientation. Called when a screen opens and when one of them changes.
static func apply_display() -> void:
	Engine.max_fps = int(number("frame_cap"))
	if OS.has_feature("mobile"):
		var orientation := str(get_value("orientation"))
		if orientation == "portrait":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
		elif orientation == "landscape":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
		else:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)


static func is_imperial() -> bool:
	return get_value("units") == "imperial"


## Calls listener(key) after every change (key "" after a reset).
static func on_changed(listener: Callable) -> void:
	if not _listeners.has(listener):
		_listeners.append(listener)


static func remove_listener(listener: Callable) -> void:
	_listeners.erase(listener)


static func _notify(key: String) -> void:
	for listener: Callable in _listeners.duplicate():
		if listener.is_valid():
			listener.call(key)
		else:
			_listeners.erase(listener)


static func _save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Settings could not be saved to %s." % PATH)
		return
	file.store_string(JSON.stringify(_values, "\t"))
