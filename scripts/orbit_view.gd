extends Control
## Orbit view: the one map screen. It shows a system (the Sun, a planet with its moons) with the bodies
## on rails, the ship and its planned route. The panels below the top bar depend on the context:
##  - the mission planner (destination, Plan, Launch, Skip) appears in a system that contains a ship
##    that can launch (it is in orbit around the body in view or one of its moons), or while a plan waits;
##  - ship operations (refuel, load facility kits at a shipyard, deploy a kit) appear with the planner,
##    each only where it is possible;
##  - the Ship design button in the top bar appears where the ship is at a shipyard.
## "Plan" finds the next launch window and the burns; "Launch" commits the plan; then run time forward
## (or use "Skip to Departure") and watch the ship follow its orbit legs.

const SKIP_LEAD_DAYS := 120.0 / 86400.0  # "skip to departure" stops two minutes before the burn
const MIN_LAUNCH_DELAY_DAYS := 10.0 / 86400.0  # a plan never starts earlier than this after "now"
const MIN_BODY_RADIUS_PX := 3.0
const RING_RADIUS_PX := 10.0
const ORBIT_SAMPLES := 160
const MOBILE_UI_SCALE := 2.0

# The game state is shared between screens (see GameState); these properties are shortcuts to it.
var bodies: Dictionary:
	get: return GameState.bodies
var children: Dictionary:
	get: return GameState.children
var time_jd: float:
	get: return GameState.time_jd
	set(value): GameState.time_jd = value
var paused: bool:
	get: return GameState.paused
	set(value): GameState.paused = value
var warp_index: int:
	get: return GameState.warp_index
	set(value): GameState.warp_index = value
var legs: Array:
	get: return GameState.legs
	set(value): GameState.legs = value
var plan: Dictionary:
	get: return GameState.plan
	set(value): GameState.plan = value
var message: String:
	get: return GameState.message
	set(value): GameState.message = value

var frames: Array = []          # "auto" plus every body id
var frame_index := 0
var destination_ids: Array = []  # what the destination picker currently offers
var picker_origin := ""         # the body the picker was filled for

var bar: TopBar
var info_label: Label
var target_picker: OptionButton
var plan_button: Button
var launch_button: Button
var skip_button: Button
var refuel_button: Button
var deploy_button: Button
var buy_button: Button
var planner_row: HFlowContainer
var ops_row: HFlowContainer
var kit_buttons: Dictionary = {}   # facility type id -> button


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = MOBILE_UI_SCALE
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	if not GameState.load_data():
		set_process(false)
		return
	frames = ["auto"] + GameState.bodies.keys()
	frame_index = GameState.view_frame_index
	_build_ui()
	_fill_destinations(GameState.view_target_id)


func _goto(scene_path: String) -> void:
	GameState.view_frame_index = frame_index
	GameState.view_target_id = _selected_target_id()
	get_tree().change_scene_to_file(scene_path)


# ---------------------------------------------------------------- user interface

func _build_ui() -> void:
	bar = TopBar.new()
	bar.setup("res://main.tscn", "View: auto")
	bar.view_pressed.connect(func() -> void: frame_index = (frame_index + 1) % frames.size())
	bar.navigate.connect(_goto)
	add_child(bar)

	planner_row = bar.add_row()
	var row := planner_row
	target_picker = OptionButton.new()
	target_picker.item_selected.connect(func(_i: int) -> void: _on_target_changed())
	row.add_child(target_picker)
	plan_button = _add_button(row, "Plan", _on_plan)
	launch_button = _add_button(row, "Launch", _on_launch)
	skip_button = _add_button(row, "Skip to Departure & Launch", _on_skip)
	ops_row = bar.add_row()
	refuel_button = _add_button(ops_row, "Refuel", _on_refuel)
	buy_button = _add_button(ops_row, "Buy propellant", _on_buy)
	for type_id in GameState.kit_type_ids():
		var id: String = type_id
		var kit_button := _add_button(ops_row, "Load %s kit" % str(GameState.facility_types[id]["name"]).to_lower(),
				func() -> void: GameState.message = GameState.load_kit(id))
		kit_buttons[id] = kit_button
	deploy_button = _add_button(ops_row, "Deploy", _on_deploy)
	_add_button(ops_row, "Reset game", _on_reset)

	info_label = Label.new()
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.box.add_child(info_label)


## Tapping or clicking the bottom third of the screen changes the time flow, as in the solar system
## view: left half = slower, right half = faster.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.position.y < size.y * 0.67:
		return
	GameState.change_warp(-1 if click.position.x < size.x * 0.5 else 1)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TAB:
			frame_index = (frame_index + 1) % frames.size()
		KEY_ESCAPE:
			_goto("res://menu.tscn")
		KEY_SPACE:
			GameState.toggle_pause()
		KEY_EQUAL, KEY_KP_ADD, KEY_PERIOD:
			GameState.change_warp(1)
		KEY_MINUS, KEY_KP_SUBTRACT, KEY_COMMA:
			GameState.change_warp(-1)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _selected_target_id() -> String:
	if target_picker.selected < 0 or target_picker.selected >= destination_ids.size():
		return ""
	return destination_ids[target_picker.selected]


