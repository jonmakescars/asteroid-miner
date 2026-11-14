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
const LATE_LAUNCH_DAYS := 300.0 / 86400.0  # a plan can still be launched this long after its departure time
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
var abort_button: Button
var keep_button: Button
var warning_label: Label
var launch_dialog: ConfirmationDialog
var lost_overlay: ShipLostOverlay
var skip_button: Button
var refuel_button: Button
var deploy_button: Button
var buy_button: Button
var shield_button: Button
var aero_row: HFlowContainer
var aero_check: CheckButton
var passes_slider: HSlider
var passes_label: Label
var altitude_slider: HSlider
var altitude_label: Label
var altitude_spin: SpinBox
var altitude_minus: Button
var altitude_plus: Button
var altitude_dragging := false
var orbit_row: HFlowContainer
var orbit_control: OrbitControl
var orbit_title: Label
var planner_row: HFlowContainer
var ops_row: HFlowContainer
var syncing_aero := false
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
	abort_button = _add_button(row, "Abort launch", _on_abort)
	keep_button = _add_button(row, "Keep current course", _on_keep_course)
	launch_dialog = ConfirmationDialog.new()
	launch_dialog.title = "Warning"
	launch_dialog.ok_button_text = "Launch anyway"
	launch_dialog.cancel_button_text = "Back to planning"
	launch_dialog.dialog_autowrap = true
	launch_dialog.wrap_controls = true
	add_child(launch_dialog)
	aero_row = bar.add_row()
	aero_check = CheckButton.new()
	aero_check.text = "Aerobrake"
	aero_check.toggled.connect(func(pressed: bool) -> void:
		_apply_aero(pressed, int(passes_slider.value), altitude_slider.value))
	aero_row.add_child(aero_check)
	passes_label = Label.new()
	aero_row.add_child(passes_label)
	passes_slider = HSlider.new()
	passes_slider.min_value = 1
	passes_slider.max_value = AeroBraking.MAX_PASSES
	passes_slider.step = 1
	passes_slider.custom_minimum_size = Vector2(160, 40)
	# Changing the number of passes picks the periapsis altitude that still reaches the target orbit; this is
	# slow enough to wait until the slider is released.
	passes_slider.value_changed.connect(func(value: float) -> void:
		passes_label.text = "Passes: %d" % int(value))
	passes_slider.drag_ended.connect(func(_changed: bool) -> void: _on_passes_changed())
	aero_row.add_child(passes_slider)
	altitude_label = Label.new()
	altitude_label.text = "Periapsis altitude:"
	aero_row.add_child(altitude_label)
	altitude_minus = _add_button(aero_row, "-", func() -> void: _nudge_altitude(-0.1))
	altitude_slider = HSlider.new()
	altitude_slider.step = 0.1
	altitude_slider.custom_minimum_size = Vector2(220, 40)
	# The slider only covers a band around the current setting (see AeroBraking.BAND_KM); the number box
	# takes any altitude. The aerobraking numbers are recalculated when the slider is released.
	altitude_slider.drag_started.connect(func() -> void: altitude_dragging = true)
	altitude_slider.drag_ended.connect(func(_changed: bool) -> void:
		altitude_dragging = false
		_apply_aero(aero_check.button_pressed, int(passes_slider.value), altitude_slider.value))
	altitude_slider.value_changed.connect(func(value: float) -> void:
		if syncing_aero:
			return
		altitude_label.text = "Periapsis altitude:"
		if altitude_dragging:
			altitude_spin.set_value_no_signal(value)
		else:
			_apply_aero(aero_check.button_pressed, int(passes_slider.value), value))
	aero_row.add_child(altitude_slider)
	altitude_plus = _add_button(aero_row, "+", func() -> void: _nudge_altitude(0.1))
	altitude_spin = SpinBox.new()
	altitude_spin.step = 0.1
	altitude_spin.suffix = "km"
	altitude_spin.custom_minimum_size = Vector2(120, 40)
	altitude_spin.value_changed.connect(func(value: float) -> void:
		if not syncing_aero:
			_apply_aero(aero_check.button_pressed, int(passes_slider.value), value, true))
	aero_row.add_child(altitude_spin)
	_add_button(aero_row, "Auto", _on_aero_auto)
	orbit_row = bar.add_row()
	orbit_title = Label.new()
	orbit_title.text = "Target orbit:"
	orbit_row.add_child(orbit_title)
	orbit_control = OrbitControl.new()
	orbit_control.orbit_changed.connect(_on_target_orbit_changed)
	orbit_row.add_child(orbit_control)
	ops_row = bar.add_row()
	refuel_button = _add_button(ops_row, "Refuel", _on_refuel)
	buy_button = _add_button(ops_row, "Buy propellant", _on_buy)
	for type_id in GameState.kit_type_ids():
		var id: String = type_id
		var kit_button := _add_button(ops_row, "Load %s kit" % str(GameState.facility_types[id]["name"]).to_lower(),
				func() -> void: GameState.message = GameState.load_kit(id))
		kit_buttons[id] = kit_button
	shield_button = _add_button(ops_row, "Replace heat shield", func() -> void: GameState.message = GameState.replace_shield())
	deploy_button = _add_button(ops_row, "Deploy", _on_deploy)
	_add_button(ops_row, "Reset game", _on_reset)

	warning_label = Label.new()
	warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	bar.box.add_child(warning_label)
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


