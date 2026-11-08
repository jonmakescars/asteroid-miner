extends Control
## Prototype build step 6: plan and fly an Earth-to-Moon or Earth-to-Mars mission on rails.
## The ship starts in a circular parking orbit around Earth. "Plan" finds the next launch window and
## the delta-v of the departure and capture burns. "Launch" commits the plan; then run time forward
## (or use "Skip to departure") and watch the ship follow its orbit segments.

const DATA_PATH := "res://data/bodies.json"
const DESIGN_PATH := "user://ship_design.json"  # written by the ship design screen
const DEFAULT_SHIP_DV_KMS := 10.0
const PARKING_ALTITUDE_KM := 400.0
const WARP_STEPS := [1.0 / 86400.0, 1.0 / 1440.0, 1.0 / 24.0, 1.0, 10.0, 100.0, 1000.0]  # game days per real second
const WARP_LABELS := ["real time", "1 min/s", "1 h/s", "1 day/s", "10 days/s", "100 days/s", "1000 days/s"]
const SKIP_LEAD_DAYS := 120.0 / 86400.0  # "skip to departure" stops two minutes before the burn
const MIN_BODY_RADIUS_PX := 3.0
const RING_RADIUS_PX := 10.0
const ORBIT_SAMPLES := 160
const MOBILE_UI_SCALE := 2.0
const FRAMES := ["auto", "sun", "earth", "mars", "moon"]
const TARGETS := [
	{"id": "moon", "name": "Moon", "frame": "earth", "capture_altitude_km": 100.0},
	{"id": "mars", "name": "Mars", "frame": "sun", "capture_altitude_km": 400.0},
]

var bodies: Dictionary = {}
var children: Dictionary = {}
var start_jd := 0.0
var time_jd := 0.0
var warp_index := 0
var paused := true
var frame_index := 0
var ship_dv_kms := DEFAULT_SHIP_DV_KMS
var ship_dv_source := "default value; design a ship on the ship design screen"
var ship_name := "Ship"
var parking_segment: Dictionary = {}
var legs: Array = []     # the ship's orbit legs: {parent, segment, t_start, label}
var plan: Dictionary = {}
var message := ""

var info_label: Label
var target_picker: OptionButton
var plan_button: Button
var launch_button: Button
var skip_button: Button
var pause_button: Button
var frame_button: Button


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = MOBILE_UI_SCALE
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Cannot read %s (on Android, add *.json to the export filter)." % DATA_PATH)
		set_process(false)
		return
	start_jd = float(parsed["game_start"]["jd"])
	for body in parsed["bodies"]:
		bodies[body["id"]] = body
		children[body["id"]] = []
	for id in bodies:
		var parent_id: Variant = bodies[id]["parent"]
		if parent_id != null:
			children[parent_id].append(id)
	_load_ship_dv()
	_build_ui()
	_reset()


func _load_ship_dv() -> void:
	if not FileAccess.file_exists(DESIGN_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("total_dv_ms"):
		ship_dv_kms = float(parsed["total_dv_ms"]) / 1000.0
		ship_dv_source = "from the ship design screen"
		ship_name = str(parsed.get("name", ship_name))


func _reset() -> void:
	time_jd = start_jd
	paused = true
	warp_index = 0
	plan = {}
	message = ""
	var earth_gm := float(bodies["earth"]["gm_km3_s2"])
	var radius := float(bodies["earth"]["radius_km"]) + PARKING_ALTITUDE_KM
	parking_segment = TransferPlanner.circular_segment(radius, earth_gm, start_jd, 0.0)
	legs = [{"parent": "earth", "segment": parking_segment, "t_start": start_jd, "label": "Parking orbit around Earth"}]


# ---------------------------------------------------------------- user interface

func _build_ui() -> void:
	var hud := PanelContainer.new()
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(hud)
	var box := VBoxContainer.new()
	hud.add_child(box)

	var row1 := HFlowContainer.new()
	box.add_child(row1)
	target_picker = OptionButton.new()
	for target in TARGETS:
		target_picker.add_item("To " + str(target["name"]))
	target_picker.item_selected.connect(func(_i: int) -> void: _on_target_changed())
	row1.add_child(target_picker)
	plan_button = _add_button(row1, "Plan", _on_plan)
	launch_button = _add_button(row1, "Launch", _on_launch)
	skip_button = _add_button(row1, "Launch + skip to departure", _on_skip)
	_add_button(row1, "Reset", _reset)

	var row2 := HFlowContainer.new()
	box.add_child(row2)
	_add_button(row2, "Slower", func() -> void: warp_index = maxi(warp_index - 1, 0))
	pause_button = _add_button(row2, "Pause", func() -> void: paused = not paused)
	_add_button(row2, "Faster", func() -> void: warp_index = mini(warp_index + 1, WARP_STEPS.size() - 1))
	frame_button = _add_button(row2, "View", func() -> void: frame_index = (frame_index + 1) % FRAMES.size())
	_add_button(row2, "Ship design", func() -> void: get_tree().change_scene_to_file("res://ship_design.tscn"))

	info_label = Label.new()
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info_label)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _on_target_changed() -> void:
	if not _departed():
		plan = {}
		legs = [legs[0]]
		message = ""