## Fills the destination picker for the body the ship is at; keeps the previous choice if still offered.
func _fill_destinations(keep_id: String) -> void:
	picker_origin = GameState.ship_body()
	target_picker.clear()
	destination_ids = []
	if picker_origin == "":
		return
	destination_ids = MissionPlanner.destinations(picker_origin)
	for id in destination_ids:
		target_picker.add_item("To " + str(bodies[id]["name"]))
	var index := destination_ids.find(keep_id)
	target_picker.select(maxi(index, 0))


func _on_target_changed() -> void:
	if GameState.ship_in_transit():
		return
	legs = [GameState.parked_leg()]
	plan = {}
	message = ""


func _on_plan() -> void:
	var parked := GameState.parked_leg()
	if parked.is_empty():
		return
	legs = [parked]
	var result := MissionPlanner.make_plan(str(parked["parent"]), parked["segment"], _selected_target_id(), time_jd + MIN_LAUNCH_DELAY_DAYS)
	paused = true
	if result.has("error"):
		plan = {}
		message = str(result["error"])
	else:
		plan = result
		message = ""


func _on_launch() -> void:
	if plan.is_empty():
		return
	GameState.budget_eur -= GameState.mission_cost_eur
	plan["committed"] = true
	legs = [
		legs[0],
		{"parent": plan["frame"], "segment": plan["transfer_segment"], "t_start": plan["t_dep"],
				"label": "Transfer orbit to %s" % plan["target_name"], "kind": "transfer"},
		{"parent": plan["target_id"], "segment": plan["capture_segment"], "t_start": plan["t_arr"],
				"label": "Orbit around %s" % plan["target_name"], "kind": "orbit"},
	]


## Launches (commits the plan) if that has not happened yet, jumps to just before the departure burn
## and resumes time in real time.
func _on_skip() -> void:
	if plan.is_empty():
		return
	if not plan["committed"]:
		_on_launch()
	time_jd = maxf(time_jd, float(plan["t_dep"]) - SKIP_LEAD_DAYS)
	paused = false
	warp_index = 0


func _on_refuel() -> void:
	var amount := GameState.refuel()
	message = "Refuelled %s kg." % GameState.thousands(amount) if amount > 0.0 else "Nothing to refuel."


func _on_buy() -> void:
	var amount := GameState.buy_propellant()
	message = "Bought %s kg of propellant for %s EUR." % [GameState.thousands(amount),
			GameState.thousands(amount * GameState.propellant_price_eur_per_kg)] if amount > 0.0 else "Nothing to buy."


func _on_deploy() -> void:
	message = GameState.deploy_kit()


func _on_reset() -> void:
	GameState.reset_mission()
	_fill_destinations("moon")


# ---------------------------------------------------------------- state helpers

## True from the departure burn until the arrival burn.
func _in_transit() -> bool:
	return GameState.ship_in_transit()


func _plan_dv_total() -> float:
	return float(plan["dv_departure"]) + float(plan["dv_arrival"])


func _body_rel(id: String, jd: float) -> Vector2:
	return GameState.body_rel(id, jd)


func _body_abs(id: String, jd: float) -> Vector2:
	return GameState.body_abs(id, jd)


func _leg_index_at(jd: float) -> int:
	return GameState.leg_index_at(jd)


func _ship_abs(jd: float) -> Vector2:
	return GameState.ship_abs(jd)


func _frame_id() -> String:
	var choice: String = frames[frame_index]
	if choice != "auto":
		return choice
	var index := _leg_index_at(time_jd)
	var parent_id := str(legs[index]["parent"])
	# Before departure show the system the transfer happens in (for example the Sun for a planet transfer).
	if index == 0 and not plan.is_empty() and plan["frame"] != parent_id:
		return str(plan["frame"])
	return parent_id


# ---------------------------------------------------------------- time and text

func _process(delta: float) -> void:
	GameState.advance(delta)
	if picker_origin != GameState.ship_body():
		_fill_destinations(_selected_target_id())
	_update_ui()
	queue_redraw()