## What the destination picker was filled for: the body the ship is orbiting, or the body it is flying around.
func _picker_key() -> String:
	var body := GameState.ship_body()
	return body if body != "" else "flight:" + GameState.ship_frame()


## Fills the destination picker (the bodies near the ship's orbit, or the bodies it can be redirected to in
## flight); keeps the previous choice if still offered.
func _fill_destinations(keep_id: String) -> void:
	picker_origin = _picker_key()
	target_picker.clear()
	destination_ids = []
	if GameState.ship_body() != "":
		destination_ids = MissionPlanner.destinations(GameState.ship_body())
	else:
		destination_ids = CourseChange.destinations()
	var here := GameState.ship_body() if GameState.ship_body() != "" else GameState.ship_frame()
	for id in destination_ids:
		target_picker.add_item(("Orbit around " if id == here else "To ") + str(bodies[id]["name"]))
	var index := destination_ids.find(keep_id)
	target_picker.select(maxi(index, 0))


func _on_target_changed() -> void:
	if GameState.ship_in_transit():
		_drop_draft(false)   # another destination was picked: the draft of the old one is no longer meant
		return
	legs = [GameState.parked_leg()]
	plan = {}
	message = ""


## "Keep current course": drops the draft and shows the course the ship is following again, with its
## destination and target orbit.
func _on_keep_course() -> void:
	_drop_draft(true)


func _drop_draft(show_followed_course: bool) -> void:
	if GameState.saved_plan.is_empty():
		return
	plan = GameState.saved_plan
	GameState.saved_plan = {}
	if show_followed_course:
		var index := destination_ids.find(str(plan["target_id"]))
		if index >= 0:
			target_picker.select(index)
		GameState.target_orbits[str(plan["target_id"])] = plan["target_orbit"]
		_sync_aero()
		_sync_orbit_control()
		message = "Keeping the current course."


func _on_plan() -> void:
	if not plan.is_empty() and not plan["committed"]:
		_cancel_plan()
		return
	# A new orbit around the body the ship is at starts from the current orbit, not from an earlier choice.
	var here := GameState.ship_body() if GameState.ship_body() != "" else GameState.ship_frame()
	if _selected_target_id() == here and not GameState.ship_in_transit():
		GameState.target_orbits.erase(here)
	_make_plan(false)


## Cancel: forgets the orbit chosen for this destination and closes the planner. A course change in flight
## goes back to showing the course the ship is following.
func _cancel_plan() -> void:
	GameState.target_orbits.erase(str(plan["target_id"]))
	if not GameState.saved_plan.is_empty():
		_drop_draft(true)
		return
	plan = {}
	var parked := GameState.parked_leg()
	if not parked.is_empty():
		legs = [parked]
	message = ""


