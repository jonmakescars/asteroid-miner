class_name UserSettings
extends RefCounted
## The player's settings (the settings screen): one file, user://user_settings.json. Every change is saved at once and
## the listeners (on_changed) are told, so the screens can apply it immediately.
## (data/settings.json is something else: the starting conditions of a new game.)
## To add a setting: give it a default here and a row in settings_view.gd.

const PATH := "user://user_settings.json"
const DEFAULTS := {
	"units": "metric",   # "metric" or "imperial" (shown by the screens from step 12c on)
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


static func is_imperial() -> bool:
	return get_value("units") == "imperial"


## Calls listener(key) after every change (key "" after a reset).
static func on_changed(listener: Callable) -> void:
	if not _listeners.has(listener):
		_listeners.append(listener)


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