func _update_ui() -> void:
	var in_transit := _in_transit()
	plan_button.disabled = in_transit or destination_ids.is_empty()
	target_picker.disabled = in_transit
	var affordable := not plan.is_empty() and _plan_dv_total() <= GameState.dv_left_kms() + 0.00001
	var window_open := not plan.is_empty() and time_jd < float(plan["t_dep"])
	var funded := GameState.budget_eur >= GameState.mission_cost_eur
	launch_button.disabled = plan.is_empty() or plan["committed"] or not affordable or not window_open or not funded
	skip_button.disabled = plan.is_empty() or not window_open or not affordable or (not funded and not plan["committed"])
	skip_button.text = "Skip to Departure" if not plan.is_empty() and plan["committed"] else "Skip to Departure & Launch"
	var ship_body := GameState.ship_body()
	var plant: Dictionary = GameState.facility_of_kind(ship_body, "propellant_plant") if ship_body != "" else {}
	refuel_button.visible = not plant.is_empty()
	refuel_button.disabled = float(plant.get("stock_kg", 0.0)) <= 0.0 \
			or GameState.ship_fuel_kg >= GameState.ship_fuel_capacity_kg - 0.001
	var at_yard := ship_body != "" and not GameState.facility_of_kind(ship_body, "shipyard").is_empty()
	buy_button.visible = at_yard
	buy_button.disabled = GameState.ship_fuel_kg >= GameState.ship_fuel_capacity_kg - 0.001 or GameState.budget_eur <= 0.0
	for type_id in kit_buttons:
		kit_buttons[type_id].visible = at_yard
		kit_buttons[type_id].disabled = GameState.kit_load_problem(type_id) != ""
	deploy_button.visible = GameState.deployable_type() != ""
	var frame_id := _frame_id()
	planner_row.visible = GameState.planner_available(frame_id)
	ops_row.visible = true
	bar.set_design_visible(GameState.design_available(frame_id))
	bar.set_view_text("View: " + str(frames[frame_index]))
	bar.refresh()
	info_label.text = _info_text()


func _span_text(days: float) -> String:
	if absf(days) < 2.0:
		return "%.1f h" % (days * 24.0)
	return "%.1f days" % days


func _fuel_text() -> String:
	return "%s kg (%.2f km/s) of %s kg (%.2f km/s)" % [
			GameState.thousands(GameState.ship_fuel_kg), GameState.dv_left_kms(),
			GameState.thousands(GameState.ship_fuel_capacity_kg), GameState.ship_dv_kms]


func _info_text() -> String:
	var lines: PackedStringArray = []
	lines.append("%s: %s" % [GameState.ship_name, legs[_leg_index_at(time_jd)]["label"]])
	lines.append("Fuel: %s" % _fuel_text())
	lines.append("Budget: %s EUR" % GameState.thousands(GameState.budget_eur))
	if not GameState.cargo.is_empty():
		var names: PackedStringArray = []
		for type_id in GameState.cargo:
			names.append(str(GameState.facility_types[type_id]["name"]))
		lines.append("Cargo (%s of %s kg): %s" % [GameState.thousands(GameState.cargo_mass_kg()),
				GameState.thousands(GameState.ship_payload_kg), ", ".join(names)])
	for id in GameState.facilities:
		var facility: Dictionary = GameState.facilities[id]
		if facility["kind"] != "propellant_plant":
			lines.append(str(facility["name"]))
			continue
		lines.append("%s: %s kg of %s kg (+%s kg/day)" % [facility["name"], GameState.thousands(float(facility["stock_kg"])),
				GameState.thousands(float(facility["storage_capacity_kg"])), GameState.thousands(GameState.facility_output_per_day(facility))])
	if plan.is_empty():
		if message != "":
			lines.append(message)
		elif _in_transit():
			lines.append("In transit.")
		elif planner_row.visible:
			lines.append("Choose a destination and press Plan to find the next launch window.")
		return "\n".join(lines)
	lines.append("Plan: %s to %s" % [bodies[plan["origin_id"]]["name"], plan["target_name"]])
	lines.append("Departure: %s (in %s)" % [GameState.date_text(float(plan["t_dep"])), _span_text(float(plan["t_dep"]) - time_jd)])
	lines.append("Arrival: %s (flight %s)" % [GameState.date_text(float(plan["t_arr"])), _span_text(float(plan["flight_days"]))])
	if not plan["committed"]:
		lines.append("Launch cost: %s EUR" % GameState.thousands(GameState.mission_cost_eur))
	lines.append("Burns: departure %.2f + capture %.2f = %.2f km/s" % [
			float(plan["dv_departure"]), float(plan["dv_arrival"]), _plan_dv_total()])
	if message != "":
		lines.append(message)
	if not plan["committed"] and _plan_dv_total() > GameState.dv_left_kms():
		lines.append("Not enough fuel for this mission. Refuel, or build a stronger ship on the ship design screen.")
	elif plan["committed"]:
		lines.append("Mission launched." if time_jd < float(plan["t_arr"]) else "Arrived at %s." % plan["target_name"])
	elif time_jd >= float(plan["t_dep"]):
		lines.append("The launch window has passed. Press Plan again.")
	else:
		lines.append("Ready: press Launch and resume time, or press Skip to Departure & Launch.")
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

	var ship_local := GameState.ship_rel(frame_id, time_jd)
	var p := _to_screen(ship_local, centre, px_per_km)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 5), p + Vector2(-6, 5)]), Color.WHITE)
	draw_string(ThemeDB.fallback_font, p + Vector2(10, 22), GameState.ship_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


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
	var facility_count := GameState.facilities_at(id).size()
	for n in facility_count:
		draw_rect(Rect2(screen_position + Vector2(-radius_px - 9.0 - 9.0 * n, -radius_px - 9.0), Vector2(7, 7)), Color(1.0, 0.6, 0.2))
	draw_string(ThemeDB.fallback_font, screen_position + Vector2(radius_px + 4.0, 5.0), body["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