## Plans the next departure with the player's target orbit for the chosen destination. With keep_aero_off an
## earlier decision to switch aerobraking off is kept.
func _make_plan(keep_aero_off: bool) -> void:
	var target_id := _selected_target_id()
	var aero_was_off: bool = keep_aero_off and not plan.is_empty() and not bool(plan.get("aero", {}).get("enabled", false))
	var result: Dictionary
	if GameState.ship_in_transit():
		# A course change: the plan the ship is following stays saved until the new one is launched.
		if GameState.saved_plan.is_empty() and not plan.is_empty() and plan["committed"]:
			GameState.saved_plan = plan
		result = CourseChange.make_plan(target_id, time_jd + MIN_LAUNCH_DELAY_DAYS, GameState.target_orbits.get(target_id, {}))
	else:
		var parked := GameState.parked_leg()
		if parked.is_empty():
			return
		legs = [parked]
		result = MissionPlanner.make_plan(str(parked["parent"]), parked["segment"], target_id,
				time_jd + MIN_LAUNCH_DELAY_DAYS, GameState.target_orbits.get(target_id, {}))
	paused = true
	if result.has("error"):
		plan = GameState.saved_plan if not GameState.saved_plan.is_empty() else {}
		GameState.saved_plan = {}
		message = str(result["error"])
	else:
		plan = result
		message = ""
		if aero_was_off and plan["aero"]["available"]:
			AeroBraking.apply(plan, false, int(plan["aero"]["n"]), float(plan["aero"]["h_km"]))
		_sync_aero()
		_sync_orbit_control()


## The player changed the target orbit: remember it for this destination and plan again.
func _on_target_orbit_changed(rp_alt_km: float, ra_alt_km: float, offset_deg: float) -> void:
	if plan.is_empty() or plan["committed"]:
		return
	GameState.target_orbits[_selected_target_id()] = {"rp_alt_km": rp_alt_km, "ra_alt_km": ra_alt_km, "offset_deg": offset_deg}
	_make_plan(true)


func _sync_orbit_control() -> void:
	if plan.is_empty():
		return
	var target: Dictionary = bodies[plan["target_id"]]
	var orbit: Dictionary = plan["target_orbit"]
	orbit_control.setup(float(target["radius_km"]), float(target["radius_km"]) * 100.0)
	orbit_control.set_orbit(float(orbit["rp_alt_km"]), float(orbit["ra_alt_km"]), float(orbit["offset_deg"]))


## Launches; if the plan will end badly (crash, burn-up, too slow, escape) the player must confirm first.
func _on_launch() -> void:
	_confirm_then(_do_launch)


func _confirm_then(action: Callable) -> void:
	if plan.is_empty():
		return
	if plan["committed"] or str(plan.get("outcome", "ok")) == "ok":
		action.call()
		return
	for connection in launch_dialog.confirmed.get_connections():
		launch_dialog.confirmed.disconnect(connection["callable"])
	launch_dialog.dialog_text = "%s\n\nLaunch anyway?" % str(plan["outcome_text"])
	launch_dialog.confirmed.connect(action)
	# Size the popup to the window: wrapped text, never wider than the screen.
	var window_size := get_viewport().get_visible_rect().size
	var width := int(minf(520.0, window_size.x - 40.0))
	launch_dialog.min_size = Vector2i(width, 0)
	launch_dialog.size = Vector2i(width, 0)
	launch_dialog.popup_centered(Vector2i(width, 0))


## Stops a launch before the departure burn. The plan stays as it is, the launch cost is refunded, and the
## planner controls come back, so the player can change what they want and launch again. For a course change
## the ship goes back to the plan it was following.
func _on_abort() -> void:
	if plan.is_empty() or not plan["committed"] or plan["departure_done"]:
		return
	plan["committed"] = false
	paused = true
	warp_index = 0
	if plan.get("midflight", false):
		legs = plan["legs_before"]
		GameState.saved_plan = plan["replaces"]
	else:
		GameState.budget_eur += GameState.mission_cost_eur
		legs = [legs[0]]
	_sync_aero()
	_sync_orbit_control()
	message = "Launch aborted. The plan is unchanged: change what you like and press Launch again."