func _on_plan() -> void:
	var target: Dictionary = TARGETS[target_picker.selected]
	legs = [legs[0]]
	plan = _make_plan(target)
	paused = true
	message = "" if not plan.is_empty() else "No launch window found within the search period."


func _on_launch() -> void:
	if plan.is_empty():
		return
	plan["committed"] = true
	legs = [
		legs[0],
		{"parent": plan["frame"], "segment": plan["transfer_segment"], "t_start": plan["t_dep"],
				"label": "Transfer orbit to %s" % plan["target_name"]},
		{"parent": plan["target_id"], "segment": plan["capture_segment"], "t_start": plan["t_arr"],
				"label": "Orbit around %s" % plan["target_name"]},
	]


## Launches (commits the plan) and jumps to just before the departure burn. Time stays as it was (paused or not).
func _on_skip() -> void:
	if plan.is_empty():
		return
	if not plan["committed"]:
		_on_launch()
	time_jd = maxf(time_jd, float(plan["t_dep"]) - SKIP_LEAD_DAYS)


func _departed() -> bool:
	return not plan.is_empty() and plan.get("committed", false) and time_jd >= float(plan["t_dep"])


# ---------------------------------------------------------------- planning

## Finds the next launch window to the target and the burns it needs. Returns {} if there is none.
func _make_plan(target: Dictionary) -> Dictionary:
	var target_id: String = target["id"]
	var frame: String = target["frame"]
	var gm := float(bodies[frame]["gm_km3_s2"])
	var earth_gm := float(bodies["earth"]["gm_km3_s2"])
	var parking := parking_segment
	var parking_radius := float(parking["semi_major_axis_km"])
	var target_fn := func(t: float) -> Vector2: return _body_rel(target_id, t)
	var origin_fn: Callable
	var horizon := 0.3   # days to search; a parking orbit passes every spot within 0.07 days
	var step := 0.002
	if frame == "earth":
		origin_fn = func(t: float) -> Vector2: return Kepler.position_at(parking, t)
	else:
		origin_fn = func(t: float) -> Vector2: return _body_rel("earth", t)
		horizon = 900.0  # longer than the synodic period of Earth and Mars (about 780 days)
		step = 1.0

	var transfer := TransferPlanner.find_window(gm, origin_fn, target_fn, time_jd, horizon, step)
	if transfer.is_empty():
		return {}
	var t_dep := float(transfer["t_dep"])
	var dv_departure := 0.0
	if frame == "earth":
		dv_departure = TransferPlanner.departure_dv_bound(transfer, gm)
	else:
		var origin_velocity := TransferPlanner.velocity_kms(origin_fn, t_dep)
		dv_departure = TransferPlanner.departure_dv_escape(transfer, origin_velocity, earth_gm, parking_radius)
	var capture_radius := float(bodies[target_id]["radius_km"]) + float(target["capture_altitude_km"])
	var target_gm := float(bodies[target_id]["gm_km3_s2"])
	var arrival := TransferPlanner.arrival_dv(transfer, target_fn, target_gm, capture_radius)
	return {
		"target_id": target_id,
		"target_name": target["name"],
		"frame": frame,
		"t_dep": t_dep,
		"t_arr": float(transfer["t_arr"]),
		"flight_days": float(transfer["flight_days"]),
		"dv_departure": dv_departure,
		"dv_arrival": float(arrival["dv_kms"]),
		"v_inf_arrival": float(arrival["v_inf_kms"]),
		"transfer_segment": TransferPlanner.transfer_segment(transfer, gm),
		"capture_segment": TransferPlanner.circular_segment(capture_radius, target_gm, float(transfer["t_arr"]), 0.0),
		"committed": false,
		"arrival_seen": false,
	}


