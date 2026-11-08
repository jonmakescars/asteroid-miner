extends Control
## Prototype build step 5: design one ship with two chemical stages and see its delta-v.
## All widgets are built in code. Sliders for masses and thrust are logarithmic, so one
## slider covers small probes and large ships alike.

const ENGINES_PATH := "res://data/engines.json"
const MOBILE_UI_SCALE := 2.5  # phone screens are dense; the UI is scaled up there only
const PAYLOAD_RANGE := Vector2(100.0, 500000.0)       # kg
const PROPELLANT_RANGE := Vector2(100.0, 2000000.0)   # kg
const THRUST_RANGE := Vector2(1.0, 50000.0)           # kN

# Starting design: roughly a 10 km/s ship with a 5 t payload.
const DEFAULT_STAGES := [
	{"engine": "kerolox", "propellant": 100000.0, "thrust": 1500.0, "durability": 0.5},
	{"engine": "hydrolox", "propellant": 20000.0, "thrust": 110.0, "durability": 0.5},
]
const DEFAULT_PAYLOAD_KG := 5000.0

# Rough values from memory, only as a yardstick until the mission planner (step 6) calculates them.
const REFERENCE_DV := [
	["Earth orbit to Moon transfer", 3.1],
	["Moon orbit capture", 0.9],
	["Moon landing from low orbit", 1.8],
	["Earth orbit to Mars transfer", 3.6],
]

var engines: Dictionary = {}     # id -> engine dictionary
var engine_order: Array = []     # ids in file order
var rules: Dictionary = {}
var payload_ctl: Dictionary = {}
var stage_ctls: Array = []       # per stage: {"engine": OptionButton, "propellant": ctl, "thrust": ctl, "durability": ctl}
var result_label: Label


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = MOBILE_UI_SCALE
	if not _load_engines():
		return
	_build_ui()
	_refresh()


func _load_engines() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ENGINES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Cannot read %s (on Android, add *.json to the export filter)." % ENGINES_PATH)
		return false
	rules = parsed["design_rules"]
	for engine in parsed["engines"]:
		engines[engine["id"]] = engine
		engine_order.append(engine["id"])
	return true


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	_add_heading(box, "Ship design (prototype step 5)")
	payload_ctl = _add_slider(box, "Payload", PAYLOAD_RANGE, true, DEFAULT_PAYLOAD_KG, "kg")

	for i in DEFAULT_STAGES.size():
		var defaults: Dictionary = DEFAULT_STAGES[i]
		_add_heading(box, "Stage %d%s" % [i + 1, " (fires first)" if i == 0 else ""])
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(0, 40)
		for id in engine_order:
			picker.add_item(str(engines[id]["name"]))
		picker.selected = engine_order.find(defaults["engine"])
		picker.item_selected.connect(func(_index: int) -> void: _refresh())
		box.add_child(picker)
		stage_ctls.append({
			"engine": picker,
			"propellant": _add_slider(box, "Propellant", PROPELLANT_RANGE, true, float(defaults["propellant"]), "kg"),
			"thrust": _add_slider(box, "Thrust", THRUST_RANGE, true, float(defaults["thrust"]), "kN"),
			"durability": _add_slider(box, "Durability", Vector2(0.0, 1.0), false, float(defaults["durability"]), ""),
		})

	_add_heading(box, "Result")
	result_label = Label.new()
	box.add_child(result_label)


func _add_heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	parent.add_child(Control.new())  # small spacer
	parent.add_child(label)


## Adds a row with a title, a text box and a unit, plus a slider; returns a Dictionary describing the control.
## The slider and the text box change the same value. The text box accepts exact numbers.
func _add_slider(parent: Control, title: String, value_range: Vector2, logarithmic: bool, start: float, unit: String) -> Dictionary:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var title_label := Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(150, 0)
	edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edit.select_all_on_focus = true
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	row.add_child(edit)
	var unit_label := Label.new()
	unit_label.text = unit
	unit_label.custom_minimum_size = Vector2(36, 0)
	row.add_child(unit_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.001
	slider.custom_minimum_size = Vector2(0, 40)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slider)

	var control := {"edit": edit, "slider": slider, "range": value_range, "log": logarithmic, "value": start}
	slider.set_value_no_signal(_to_slider(start, control))
	slider.value_changed.connect(func(_v: float) -> void:
		control["value"] = _value_from_slider(control)
		_refresh())
	edit.text_submitted.connect(func(text: String) -> void: _apply_text(control, text))
	edit.focus_exited.connect(func() -> void: _apply_text(control, edit.text))
	return control