func _do_launch() -> void:
	if plan.is_empty():
		return
	var transfer_leg := {"parent": plan["frame"], "segment": plan["transfer_segment"], "t_start": plan["t_dep"],
			"label": ("Orbit change around %s" if plan.get("orbit_change", false) else "Transfer orbit to %s") % plan["target_name"],
			"kind": "transfer"}
	plan["committed"] = true
	if plan.get("midflight", false):
		# A course change: the flight so far stays, the old plan's later legs are replaced. No launch cost.
		plan["legs_before"] = legs.duplicate()
		plan["replaces"] = GameState.saved_plan
		GameState.saved_plan = {}
		var kept: Array = []
		for leg in legs:
			if float(leg["t_start"]) < float(plan["t_dep"]):
				kept.append(leg)
		legs = kept
		legs.append(transfer_leg)
	else:
		GameState.budget_eur -= GameState.mission_cost_eur
		legs = [legs[0], transfer_leg]
	legs.append_array(plan["capture_legs"])


## Launches (commits the plan) if that has not happened yet, jumps to just before the departure burn
## and resumes time in real time.
func _on_skip() -> void:
	if plan.is_empty():
		return
	if not plan["committed"]:
		_confirm_then(func() -> void:
			_do_launch()
			_skip_to_departure())
		return
	_skip_to_departure()


func _skip_to_departure() -> void:
	time_jd = maxf(time_jd, float(plan["t_dep"]) - SKIP_LEAD_DAYS)
	paused = false
	warp_index = 0


func _on_refuel() -> void:
	var amount := GameState.refuel()
	message = "Refuelled %s kg." % GameState.thousands(amount) if amount > 0.0 else "Nothing to refuel."


## Copies the plan's aerobraking settings to the controls.
func _sync_aero() -> void:
	syncing_aero = true
	var aero: Dictionary = plan.get("aero", {})
	if aero.get("available", false):
		var enabled: bool = aero["enabled"]
		aero_check.set_pressed_no_signal(enabled)
		passes_slider.set_value_no_signal(float(aero["n"]))
		altitude_slider.min_value = float(aero["band_lo"])
		altitude_slider.max_value = maxf(float(aero["band_hi"]), float(aero["band_lo"]) + 0.1)
		altitude_slider.set_value_no_signal(float(aero["h_km"]))
		altitude_spin.min_value = float(aero["h_min_km"])
		altitude_spin.max_value = float(aero["h_max_km"])
		altitude_spin.set_value_no_signal(float(aero["h_km"]))
		passes_label.text = "Passes: %d" % int(aero["n"])
		# Without aerobraking the passes and the altitude do not apply: grey them out.
		passes_slider.editable = enabled
		altitude_slider.editable = enabled
		altitude_spin.editable = enabled
		altitude_minus.disabled = not enabled
		altitude_plus.disabled = not enabled
		passes_label.modulate = Color(1, 1, 1, 1.0 if enabled else 0.4)
		altitude_label.modulate = passes_label.modulate
	syncing_aero = false


func _nudge_altitude(delta_km: float) -> void:
	_apply_aero(aero_check.button_pressed, int(passes_slider.value), altitude_spin.value + delta_km, true)


func _apply_aero(enabled: bool, passes: int, altitude_km: float, recenter := false) -> void:
	if plan.is_empty() or plan["committed"]:
		return
	AeroBraking.apply(plan, enabled, passes, clampf(altitude_km, float(plan["aero"]["h_min_km"]), float(plan["aero"]["h_max_km"])), recenter)
	_sync_aero()


## A new number of passes: find the periapsis altitude that gives the target orbit with that many passes.
func _on_passes_changed() -> void:
	if plan.is_empty() or plan["committed"] or not plan["aero"]["available"]:
		return
	var n := int(passes_slider.value)
	var h := AeroBraking.find_altitude(plan["aero"]["ctx"], n, AeroBraking.SEARCH_DT)
	if h < 0.0:
		message = "%d passes cannot slow the ship enough, even at the lowest periapsis." % n
		h = float(plan["aero"]["h_min_km"])
	_apply_aero(true, n, h, true)