func _plan_dv_total() -> float:
	return float(plan["dv_departure"]) + float(plan["dv_arrival"])


# ---------------------------------------------------------------- positions on rails

## Position (km) of a body relative to its parent.
func _body_rel(id: String, jd: float) -> Vector2:
	var segments: Array = bodies[id]["orbit_segments"]
	if segments.is_empty():
		return Vector2.ZERO
	return Kepler.position_at(Kepler.segment_at(segments, jd), jd)


## Position (km) of a body relative to the Sun.
func _body_abs(id: String, jd: float) -> Vector2:
	var total := Vector2.ZERO
	var current: Variant = id
	while current != null:
		total += _body_rel(str(current), jd)
		current = bodies[str(current)]["parent"]
	return total


func _leg_index_at(jd: float) -> int:
	var chosen := 0
	for i in legs.size():
		if float(legs[i]["t_start"]) <= jd:
			chosen = i
	return chosen


func _ship_abs(jd: float) -> Vector2:
	var leg: Dictionary = legs[_leg_index_at(jd)]
	return _body_abs(str(leg["parent"]), jd) + Kepler.position_at(leg["segment"], jd)


func _frame_id() -> String:
	var choice: String = FRAMES[frame_index]
	if choice != "auto":
		return choice
	var index := _leg_index_at(time_jd)
	# While waiting for a window to Mars, watch the planets rather than the parking orbit.
	if index == 0 and not plan.is_empty() and plan["frame"] == "sun":
		return "sun"
	return str(legs[index]["parent"])


# ---------------------------------------------------------------- time

func _process(delta: float) -> void:
	if not paused:
		time_jd += delta * float(WARP_STEPS[warp_index])
	# On arrival, drop back to the slowest time flow.
	if not plan.is_empty() and plan["committed"] and not plan["arrival_seen"] and time_jd >= float(plan["t_arr"]):
		plan["arrival_seen"] = true
		warp_index = 0
	_update_ui()
	queue_redraw()


func _update_ui() -> void:
	var departed := _departed()
	plan_button.disabled = departed
	var affordable := not plan.is_empty() and _plan_dv_total() <= ship_dv_kms
	var window_open := not plan.is_empty() and time_jd < float(plan["t_dep"]) - 0.0001
	launch_button.disabled = plan.is_empty() or plan["committed"] or not affordable or not window_open
	skip_button.disabled = plan.is_empty() or not window_open or not affordable
	pause_button.text = "Resume" if paused else "Pause"
	frame_button.text = "View: " + str(FRAMES[frame_index])
	info_label.text = _info_text()


func _date_text(jd: float) -> String:
	return Time.get_datetime_string_from_unix_time(int((jd - 2440587.5) * 86400.0)).replace("T", " ")


func _span_text(days: float) -> String:
	if absf(days) < 2.0:
		return "%.1f h" % (days * 24.0)
	return "%.1f days" % days


func _dv_left() -> float:
	var left := ship_dv_kms
	if not plan.is_empty() and plan["committed"]:
		if time_jd >= float(plan["t_dep"]):
			left -= float(plan["dv_departure"])
		if time_jd >= float(plan["t_arr"]):
			left -= float(plan["dv_arrival"])
	return left