## Takes a number typed into a text box: clamps it to the allowed range and moves the slider to match.
func _apply_text(control: Dictionary, text: String) -> void:
	var cleaned := text.strip_edges().replace(",", ".")
	if cleaned.is_valid_float():
		var value_range: Vector2 = control["range"]
		var value := clampf(cleaned.to_float(), value_range.x, value_range.y)
		control["value"] = value
		(control["slider"] as HSlider).set_value_no_signal(_to_slider(value, control))
	_refresh()  # also rewrites the text box, which restores the old value if the input was not a number


func _to_slider(value: float, control: Dictionary) -> float:
	var value_range: Vector2 = control["range"]
	if control["log"]:
		return log(value / value_range.x) / log(value_range.y / value_range.x)
	return (value - value_range.x) / (value_range.y - value_range.x)


func _value_from_slider(control: Dictionary) -> float:
	var value_range: Vector2 = control["range"]
	var position: float = (control["slider"] as HSlider).value
	if control["log"]:
		var raw := value_range.x * pow(value_range.y / value_range.x, position)
		var step := pow(10.0, floor(log(raw) / log(10.0)) - 2.0)  # three significant figures
		return round(raw / step) * step
	return snappedf(value_range.x + position * (value_range.y - value_range.x), 0.01)


func _value_of(control: Dictionary) -> float:
	return float(control["value"])


func _num(value: float) -> String:
	if value >= 100.0:
		return str(int(round(value)))
	if value >= 10.0:
		return "%.1f" % value
	return "%.2f" % value


func _refresh() -> void:
	if result_label == null:
		return
	var payload_kg := _value_of(payload_ctl)
	_update_label(payload_ctl)
	var stages: Array = []
	for ctls in stage_ctls:
		for key in ["propellant", "thrust", "durability"]:
			_update_label(ctls[key])
		var picker: OptionButton = ctls["engine"]
		stages.append({
			"engine_id": engine_order[picker.selected],
			"propellant_kg": maxf(_value_of(ctls["propellant"]), float(rules["min_stage_propellant_kg"])),
			"thrust_kn": _value_of(ctls["thrust"]),
			"durability": _value_of(ctls["durability"]),
		})

	var analysis := ShipCalc.analyse(stages, engines, rules, payload_kg)
	var lines: PackedStringArray = []
	lines.append("Total delta-v: %s km/s" % _num(float(analysis["total_dv_ms"]) / 1000.0))
	lines.append("Total mass at launch: %s t" % _num(float(analysis["total_mass_kg"]) / 1000.0))
	for i in stages.size():
		var result: Dictionary = analysis["stages"][i]
		var accel := float(result["accel_start_ms2"])
		lines.append("")
		lines.append("Stage %d: %s km/s | dry mass %s t | start mass %s t" % [
				i + 1, _num(float(result["dv_ms"]) / 1000.0), _num(float(result["dry_kg"]) / 1000.0),
				_num(float(result["mass_start_kg"]) / 1000.0)])
		lines.append("   start acceleration %s m/s2 (%s g) | burn time %s s" % [
				_num(accel), _num(accel / ShipCalc.G0), _num(float(result["burn_time_s"]))])
		if accel < float(rules["warn_start_accel_below_ms2"]):
			lines.append("   Warning: very low acceleration, the burn takes long (the instant-burn model is only approximate)")
		if accel / ShipCalc.G0 > float(rules["warn_start_accel_above_g"]):
			lines.append("   Warning: acceleration above %s g, dangerous for crew" % str(rules["warn_start_accel_above_g"]))
	lines.append("")
	lines.append("For comparison (approximate, from Earth orbit):")
	for reference in REFERENCE_DV:
		lines.append("   %s: %s km/s" % [reference[0], str(reference[1])])
	result_label.text = "\n".join(lines)


func _update_label(control: Dictionary) -> void:
	(control["edit"] as LineEdit).text = String.num(_value_of(control), 2)