## Back to the planner's suggestion.
func _on_aero_auto() -> void:
	if plan.is_empty() or plan["committed"] or not plan["aero"]["available"]:
		return
	var suggestion := AeroBraking.suggest(plan["aero"]["ctx"])
	if suggestion.is_empty():
		message = "The planner has no safe aerobraking suggestion for this shield."
		_apply_aero(false, int(passes_slider.value), altitude_slider.value)
	else:
		_apply_aero(true, int(suggestion["n"]), float(suggestion["h_km"]), true)


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
	if not GameState.lost_event.is_empty() and not is_instance_valid(lost_overlay):
		var event: Dictionary = GameState.lost_event
		GameState.lost_event = {}
		lost_overlay = ShipLostOverlay.new()
		add_child(lost_overlay)
		lost_overlay.play(str(event["text"]), bool(event["burn"]))
	if picker_origin != _picker_key():
		_fill_destinations(_selected_target_id())
	_update_ui()
	queue_redraw()


func _update_ui() -> void:
	var in_transit := _in_transit()
	var burn_pending: bool = not plan.is_empty() and plan["committed"] and not plan["departure_done"]
	plan_button.disabled = destination_ids.is_empty() or burn_pending
	plan_button.text = "Cancel" if not plan.is_empty() and not plan["committed"] else "Plan"
	target_picker.disabled = destination_ids.is_empty() or burn_pending
	keep_button.visible = not GameState.saved_plan.is_empty()
	var draft_bad: bool = not plan.is_empty() and not plan["committed"] and str(plan.get("outcome", "ok")) != "ok"
	var warnings: PackedStringArray = []
	if draft_bad:
		warnings.append(str(plan["outcome_text"]))
	if not plan.is_empty() and not plan["committed"] and str(plan.get("warning", "")) != "":
		warnings.append(str(plan["warning"]))
	warning_label.text = "Warning: " + "\nWarning: ".join(warnings) if not warnings.is_empty() else ""
	warning_label.visible = not warnings.is_empty()
	var affordable := not plan.is_empty() and _plan_dv_total() <= GameState.dv_left_kms() + 0.00001
	var window_open := not plan.is_empty() and time_jd < float(plan["t_dep"]) + LATE_LAUNCH_DAYS
	var funded: bool = GameState.budget_eur >= GameState.mission_cost_eur or (not plan.is_empty() and plan.get("midflight", false))
	launch_button.disabled = plan.is_empty() or plan["committed"] or not affordable or not window_open or not funded
	skip_button.disabled = plan.is_empty() or not window_open or not affordable or (not funded and not plan["committed"])
	abort_button.visible = not plan.is_empty() and plan["committed"] and not plan["departure_done"]
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
	aero_row.visible = planner_row.visible and not plan.is_empty() and not plan["committed"] \
			and bool(plan.get("aero", {}).get("available", false))
	orbit_row.visible = planner_row.visible and not plan.is_empty() and not plan["committed"]
	shield_button.visible = at_yard and GameState.shield_used_mj_m2 > 0.0
	shield_button.disabled = GameState.shield_replace_problem() != ""
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
			GameState.thousands(GameState.ship_fuel_capacity_kg),
			GameState.dv_for_fuel(GameState.ship_fuel_capacity_kg)]