func _info_text() -> String:
	var lines: PackedStringArray = []
	var warp_text := "paused (%s)" % WARP_LABELS[warp_index] if paused else str(WARP_LABELS[warp_index])
	lines.append("%s | warp %s" % [_date_text(time_jd), warp_text])
	lines.append("%s: %s | delta-v left %.2f km/s (%s)" % [
			ship_name, legs[_leg_index_at(time_jd)]["label"], _dv_left(), ship_dv_source])
	if plan.is_empty():
		lines.append(message if message != "" else "Choose a destination and press Plan to find the next launch window.")
		return "\n".join(lines)
	lines.append("Departure: %s (in %s)" % [_date_text(float(plan["t_dep"])), _span_text(float(plan["t_dep"]) - time_jd)])
	lines.append("Arrival: %s (flight %s)" % [_date_text(float(plan["t_arr"])), _span_text(float(plan["flight_days"]))])
	lines.append("Burns: departure %.2f + capture %.2f = %.2f km/s" % [
			float(plan["dv_departure"]), float(plan["dv_arrival"]), _plan_dv_total()])
	if _plan_dv_total() > ship_dv_kms:
		lines.append("Not enough delta-v for this mission. Build a stronger ship on the ship design screen.")
	elif plan["committed"]:
		lines.append("Mission launched." if time_jd < float(plan["t_arr"]) else "Arrived at %s." % plan["target_name"])
	elif time_jd >= float(plan["t_dep"]):
		lines.append("The launch window has passed. Press Plan again.")
	else:
		lines.append("Ready: press Launch and resume time, or press Launch + skip to departure.")
	return "\n".join(lines)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var frame_id := _frame_id()
	var centre := Vector2(size.x * 0.5, size.y * 0.58)
	var half_extent := minf(size.x * 0.5, size.y * 0.38)
	var kid_ids: Array = children[frame_id]
	var leg: Dictionary = legs[_leg_index_at(time_jd)]

	# Scale so that the widest orbit in this frame (or the ship's orbit, if it has no children) fits.
	var extent := float(bodies[frame_id]["radius_km"]) * 4.0
	if kid_ids.is_empty() and leg["parent"] == frame_id:
		extent = maxf(extent, float(leg["segment"]["semi_major_axis_km"]) * 1.5)
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		extent = maxf(extent, float(segment["semi_major_axis_km"]) * (1.0 + float(segment["eccentricity"])))
	var px_per_km := half_extent * 0.9 / extent

	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		var line := PackedVector2Array()
		for point in Kepler.orbit_points(segment, ORBIT_SAMPLES):
			line.append(_to_screen(point, centre, px_per_km))
		draw_polyline(line, Color(1, 1, 1, 0.25), 1.0, true)

	# Planned transfer path, drawn when the transfer happens around the body at the centre of the view.
	if not plan.is_empty() and plan["frame"] == frame_id:
		var path := PackedVector2Array()
		for i in 81:
			var t := float(plan["t_dep"]) + float(plan["flight_days"]) * float(i) / 80.0
			path.append(_to_screen(Kepler.position_at(plan["transfer_segment"], t), centre, px_per_km))
		draw_polyline(path, Color(0.4, 0.9, 1.0, 0.9), 1.5, true)
	if leg["parent"] == frame_id:
		var ring := PackedVector2Array()
		for point in Kepler.orbit_points(leg["segment"], 64):
			ring.append(_to_screen(point, centre, px_per_km))
		draw_polyline(ring, Color(0.4, 0.9, 1.0, 0.6), 1.0, true)

	_draw_body(frame_id, centre, px_per_km)
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		_draw_body(kid_id, _to_screen(Kepler.position_at(segment, time_jd), centre, px_per_km), px_per_km)

	var ship_local := _ship_abs(time_jd) - _body_abs(frame_id, time_jd)
	var p := _to_screen(ship_local, centre, px_per_km)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 5), p + Vector2(-6, 5)]), Color.WHITE)
	draw_string(ThemeDB.fallback_font, p + Vector2(10, 22), ship_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _to_screen(position_km: Vector2, centre: Vector2, px_per_km: float) -> Vector2:
	return centre + Vector2(position_km.x, -position_km.y) * px_per_km


func _draw_body(id: String, screen_position: Vector2, px_per_km: float) -> void:
	var body: Dictionary = bodies[id]
	var radius_px := maxf(MIN_BODY_RADIUS_PX, float(body["radius_km"]) * px_per_km)
	var colour := Color.html(body["draw_color"])
	draw_circle(screen_position, radius_px, colour)
	if radius_px < RING_RADIUS_PX:
		draw_arc(screen_position, RING_RADIUS_PX, 0.0, TAU, 32, colour, 1.5, true)
		radius_px = RING_RADIUS_PX
	draw_string(ThemeDB.fallback_font, screen_position + Vector2(radius_px + 4.0, 5.0), body["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