func _aero_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	var aero: Dictionary = plan.get("aero", {})
	if not aero.get("available", false):
		if aero.get("message", "") != "":
			lines.append(str(aero["message"]))
	elif not aero["enabled"]:
		lines.append("Aerobraking off: propulsive capture. %s" % aero.get("message", ""))
	elif aero["outcome"] != "ok":
		lines.append("Aerobraking: %d passes at %.1f km. Heat %.0f MJ/m2" % [int(aero["n"]), float(aero["h_km"]), float(aero["heat"])])
	else:
		lines.append("Aerobraking: %d passes at %.1f km, %s in total, final burns %.0f m/s" % [
				int(aero["n"]), float(aero["h_km"]), _span_text(float(aero["days"])), float(aero["final_dv"]) * 1000.0])
		lines.append("Heat %.0f MJ/m2 | peak %.1f g | peak heating %.1f MW/m2" % [
				float(aero["heat"]), float(aero["peak_g"]), float(aero["peak_flux"])])
	if aero.get("enabled", false) and aero.has("shield_after"):
		lines.append("Heat shield capacity: %.0f%% now, %.0f%% after the passes" % [
				float(aero["shield_before"]) * 100.0, float(aero["shield_after"]) * 100.0])
		if aero["outcome"] == "ok":
			if float(aero["shield_after"]) <= 0.0 or float(aero["heat"]) > float(aero["shield_before"]) * AeroBraking.shield_capacity_mj_m2(GameState.ship_shield_cm):
				lines.append("Warning: the heat shield will be used up and the ship will be damaged.")
			elif float(aero["peak_g"]) > AeroBraking.G_LIMIT:
				lines.append("Warning: the deceleration is above the limit and the ship will be damaged.")
			elif float(aero["heat"]) > AeroBraking.HEAT_MARGIN * float(aero["shield_before"]) * AeroBraking.shield_capacity_mj_m2(GameState.ship_shield_cm):
				lines.append("The shield is nearly used up.")
	if str(plan.get("outcome", "ok")) != "ok":
		lines.append("Warning: " + str(plan["outcome_text"]))
	if str(plan.get("warning", "")) != "":
		lines.append("Warning: " + str(plan["warning"]))
	return lines


func _info_text() -> String:
	var lines: PackedStringArray = []
	lines.append("%s: %s" % [GameState.ship_name, legs[_leg_index_at(time_jd)]["label"]])
	lines.append("Fuel: %s" % _fuel_text())
	lines.append("Heat shield: %.0f of %.0f MJ/m2 used | Health: %.0f%%" % [GameState.shield_used_mj_m2,
			AeroBraking.shield_capacity_mj_m2(GameState.ship_shield_cm), GameState.ship_health * 100.0])
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
	if plan.get("orbit_change", false):
		lines.append("Plan: new orbit around %s" % plan["target_name"])
	elif plan.get("midflight", false):
		lines.append("Plan: course change to %s" % plan["target_name"])
	else:
		lines.append("Plan: %s to %s" % [bodies[plan["origin_id"]]["name"], plan["target_name"]])
	lines.append("Departure: %s (in %s)" % [GameState.date_text(float(plan["t_dep"])), _span_text(float(plan["t_dep"]) - time_jd)])
	lines.append("Arrival: %s (flight %s)" % [GameState.date_text(float(plan["t_arr"])), _span_text(float(plan["flight_days"]))])
	if not plan["committed"] and not plan.get("midflight", false):
		lines.append("Launch cost: %s EUR" % GameState.thousands(GameState.mission_cost_eur))
	lines.append("Burns: departure %.2f + capture %.2f = %.2f km/s" % [
			float(plan["dv_departure"]), float(plan["dv_arrival"]), _plan_dv_total()])
	if float(plan.get("dv_circularize", 0.0)) > 0.0:
		lines.append("The periapsis of the parking orbit points the wrong way for this departure: circularising first (%.0f m/s, included in the departure burn)." % (float(plan["dv_circularize"]) * 1000.0))
	lines.append_array(_aero_lines())
	if message != "":
		lines.append(message)
	if not plan["committed"] and _plan_dv_total() > GameState.dv_left_kms():
		lines.append("Not enough fuel for this mission. Refuel, or build a stronger ship on the ship design screen.")
	elif plan["committed"]:
		lines.append(("Mission launched (the departure burn can still be aborted)." if not plan["departure_done"] else "Mission launched.") if time_jd < float(plan["t_arr"]) else "Arrived at %s." % plan["target_name"])
	elif time_jd >= float(plan["t_dep"]) + LATE_LAUNCH_DAYS:
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
