class_name GameState
extends RefCounted
## The shared state of the running game, kept in static variables so that it survives switching
## between screens (scenes) and needs no autoload. Every screen reads and writes it directly:
## the game clock, the loaded data, the ship and its mission, the facilities and the budget.

const DATA_PATH := "res://data/bodies.json"
const FACILITIES_PATH := "res://data/facilities.json"
const SETTINGS_PATH := "res://data/settings.json"
const DESIGN_PATH := "user://ship_design.json"  # written by the ship design screen
const DEFAULT_SHIP_DV_KMS := 10.0
const DEFAULT_SHIP_PROPELLANT_KG := 120000.0
const DEFAULT_SHIP_VE_MS := 3900.0   # effective exhaust velocity of the default ship
const DEFAULT_SHIP_PAYLOAD_KG := 5000.0
const DEFAULT_SHIP_THRUST_KN := 1000.0
const TINY_SOI_RADII := 5.0         # a sphere of influence smaller than this many body radii counts as none (Phobos, Deimos)
const CONTEXT_HYSTERESIS := 1.05   # the ship leaves a context at this multiple of its radius (and enters it at 1.0)
const VIEW_FILL := 0.9          # share of the half screen width that the widest orbit of a view fills
static var _last_approach_diag := ""

## Greatest distance (km) by which a transfer may miss the centre of its target for the curved approach to be drawn.
const APPROACH_MAX_MISS_KM := 1.0e6
const ROUTE_FADE_LENGTHS := 6.0  # the jump at escape / insertion fades out over this many times its size
const DEFAULT_SHIELD_CM := 15.0
const AERO_WARP_INDEX := 1   # time flow drops to this (1 min/s) when the ship reaches the upper atmosphere
const WARP_STEPS := [1.0 / 86400.0, 1.0 / 1440.0, 1.0 / 24.0, 1.0, 10.0, 100.0, 1000.0]  # game days per real second
const WARP_LABELS := ["real time", "1 min/s", "1 h/s", "1 day/s", "10 days/s", "100 days/s", "1000 days/s"]

# Data (loaded once from the data files).
static var data_loaded := false
static var bodies: Dictionary = {}          # id -> body dictionary
static var children: Dictionary = {}        # id -> array of child ids
static var facility_types: Dictionary = {}  # id -> facility type dictionary
static var start_facilities: Array = []
static var start_budget_eur := 0.0
static var propellant_price_eur_per_kg := 0.0
static var mission_cost_eur := 0.0
static var shield_cost_eur_per_kg := 0.0
static var stop_reason := ""   # why the time flow was slowed down last (shown for a while, to find odd stops)
static var stop_ms := 0
static var rotation_max_deg_s := 180.0     # turning rate of a light ship ...
static var rotation_min_deg_s := 10.0      # ... and of a heavy one (log scale between the two masses)
static var rotation_light_mass_kg := 5000.0
static var rotation_heavy_mass_kg := 100000.0
static var heat_effect_min_mw_m2 := 0.1    # peak heat flux where the heating effect just shows ...
static var heat_effect_max_mw_m2 := 20.0   # ... and where it is at full strength (logarithmic in between)
static var start_jd := 0.0

# Game clock.
static var initialized := false
static var time_jd := 0.0
static var paused := true
static var warp_index := 0

# The ship and its mission. legs: {parent, segment, t_start, label, kind}; kind is "orbit" or "transfer".
# The first leg is the orbit the ship is in when the mission is planned.
static var legs: Array = []
static var plan: Dictionary = {}
## While the player plans a course change in flight, plan is the draft and this is the plan that keeps running.
static var saved_plan: Dictionary = {}
## The target orbit the player chose for each destination body: {rp_alt_km, ra_alt_km, offset_deg}.
static var target_orbits: Dictionary = {}
static var message := ""
static var ship_lost := false   # true once the ship has been lost: the screen draws no ship and no course
static var lost_event: Dictionary = {}   # {text, burn}: set when the ship is lost; the screen shows it and clears it
static var ship_name := "Ship"
static var cargo: Array = []   # facility type ids of the kits the ship carries

# The ship's tanks: a delta-v tank. The design gives a capacity in kg of propellant and in km/s; the
# two are linked by the rocket equation for an equivalent single stage (effective exhaust velocity and
# dry mass), so burning delta-v uses up propellant mass and refuelling restores it.
static var ship_dv_kms := DEFAULT_SHIP_DV_KMS           # capacity
static var ship_payload_kg := DEFAULT_SHIP_PAYLOAD_KG   # cargo capacity
static var ship_fuel_capacity_kg := DEFAULT_SHIP_PROPELLANT_KG
static var ship_ve_ms := DEFAULT_SHIP_VE_MS
static var ship_thrust_kn := DEFAULT_SHIP_THRUST_KN   # thrust of the first stage; sets how long burns take
static var ship_dry_kg := DEFAULT_SHIP_PROPELLANT_KG / (exp(DEFAULT_SHIP_DV_KMS * 1000.0 / DEFAULT_SHIP_VE_MS) - 1.0) - DEFAULT_SHIP_PAYLOAD_KG
# The heat shield: thickness, area, and the heat load (MJ/m2) it has already absorbed. Health drops when a
# pass overloads the shield or the g limit.
static var ship_shield_cm := DEFAULT_SHIELD_CM
static var ship_shield_area_m2 := AeroBraking.area_for_mass(DEFAULT_SHIP_PROPELLANT_KG * (1.0 + 1.0 / (exp(DEFAULT_SHIP_DV_KMS * 1000.0 / DEFAULT_SHIP_VE_MS) - 1.0)))
static var shield_used_mj_m2 := 0.0
static var ship_health := 1.0
static var ship_fuel_kg := -1.0                         # current propellant; negative = not set yet
static var ship_burned := false                         # true once the ship has used any delta-v
static var ship_dv_source := "default value; design a ship on the ship design screen"
static var ship_context_id := ""                        # the body whose space the ship is in (see update_ship_context); "" = not worked out yet

# Facilities: id -> state dictionary (type values plus body, name, stock_kg and last_jd).
static var facilities: Dictionary = {}
static var budget_eur := 0.0

# Per-screen choices that are kept when switching screens.
static var view_frame_index := 0
static var view_target_id := "moon"


## Loads the data once and makes sure the game has been started. Returns false if the data is missing.
static func load_data() -> bool:
	if not data_loaded:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Cannot read %s (on Android, add *.json to the export filter)." % DATA_PATH)
			return false
		start_jd = float(parsed["game_start"]["jd"])
		bodies = {}
		children = {}
		for body in parsed["bodies"]:
			bodies[body["id"]] = body
			children[body["id"]] = []
		for id in bodies:
			var parent_id: Variant = bodies[id]["parent"]
			if parent_id != null:
				children[parent_id].append(id)
		var facility_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FACILITIES_PATH))
		facility_types = {}
		if typeof(facility_data) == TYPE_DICTIONARY:
			for type in facility_data["types"]:
				facility_types[type["id"]] = type
		var settings: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if typeof(settings) == TYPE_DICTIONARY:
			start_budget_eur = float(settings["start_budget_eur"])
			start_facilities = settings["start_facilities"]
			propellant_price_eur_per_kg = float(settings.get("propellant_price_eur_per_kg", 0.0))
			mission_cost_eur = float(settings.get("mission_cost_eur", 0.0))
			shield_cost_eur_per_kg = float(settings.get("shield_cost_eur_per_kg", 0.0))
			rotation_max_deg_s = float(settings.get("rotation_rate_max_deg_s", rotation_max_deg_s))
			rotation_min_deg_s = float(settings.get("rotation_rate_min_deg_s", rotation_min_deg_s))
			rotation_light_mass_kg = float(settings.get("rotation_light_mass_kg", rotation_light_mass_kg))
			rotation_heavy_mass_kg = float(settings.get("rotation_heavy_mass_kg", rotation_heavy_mass_kg))
			heat_effect_min_mw_m2 = float(settings.get("heat_effect_min_mw_m2", heat_effect_min_mw_m2))
			heat_effect_max_mw_m2 = float(settings.get("heat_effect_max_mw_m2", heat_effect_max_mw_m2))
		data_loaded = true
	if not initialized:
		reset_mission()
	load_ship_design()
	return true


## Back to the start: time paused at the start date, the ship in a parking orbit around Earth, no plan,
## the starting facilities and budget.
static func reset_mission() -> void:
	initialized = true
	time_jd = start_jd
	paused = true
	warp_index = 0
	plan = {}
	saved_plan = {}
	target_orbits = {}
	message = ""
	cargo = []
	var earth_gm := float(bodies["earth"]["gm_km3_s2"])
	var radius := float(bodies["earth"]["radius_km"]) + float(bodies["earth"]["default_orbit_altitude_km"])
	var parking := TransferPlanner.circular_segment(radius, earth_gm, start_jd, 0.0)
	legs = [{"parent": "earth", "segment": parking, "t_start": start_jd, "label": "Orbit around Earth", "kind": "orbit"}]
	ship_burned = false
	ship_fuel_kg = ship_fuel_capacity_kg
	shield_used_mj_m2 = 0.0
	ship_health = 1.0
	lost_event = {}
	ship_lost = false
	budget_eur = start_budget_eur
	facilities = {}
	for entry in start_facilities:
		create_facility(str(entry["type"]), str(entry["body"]))


## Reads the ship's name, delta-v and tank data from the ship design screen's saved design.
static func load_ship_design() -> void:
	if FileAccess.file_exists(DESIGN_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("total_dv_ms"):
			ship_dv_kms = float(parsed["total_dv_ms"]) / 1000.0
			ship_dv_source = "from the ship design screen"
			ship_name = str(parsed.get("name", ship_name))
			ship_payload_kg = float(parsed.get("payload_kg", ship_payload_kg))
			if parsed.has("propellant_kg") and parsed.has("ve_eff_ms"):
				ship_fuel_capacity_kg = float(parsed["propellant_kg"])
				ship_ve_ms = float(parsed["ve_eff_ms"])
				# The empty ship; older saved designs only have the mass with the full payload.
				ship_dry_kg = float(parsed.get("dry_empty_kg", maxf(float(parsed["dry_eff_kg"]) - ship_payload_kg, 100.0)))
			ship_thrust_kn = float(parsed.get("thrust_kn", ship_thrust_kn))
			ship_shield_cm = float(parsed.get("shield_cm", ship_shield_cm))
			ship_shield_area_m2 = float(parsed.get("shield_area_m2", ship_shield_area_m2))
	# Until the ship has used any fuel the tanks are full; afterwards a new design can only lower the level.
	if not ship_burned or ship_fuel_kg < 0.0:
		ship_fuel_kg = ship_fuel_capacity_kg
	else:
		ship_fuel_kg = minf(ship_fuel_kg, ship_fuel_capacity_kg)
	# Kits that no longer fit into a smaller payload are taken off the ship and refunded.
	while not cargo.is_empty() and cargo_mass_kg() > ship_payload_kg:
		var type_id: String = cargo.pop_back()
		budget_eur += float(facility_types[type_id]["kit"]["cost_eur"])


## True for a body with a surface to lift off from (everything but the Sun).
static func has_hard_surface(body_id: String) -> bool:
	return bodies.has(body_id) and str(bodies[body_id]["type"]) != "star"


## Gravity at the surface of a body (m/s2).
static func surface_gravity_ms2(body_id: String) -> float:
	return ShipCalc.surface_gravity_ms2(float(bodies[body_id]["gm_km3_s2"]), float(bodies[body_id]["radius_km"]))


## Whether the ship can lift off from the surface of a body: its first stage must give a thrust-to-weight ratio of at least
## ShipCalc.LIFTOFF_MIN_TWR there, at the ship's mass with the propellant it has now. (Nothing in the game departs from a
## surface yet; the mission planner will use this when it does.)
static func can_lift_off(body_id: String) -> bool:
	if not has_hard_surface(body_id):
		return false
	var mass := dry_mass_kg() + maxf(ship_fuel_kg, 0.0)
	return ShipCalc.liftoff_twr(ship_thrust_kn, mass, surface_gravity_ms2(body_id)) >= ShipCalc.LIFTOFF_MIN_TWR


## The mass of the ship without propellant: the empty ship plus the cargo it carries. This is the mass the
## rocket equation works with, so loading a kit lowers the delta-v and deploying it raises it again.
static func dry_mass_kg() -> float:
	return ship_dry_kg + cargo_mass_kg()


## Propellant mass (kg) that corresponds to a delta-v (km/s) for the equivalent single stage.
static func fuel_for_dv(dv_kms: float) -> float:
	return dry_mass_kg() * (exp(dv_kms * 1000.0 / ship_ve_ms) - 1.0)


## Delta-v (km/s) that a propellant mass (kg) gives.
static func dv_for_fuel(fuel_kg: float) -> float:
	return ship_ve_ms * log(1.0 + fuel_kg / dry_mass_kg()) / 1000.0


static func dv_left_kms() -> float:
	return dv_for_fuel(ship_fuel_kg)


## How long (game days) a burn of dv_kms takes with the ship's thrust (at least one second).
static func burn_days(dv_kms: float) -> float:
	if dv_kms <= 0.0 or ship_thrust_kn <= 0.0:
		return 0.0
	var mass_before := dry_mass_kg() + maxf(ship_fuel_kg, 0.0)
	var used_kg := mass_before * (1.0 - exp(-dv_kms * 1000.0 / ship_ve_ms))
	var seconds := used_kg * ship_ve_ms / (ship_thrust_kn * 1000.0)
	return maxf(seconds, 1.0) / 86400.0


## Uses up delta-v from the tanks.
static func apply_burn(dv_kms: float) -> void:
	ship_burned = true
	ship_fuel_kg = fuel_for_dv(maxf(dv_left_kms() - dv_kms, 0.0))


## The time (jd) when everything of a plan is over: the end of the plan and the end of the last burn or pass of its
## capture (the burns are centred on the start of their leg, so the plan is not over in the middle of one).
static func _plan_finish_time(a_plan: Dictionary) -> float:
	var finish := float(a_plan.get("t_end", a_plan["t_arr"]))
	for leg: Dictionary in a_plan.get("capture_legs", []):
		finish = maxf(finish, float(leg["t_start"]) + 0.5 * float(leg.get("morph_days", 0.0)))
	return finish


## The burn windows of a plan: [{"t0", "span", "weight"}] for the departure burn or the propulsive burns of the
## capture. The delta-v of the arrival is shared among them by their duration.
static func _burn_windows(a_plan: Dictionary, departure: bool) -> Array:
	var windows: Array = []
	if departure:
		for leg: Dictionary in legs:
			if leg["kind"] == "transfer" and absf(float(leg["t_start"]) - float(a_plan["t_dep"])) < 1.0e-9:
				var span := float(leg.get("morph_days", 0.0))
				windows.append({"t0": float(a_plan["t_dep"]) - 0.5 * span, "span": span, "weight": 1.0})
				break
		return windows
	var total := 0.0
	for leg: Dictionary in a_plan.get("capture_legs", []):
		var span := float(leg.get("morph_days", 0.0))
		if span > 0.0 and not bool(leg.get("is_pass", false)):
			windows.append({"t0": float(leg["t_start"]) - 0.5 * span, "span": span, "weight": span})
			total += span
	for window: Dictionary in windows:
		window["weight"] = float(window["weight"]) / total
	return windows


## Takes the propellant of the burns out of the tanks while they run, not all at once: the share of each burn that
## is done by now is used up. finish: the plan is over, so everything that is left is used up. Generic for every
## plan and every target.
static func _burn_fuel_gradually(a_plan: Dictionary, finish := false) -> void:
	for kind in ["dv_departure", "dv_arrival"]:
		var windows := _burn_windows(a_plan, kind == "dv_departure")
		var done := 1.0 if finish else 0.0
		if not finish:
			if windows.is_empty():
				done = 1.0 if (kind == "dv_departure" and time_jd >= float(a_plan["t_dep"])) else 0.0
			else:
				for window: Dictionary in windows:
					done += float(window["weight"]) * clampf((time_jd - float(window["t0"])) / maxf(float(window["span"]), 1.0e-9), 0.0, 1.0)
		var key: String = kind + "_applied"
		var wanted := float(a_plan[kind]) * clampf(done, 0.0, 1.0)
		var applied := float(a_plan.get(key, 0.0))
		if wanted > applied:
			apply_burn(wanted - applied)
			a_plan[key] = wanted


# ---------------------------------------------------------------- clock

## Advances the game clock by delta real seconds. On departure and arrival the burns are taken from
## the tanks; on arrival the plan is finished and the time flow drops to real time.
static func advance(delta: float) -> void:
	if not paused:
		var step := delta * float(WARP_STEPS[warp_index])
		var entry := _next_atmosphere_entry()
		var decay_entry := _next_decay_entry(time_jd + step)
		var entry_is_decay := false
		if decay_entry > 0.0 and (entry < 0.0 or decay_entry < entry):
			entry = decay_entry
			entry_is_decay = true
		if warp_index > 0:
			# Stop at the EARLIEST of the events that need a slow warp. Before a burn or an aerobraking pass (the ship
			# starts turning one half-turn time before it) the time flow drops to real time, so the turn and the burn
			# can be watched; the moment the ship gets inside the space of a smaller body only drops it to 1 min/s.
			var stop := -1.0
			var stop_to_real := true
			var reason := ""
			if entry > 0.0 and time_jd + step >= entry:
				stop = entry
				reason = "the ship reaches the atmosphere"
				# The outer limit of the atmosphere of an aerobraking plan only slows the time flow down to 1 min/s;
				# it drops to real time later, before the turn for the pass (the morph window below).
				stop_to_real = entry_is_decay
			var morph_window := _next_morph_window(time_jd + step)
			if not morph_window.is_empty() and (stop < 0.0 or float(morph_window["t_turn"]) < stop):
				stop = float(morph_window["t_turn"])
				reason = "%s: %s" % ["aerobraking pass" if bool(morph_window["is_pass"]) else "burn", str(morph_window["label"])]
			if warp_index > AERO_WARP_INDEX:
				var entry_time := _next_context_entry(time_jd + step)
				if entry_time > 0.0 and (stop < 0.0 or entry_time < stop):
					stop = entry_time
					stop_to_real = false
					reason = "the ship enters the space of a smaller body"
			if stop > 0.0:
				time_jd = maxf(time_jd, stop)
				stop_reason = reason
				stop_ms = Time.get_ticks_msec()
				warp_index = 0 if stop_to_real else AERO_WARP_INDEX
				step = delta * float(WARP_STEPS[warp_index])
		var lost_at := _loss_time()
		if lost_at > 0.0 and time_jd + step >= lost_at:
			time_jd = maxf(time_jd, lost_at)   # stop exactly where the ship blows up
		else:
			time_jd += step
	update_ship_context(time_jd)
	_decay_orbit()
	var running := running_plan()
	if not running.is_empty() and running["committed"]:
		_burn_fuel_gradually(running)
		if not running["departure_done"]:
			# The departure can be aborted until the burn starts (before that no propellant has been used).
			var dep_windows := _burn_windows(running, true)
			var burn_start := float(dep_windows[0]["t0"]) if not dep_windows.is_empty() else float(running["t_dep"])
			if time_jd >= burn_start:
				running["departure_done"] = true
		var lost_at_end := _loss_time()
		var end_time := lost_at_end if lost_at_end > 0.0 else _plan_finish_time(running)
		if time_jd >= end_time:
			var aero: Dictionary = running.get("aero", {})
			if str(running.get("outcome", "ok")) == "flyby":
				# Too fast to be captured, and no burn could capture it: the ship flies past and goes on around the Sun.
				message = "Fly-by of %s: the ship was too fast to be captured and flies on around the Sun." % running["target_name"]
				if running.get("flyby_propulsive", false):
					message = "Fly-by of %s: the propellant was not enough for the capture burn, so the ship flies on around the Sun. Plan a course change to try again." % running["target_name"]
				if aero.get("enabled", false):
					message += " " + _take_aerobraking_effects(aero)
			elif str(running.get("outcome", "ok")) != "ok":
				# The planner only warned about this; now it happens. (Placeholder rules: the ship is wrecked.)
				ship_health = 0.0
				message = _lost_text(str(running["outcome"]), str(running["target_name"]))
				_lose_ship(message, str(running["outcome"]) != "crash" and bodies[str(running["target_id"])].get("atmosphere") is Dictionary)
				warp_index = 0
			else:
				_burn_fuel_gradually(running, true)
				message = "Arrived at %s." % running["target_name"]
				if aero.get("enabled", false):
					message += " " + _take_aerobraking_effects(aero)
			plan = {}
			saved_plan = {}
	_update_facilities()


## One line about the ship's current orbit for the top bar: periapsis and apoapsis altitude, the angle of the
## axis of the orbit, the current altitude and the speed relative to the body (the airspeed while the ship is
## in the atmosphere).
static func orbit_status_text() -> String:
	if ship_lost:
		return "Ship lost."
	var leg: Dictionary = legs[leg_index_at(time_jd)]
	if leg["kind"] == "transfer":
		# On the way, but inside the local view of another body (leaving or approaching it): the altitude and the speed
		# relative to that body, not the numbers of the transfer orbit around the Sun.
		var near_id := smallest_view(time_jd)
		if near_id != str(leg["parent"]) and near_id != "sun":
			var dt := 60.0 / 86400.0
			var near_speed := (ship_rel(near_id, time_jd + dt) - ship_rel(near_id, time_jd - dt)).length() / 120.0
			var near_altitude := ship_rel(near_id, time_jd).length() - float(bodies[near_id]["radius_km"])
			var closing := ship_rel(near_id, time_jd + dt).length() < ship_rel(near_id, time_jd - dt).length()
			var verb := "Approaching " if closing else "Leaving "
			return "%s%s: altitude %s %s | Speed %.2f %s (relative to %s)" % [verb, str(bodies[near_id]["name"]), _km_text(near_altitude),
					UnitFormat.length_unit(), UnitFormat.speed_kms(near_speed), UnitFormat.speed_kms_unit(), str(bodies[near_id]["name"])]
	var frame := str(leg["parent"])
	var body: Dictionary = bodies[frame]
	var segment: Dictionary = leg["segment"]
	var shown := segment
	var morph := morph_at(time_jd)
	if not morph.is_empty() and str(morph["parent"]) == frame:
		shown = morph["segment"]   # while a burn or a pass changes the orbit, show it changing
	var a := float(shown["semi_major_axis_km"])
	var e := float(shown["eccentricity"])
	var radius := float(body["radius_km"])
	var periapsis := a * (1.0 - e) - radius
	var apoapsis := a * (1.0 + e) - radius
	var position_fn := func(t: float) -> Vector2: return Kepler.position_at(segment, t)
	var position: Vector2 = position_fn.call(time_jd)
	var speed := TransferPlanner.velocity_kms(position_fn, time_jd).length()
	var altitude := position.length() - radius
	var speed_name := "Speed"
	if body.get("atmosphere") is Dictionary and altitude < AeroBraking.interface_altitude_km(body["atmosphere"]):
		speed_name = "Airspeed"
	var axis_text := "circular"
	if not OrbitControl.is_circular(periapsis, apoapsis):
		axis_text = "%.0f deg" % fposmod(float(shown["argument_of_periapsis_deg"]), 360.0)
	if leg["kind"] != "transfer" and Kepler.direction(segment) < 0:
		axis_text += ", clockwise"
	var length_unit := UnitFormat.length_unit()
	return "%s: periapsis %s %s | apoapsis %s %s | axis %s | altitude %s %s | %s %.2f %s" % [
			("Orbit around " if leg["kind"] == "orbit" else "Flight around ") + str(body["name"]),
			_km_text(periapsis), length_unit, _km_text(apoapsis), length_unit, axis_text, _km_text(altitude), length_unit,
			speed_name, UnitFormat.speed_kms(speed), UnitFormat.speed_kms_unit()]


## A distance given in km, in the unit of the Units setting (the unit itself is added by the caller).
static func _km_text(value: float) -> String:
	value = UnitFormat.length(value)
	return "%.1f" % value if absf(value) < 10000.0 else thousands(value)


## The plan the ship is actually following: the saved one while a course change is being drafted.
static func running_plan() -> Dictionary:
	return saved_plan if not saved_plan.is_empty() else plan


## The body the ship is flying around or orbiting (the parent of its current leg).
static func ship_frame() -> String:
	return str(legs[leg_index_at(time_jd)]["parent"])


## The next time (jd) the committed ship reaches the upper atmosphere, or -1.
static func _next_atmosphere_entry() -> float:
	var running := running_plan()
	if running.is_empty() or not running["committed"]:
		return -1.0
	var aero: Dictionary = running.get("aero", {})
	if not aero.get("enabled", false):
		return -1.0
	for entry in aero["entry_times"]:
		if float(entry) > time_jd:
			return float(entry)
	return -1.0


# ---------------------------------------------------------------- orbit decay

## The text shown after the ship was lost on arrival (past tense; the planner's own texts speak of the future).
static func _lost_text(outcome: String, target_name: String) -> String:
	match outcome:
		"crash":
			return "The ship crashed into the surface of %s and was lost." % target_name
		"burn_up":
			return "Ship lost: it burned up in the atmosphere of %s because the periapsis of the target orbit was too deep." % target_name
		"too_slow":
			return "Ship lost: it slowed down too much in the atmosphere of %s and could not get out of it again." % target_name
	return "Ship lost: it was too fast to be captured by %s and flew past." % target_name


## When the ship of the running plan blows up (crash or burn-up in the target orbit): the first time it reaches the
## periapsis of the target orbit (the end of the capture is when it would have finished the manoeuvre). -1 if the
## plan does not end in a loss of that kind.
static func _loss_time() -> float:
	var running := running_plan()
	if running.is_empty() or not running["committed"] or ship_lost:
		return -1.0
	if not str(running.get("outcome", "ok")) in ["crash", "burn_up"]:
		return -1.0
	var captures: Array = running.get("capture_legs", [])
	if captures.is_empty():
		return -1.0
	var segment: Dictionary = captures[captures.size() - 1]["segment"]
	var way := float(Kepler.direction(segment))   # (a clockwise segment counts its mean anomaly the other way)
	var to_periapsis_deg := fposmod(-way * float(segment["mean_anomaly_deg"]), 360.0)
	return float(segment["epoch_jd"]) + to_periapsis_deg / absf(float(segment["mean_motion_deg_per_day"]))


## Records that the ship was lost: time stops and the screen shows the loss (with the burning-up animation
## when it happened in an atmosphere).
static func _lose_ship(text: String, burn: bool) -> void:
	lost_event = {"text": text, "burn": burn}
	ship_lost = true
	paused = true

const DECAY_MAX_STEPS := 60       # the decay is simulated in at most this many groups of passes
const DECAY_MAX_PASSES := 20000   # a decay slower than this is ignored


## Prepares leg["decay"] for a parked orbit whose periapsis is inside the atmosphere: the passes through the
## atmosphere, in groups (one simulated pass stands for several similar ones when there are many).
## leg["decay"] = {"steps": [{"t_entry", "t", "ra" (km, radius), "heat", "g", "lost"}], "next": index}
static func _ensure_decay(leg: Dictionary) -> void:
	if leg.has("decay") or leg["kind"] != "orbit":
		return
	leg["decay"] = {"steps": [], "next": 0}
	var body: Dictionary = bodies[str(leg["parent"])]
	if not (body.get("atmosphere") is Dictionary):
		return
	var atmosphere: Dictionary = body["atmosphere"]
	var segment: Dictionary = leg["segment"]
	var a := float(segment["semi_major_axis_km"])
	var e := float(segment["eccentricity"])
	var radius := float(body["radius_km"])
	var rp := a * (1.0 - e)
	var interface_r := radius + AeroBraking.interface_altitude_km(atmosphere)
	if rp >= interface_r:
		return
	var gm := float(body["gm_km3_s2"])
	var area := ship_shield_area_m2
	var beta := (dry_mass_kg() + ship_fuel_kg) / (AeroBraking.DRAG_COEFFICIENT * area)
	var nose := sqrt(area / PI)
	# First periapsis passage that is still to come.
	var t_start := maxf(time_jd, float(leg["t_start"]))
	var n_rate := float(segment["mean_motion_deg_per_day"])
	var m_deg := float(segment["mean_anomaly_deg"]) + n_rate * (t_start - float(segment["epoch_jd"]))
	var t_pass := t_start + fposmod(-signf(n_rate) * m_deg, 360.0) / absf(n_rate)
	var energy := -gm / (2.0 * a)
	var passes := 0
	var steps: Array = []
	while passes < DECAY_MAX_PASSES and steps.size() < DECAY_MAX_STEPS:
		var h_km := rp - radius
		var result := AeroBraking.simulate_pass(gm, radius, atmosphere, h_km, energy, beta, nose, 4.0)
		var group := maxi(1, int(passes / 20))
		if result.has("crash"):
			steps.append({"t_entry": t_pass - 0.002, "t": t_pass, "ra": 0.0, "heat": 0.0, "g": 0.0, "lost": true})
			break
		var new_energy := float(result["energy"])
		var delta := new_energy - energy
		energy += delta * float(group)
		var half_days := 0.5 * float(result["seconds"]) / 86400.0
		var ra := AeroBraking.apoapsis_from_energy(gm, rp, energy)
		var lost := ra <= interface_r
		var period := 0.0 if ra <= 0.0 else TAU * sqrt(pow(0.5 * (rp + ra), 3.0) / gm) / 86400.0
		var t_group := t_pass + period * float(group - 1)
		steps.append({"t_entry": t_pass - half_days, "t": t_group, "ra": ra,
				"heat": float(result["heat_mj_m2"]) * float(group), "g": float(result["peak_g"]), "lost": lost})
		passes += group
		if lost:
			break
		t_pass = t_group + period
	if not steps.is_empty() and not steps[steps.size() - 1]["lost"] and passes >= DECAY_MAX_PASSES:
		steps.clear()   # decays too slowly to matter
	leg["decay"]["steps"] = steps


## The start of the next pass through the atmosphere of a decaying parked orbit before time jd, or -1.
static func _next_decay_entry(until_jd: float) -> float:
	var leg: Dictionary = legs[leg_index_at(until_jd)]
	if leg["kind"] != "orbit":
		return -1.0
	_ensure_decay(leg)
	var decay: Dictionary = leg["decay"]
	var steps: Array = decay["steps"]
	for i in range(int(decay["next"]), steps.size()):
		var entry := float(steps[i]["t_entry"])
		if entry > time_jd:
			return entry
	return -1.0


## Carries out the passes of the decay that are over: the orbit gets lower, the shield takes the heat, and
## at the end the ship is lost.
static func _decay_orbit() -> void:
	if ship_lost:
		return
	var leg: Dictionary = legs[leg_index_at(time_jd)]
	if leg["kind"] != "orbit":
		return
	_ensure_decay(leg)
	var decay: Dictionary = leg["decay"]
	var steps: Array = decay["steps"]
	var segment: Dictionary = leg["segment"]
	var gm := float(bodies[str(leg["parent"])]["gm_km3_s2"])
	while int(decay["next"]) < steps.size() and float(steps[int(decay["next"])]["t"]) <= time_jd:
		var step: Dictionary = steps[int(decay["next"])]
		decay["next"] = int(decay["next"]) + 1
		var rp := float(segment["semi_major_axis_km"]) * (1.0 - float(segment["eccentricity"]))
		var text := _take_aerobraking_effects({"heat": float(step["heat"]), "peak_g": float(step["g"])})
		if bool(step["lost"]):
			ship_health = 0.0
			message = "Ship lost: the orbit decayed into the atmosphere of %s." % str(bodies[str(leg["parent"])]["name"])
			_lose_ship(message, true)
			warp_index = 0
			return
		var ra := float(step["ra"])
		var a_new := 0.5 * (rp + ra)
		segment["epoch_jd"] = float(step["t"])
		segment["mean_anomaly_deg"] = 0.0
		segment["semi_major_axis_km"] = a_new
		segment["eccentricity"] = (ra - rp) / (ra + rp)
		segment["mean_motion_deg_per_day"] = TransferPlanner.mean_motion_deg_per_day(gm, a_new) * float(Kepler.direction(segment))
		message = "The orbit is decaying: " + text


## How much health (0 to 1) a heat load (MJ/m2) and a peak deceleration (g) take from the ship now: the part of the
## heat the shield cannot take (relative to what is left of it) and the part of the deceleration above the limit.
## The mission planner uses the same numbers for its prediction.
static func aerobraking_damage(heat: float, peak_g: float) -> float:
	var left := shield_left_mj_m2()
	var excess_heat := 0.0
	if heat > left:
		excess_heat = 1.0 if left <= 0.0 else heat / left - 1.0
	var excess_g := maxf(peak_g / AeroBraking.G_LIMIT - 1.0, 0.0)
	return excess_heat + excess_g


## The heat shield as a share of its full capacity: 0 to 1 (a ship without a shield counts as used up).
static func shield_used_share() -> float:
	var capacity := AeroBraking.shield_capacity_mj_m2(ship_shield_cm)
	return 1.0 if capacity <= 0.0 else clampf(shield_used_mj_m2 / capacity, 0.0, 1.0)


## Adds the heat of the aerobraking passes to the shield and damages the ship if the shield or the g
## limit was exceeded. Returns a sentence for the message.
static func _take_aerobraking_effects(aero: Dictionary) -> String:
	var heat := float(aero["heat"])
	var damage := aerobraking_damage(heat, float(aero["peak_g"]))
	var capacity := AeroBraking.shield_capacity_mj_m2(ship_shield_cm)
	shield_used_mj_m2 += heat
	ship_health = maxf(ship_health - damage, 0.0)
	var text := "The ship has no heat shield." if capacity <= 0.0 else "Aerobraking used %.0f%% of the heat shield; %.0f%% of it is left." % [
			100.0 * heat / capacity, 100.0 * (1.0 - shield_used_share())]
	if damage > 0.0:
		text += " The ship was damaged: health is now %.0f%%." % (ship_health * 100.0)
	return text


## Faster: if paused, resumes at the selected rate; otherwise steps up one rate.
## Slower: if running at real time, pauses; otherwise steps down one rate (also while paused).
static func change_warp(step: int) -> void:
	if step > 0:
		if paused:
			paused = false
		else:
			warp_index = mini(warp_index + 1, WARP_STEPS.size() - 1)
	else:
		if not paused and warp_index == 0:
			paused = true
		else:
			warp_index = maxi(warp_index - 1, 0)


static func toggle_pause() -> void:
	paused = not paused


static func date_text(jd: float) -> String:
	return Time.get_datetime_string_from_unix_time(int((jd - 2440587.5) * 86400.0)).replace("T", " ")


## A number with thousands separators, for example 120,000.
static func thousands(value: float) -> String:
	var digits := str(int(round(absf(value))))
	var out := "-" if value < 0.0 else ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


# ---------------------------------------------------------------- facilities

## Creates a facility of a type at a body (at game start, or when a kit is deployed).
static func create_facility(type_id: String, body_id: String) -> Dictionary:
	var state: Dictionary = (facility_types[type_id] as Dictionary).duplicate(true)
	state["type"] = type_id
	state["id"] = "%s_%s" % [type_id, body_id]
	state["body"] = body_id
	state["name"] = "%s on %s" % [state["name"], bodies[body_id]["name"]]
	state["stock_kg"] = float(state.get("start_stock_kg", 0.0))
	state["last_jd"] = time_jd
	facilities[state["id"]] = state
	return state


## Propellant plants produce continuously: output per day is the peak output times the availability
## of the resource on the body times the conversion, up to the storage capacity.
static func _update_facilities() -> void:
	for id in facilities:
		var facility: Dictionary = facilities[id]
		var days := time_jd - float(facility["last_jd"])
		if days <= 0.0:
			continue
		facility["last_jd"] = time_jd
		if facility["kind"] == "propellant_plant":
			facility["stock_kg"] = minf(float(facility["stock_kg"]) + facility_output_per_day(facility) * days,
					float(facility["storage_capacity_kg"]))


## Production per day (kg) of a facility right now (zero for facilities that do not produce).
static func facility_output_per_day(facility: Dictionary) -> float:
	if facility["kind"] != "propellant_plant":
		return 0.0
	var resource: Dictionary = bodies[facility["body"]]["resources"].get(facility["resource"], {})
	return float(facility["peak_output_kg_per_day"]) * float(resource.get("availability", 0.0)) * float(facility["conversion"])


## The facilities at a body.
static func facilities_at(body_id: String) -> Array:
	var result: Array = []
	for id in facilities:
		if facilities[id]["body"] == body_id:
			result.append(facilities[id])
	return result


## The facility of a kind (for example "shipyard") at a body, or an empty dictionary.
static func facility_of_kind(body_id: String, kind: String) -> Dictionary:
	for facility in facilities_at(body_id):
		if facility["kind"] == kind:
			return facility
	return {}


# ---------------------------------------------------------------- the ship's place

## The leg the ship is parked on (an orbit around a body), or an empty dictionary during a transfer.
static func parked_leg() -> Dictionary:
	var leg: Dictionary = legs[leg_index_at(time_jd)]
	return leg if leg["kind"] == "orbit" else {}


## The body the ship is in orbit around, or "" while it is on a transfer.
static func ship_body() -> String:
	var leg := parked_leg()
	return "" if leg.is_empty() else str(leg["parent"])


## True while the ship is on a transfer orbit between bodies.
static func ship_in_transit() -> bool:
	return legs[leg_index_at(time_jd)]["kind"] != "orbit"


## The mission planner is offered in a system that contains a ship that can launch: the ship is in
## orbit around the body in view, or a plan is waiting.
static func planner_available(focus_id: String) -> bool:
	var body := ship_body()
	if body == "":
		return str(legs[leg_index_at(time_jd)]["kind"]) in ["transfer", "aero"]   # a course change can be planned in flight (also on the legs of a capture)
	return body == focus_id or bodies[body]["parent"] == focus_id or not plan.is_empty()


## The ship designer is offered in a system with a shipbuilding facility, when the ship is at it.
static func design_available(focus_id: String) -> bool:
	return ship_body() == focus_id and not facility_of_kind(focus_id, "shipyard").is_empty()


# ---------------------------------------------------------------- heat shield

## Heat load (MJ/m2) the shield can still take.
static func shield_left_mj_m2() -> float:
	return maxf(AeroBraking.shield_capacity_mj_m2(ship_shield_cm) - shield_used_mj_m2, 0.0)


static func shield_mass_kg() -> float:
	return AeroBraking.shield_mass_kg(ship_shield_cm, ship_shield_area_m2)


## Ship mass (kg) after the departure burn, for the aerobraking pass at arrival.
static func ship_mass_after_departure(dv_departure_kms: float) -> float:
	return dry_mass_kg() + fuel_for_dv(maxf(dv_left_kms() - dv_departure_kms, 0.0))


## Why the shield cannot be replaced now ("" if it can).
static func shield_replace_problem() -> String:
	if shield_used_mj_m2 <= 0.0:
		return "The shield is unused."
	if facility_of_kind(ship_body(), "shipyard").is_empty():
		return "Shields are replaced at a shipyard."
	if shield_mass_kg() * shield_cost_eur_per_kg > budget_eur:
		return "Not enough budget for a new shield."
	return ""


## Replaces the used heat shield at a shipyard. Returns a message.
static func replace_shield() -> String:
	var problem := shield_replace_problem()
	if problem != "":
		return problem
	var cost := shield_mass_kg() * shield_cost_eur_per_kg
	budget_eur -= cost
	shield_used_mj_m2 = 0.0
	return "New heat shield fitted for %s EUR." % thousands(cost)


# ---------------------------------------------------------------- refuelling and cargo

## Fills the ship's tanks from the propellant plant at the ship's location. Returns the propellant taken (kg).
static func refuel() -> float:
	var facility := facility_of_kind(ship_body(), "propellant_plant")
	if facility.is_empty():
		return 0.0
	var amount := minf(float(facility["stock_kg"]), ship_fuel_capacity_kg - ship_fuel_kg)
	if amount <= 0.0:
		return 0.0
	facility["stock_kg"] = float(facility["stock_kg"]) - amount
	ship_fuel_kg += amount
	return amount


## Buys propellant at a shipyard until the tanks are full or the budget runs out. Returns the kg bought.
static func buy_propellant() -> float:
	if facility_of_kind(ship_body(), "shipyard").is_empty() or propellant_price_eur_per_kg <= 0.0:
		return 0.0
	var amount := minf(ship_fuel_capacity_kg - ship_fuel_kg, budget_eur / propellant_price_eur_per_kg)
	if amount <= 0.0:
		return 0.0
	budget_eur -= amount * propellant_price_eur_per_kg
	ship_fuel_kg += amount
	return amount


static func cargo_mass_kg() -> float:
	var total := 0.0
	for type_id in cargo:
		total += float(facility_types[type_id]["kit"]["mass_kg"])
	return total


## Facility types that have a kit, in file order.
static func kit_type_ids() -> Array:
	var result: Array = []
	for id in facility_types:
		if facility_types[id].has("kit"):
			result.append(id)
	return result


## Why a kit cannot be loaded now ("" if it can).
static func kit_load_problem(type_id: String) -> String:
	var kit: Dictionary = facility_types[type_id]["kit"]
	if facility_of_kind(ship_body(), "shipyard").is_empty():
		return "Kits are loaded at a shipyard."
	if float(kit["mass_kg"]) > ship_payload_kg - cargo_mass_kg():
		return "Not enough payload capacity for the kit."
	if float(kit["cost_eur"]) > budget_eur:
		return "Not enough budget for the kit."
	return ""


## Buys a kit at the shipyard and loads it. Returns a message.
static func load_kit(type_id: String) -> String:
	var problem := kit_load_problem(type_id)
	if problem != "":
		return problem
	budget_eur -= float(facility_types[type_id]["kit"]["cost_eur"])
	cargo.append(type_id)
	return "Loaded: %s kit." % facility_types[type_id]["name"]


## The type of the first kit on board that can be deployed at the ship's body now ("" if none): the
## resource it works on must be available there, and the body must not have that facility yet.
static func deployable_type() -> String:
	var body_id := ship_body()
	if body_id == "":
		return ""
	for type_id in cargo:
		var type: Dictionary = facility_types[type_id]
		if facilities.has("%s_%s" % [type_id, body_id]):
			continue
		if type.has("resource"):
			var resource: Dictionary = bodies[body_id]["resources"].get(type["resource"], {})
			if float(resource.get("availability", 0.0)) <= 0.0:
				continue
		return type_id
	return ""


## Deploys the first deployable kit at the ship's body. Returns a message.
static func deploy_kit() -> String:
	var type_id := deployable_type()
	if type_id == "":
		return "Nothing to deploy here."
	cargo.erase(type_id)
	var facility := create_facility(type_id, ship_body())
	return "Built: %s." % facility["name"]


# ---------------------------------------------------------------- positions on rails

## The direction a ship orbits a body in when it follows the body's rotation: 1 counter-clockwise, -1 clockwise. That is the
## cheapest direction (for landing and taking off), so it is the default of the target orbit. A body can say otherwise in
## its data with "rotation_direction": -1 (a retrograde spinner); all the bodies so far spin counter-clockwise.
static func natural_orbit_dir(body_id: String) -> int:
	return -1 if int(bodies[body_id].get("rotation_direction", 1)) < 0 else 1


## Position (km) of a body relative to its parent.
static func body_rel(id: String, jd: float) -> Vector2:
	var segments: Array = bodies[id]["orbit_segments"]
	if segments.is_empty():
		return Vector2.ZERO
	return Kepler.position_at(Kepler.segment_at(segments, jd), jd)


## Position (km) of a body relative to the Sun.
static func body_abs(id: String, jd: float) -> Vector2:
	var total := Vector2.ZERO
	var current: Variant = id
	while current != null:
		total += body_rel(str(current), jd)
		current = bodies[str(current)]["parent"]
	return total


## The position of body to_id relative to body from_id (km), summed along the path through their common
## ancestor so that nearby bodies give small numbers (no precision lost to the Sun-centred coordinates).
static func body_rel_to(from_id: String, to_id: String, jd: float) -> Vector2:
	var from_chain: Array = _ancestors(from_id)
	var to_chain: Array = _ancestors(to_id)
	var common := ""
	for id in to_chain:
		if from_chain.has(id):
			common = str(id)
			break
	# Summed and subtracted as 64-bit floats; Vector2 (32-bit) only for the result (see B-014).
	var from_pos := [0.0, 0.0]
	for id in from_chain:
		if str(id) == common:
			break
		from_pos = _add_xy(from_pos, _body_rel_xy(str(id), jd), 1.0)
	var to_pos := [0.0, 0.0]
	for id in to_chain:
		if str(id) == common:
			break
		to_pos = _add_xy(to_pos, _body_rel_xy(str(id), jd), 1.0)
	return Vector2(to_pos[0] - from_pos[0], to_pos[1] - from_pos[1])


## Position of a body relative to its parent as 64-bit floats [x, y].
static func _body_rel_xy(id: String, jd: float) -> Array:
	var segments: Array = bodies[id]["orbit_segments"]
	if segments.is_empty():
		return [0.0, 0.0]
	return Kepler.position_xy(Kepler.segment_at(segments, jd), jd)


## a + factor * b for [x, y] pairs of 64-bit floats.
static func _add_xy(a: Array, b: Array, factor: float) -> Array:
	return [float(a[0]) + factor * float(b[0]), float(a[1]) + factor * float(b[1])]


## The natural direction of the periapsis (degrees, in the frame of the target body's parent) of a capture at
## the target: the ship comes in along its real path and passes the target on the side where it sweeps round it
## counter-clockwise, the direction of the body's rotation. The angle between the incoming direction and the
## periapsis follows from the hyperbola with periapsis radius rp and the energy of the arrival (km2/s2).
## segment is the transfer orbit (in the frame of the target's parent), t_arr the arrival time.
## direction -1: the ship passes on the other side and sweeps round the target clockwise (the mirror image).
static func natural_capture_axis_deg(segment: Dictionary, target_id: String, t_arr: float, rp: float, gm: float, energy: float, direction := 1) -> float:
	var h := 0.1   # days
	var before := _transfer_rel_target_xy(segment, target_id, t_arr - h)
	var after := _transfer_rel_target_xy(segment, target_id, t_arr + h)
	var incoming := atan2(float(after[1]) - float(before[1]), float(after[0]) - float(before[0]))
	var e := 1.0 + rp * 2.0 * energy / gm
	var slope := sqrt(maxf(e * e - 1.0, 0.0))
	return rad_to_deg(incoming - float(direction) * atan2(slope, 1.0))


## Position of the transfer orbit relative to the target body as 64-bit floats [x, y].
static func _transfer_rel_target_xy(segment: Dictionary, target_id: String, jd: float) -> Array:
	var ship_xy: Array = Kepler.position_xy(segment, jd)
	var body_xy: Array = _body_rel_xy(target_id, jd)
	return [float(ship_xy[0]) - float(body_xy[0]), float(ship_xy[1]) - float(body_xy[1])]


## The body and the bodies it orbits, from the body up to the root.
static func _ancestors(id: String) -> Array:
	var chain: Array = []
	var current: Variant = id
	while current != null:
		chain.append(str(current))
		current = bodies[str(current)]["parent"]
	return chain


static func leg_index_at(jd: float) -> int:
	var chosen := 0
	for i in legs.size():
		if float(legs[i]["t_start"]) <= jd:
			chosen = i
	return chosen


## Position (km) of the ship relative to the body frame_id. Vector2 holds 32-bit numbers, so subtracting
## two positions measured from the Sun (about 2e8 km) would lose several km of precision. Instead the
## ship's position around its body is added up the chain of parent bodies until it reaches the frame
## body; only when the frame is not an ancestor does it fall back to the difference of Sun positions.
## Near the start and the end of a transfer the position is shifted so that the path joins the orbit it
## leaves and the orbit it enters without a jump (see transfer_leg_for_plan).
static func ship_rel(frame_id: String, jd: float) -> Vector2:
	return leg_rel_with_offsets(legs[leg_index_at(jd)], frame_id, jd)


static func _leg_rel(leg: Dictionary, frame_id: String, jd: float) -> Vector2:
	# All sums and differences are done in 64-bit floats; only the result becomes a Vector2 (B-014: with
	# 32-bit numbers the position relative to Ceres was rounded to steps of about 32 km).
	var total: Array = Kepler.position_xy(leg["segment"], jd)
	var current := str(leg["parent"])
	# The frame is a body inside the leg's own system (for example a moon of the planet the ship orbits):
	# subtract the body's position around that planet, which keeps the full precision.
	var down: Array = [0.0, 0.0]
	var walker := frame_id
	while walker != current:
		var up: Variant = bodies[walker]["parent"]
		if up == null:
			break
		down = _add_xy(down, _body_rel_xy(walker, jd), 1.0)
		walker = str(up)
	if walker == current:
		return Vector2(float(total[0]) - float(down[0]), float(total[1]) - float(down[1]))
	while current != frame_id:
		var parent_id: Variant = bodies[current]["parent"]
		if parent_id == null:
			# The frame is not an ancestor: difference of the Sun positions of the leg's body and the frame.
			var leg_chain: Array = [0.0, 0.0]
			var walk: Variant = str(leg["parent"])
			while walk != null:
				leg_chain = _add_xy(leg_chain, _body_rel_xy(str(walk), jd), 1.0)
				walk = bodies[str(walk)]["parent"]
			var frame_chain: Array = [0.0, 0.0]
			walk = frame_id
			while walk != null:
				frame_chain = _add_xy(frame_chain, _body_rel_xy(str(walk), jd), 1.0)
				walk = bodies[str(walk)]["parent"]
			return Vector2(float(leg_chain[0]) + float(total[0]) - float(frame_chain[0]),
					float(leg_chain[1]) + float(total[1]) - float(frame_chain[1]))
		total = _add_xy(total, _body_rel_xy(current, jd), 1.0)
		current = str(parent_id)
	return Vector2(float(total[0]), float(total[1]))


static func leg_rel_with_offsets(leg: Dictionary, frame_id: String, jd: float) -> Vector2:
	var base := _leg_rel(leg, frame_id, jd)
	if leg["kind"] != "transfer":
		return base
	var total := base
	if leg.has("planet_hyp") and frame_id == str(leg["planet_id"]):
		return _planet_course(leg, jd)   # leaving a moon: in the view of its planet the course is the escape orbit of the planet
	if str(leg.get("from_body", "")) == frame_id:
		if leg.has("from_hyp"):
			var from_hyp: Dictionary = leg["from_hyp"]
			var from_base := base
			if leg.has("planet_hyp"):
				from_base = _moon_far_course(leg, jd)   # leaving a moon: the far course is the escape orbit of the planet, seen from the moon
			total = _blend_hyperbola(from_hyp, from_base, (jd - float(from_hyp["t0"])) * 86400.0)
		else:
			total += _faded(leg["from_offset"], base - (leg["from_ref"] as Vector2))
	if leg.has("anc_offsets") and (leg["anc_offsets"] as Dictionary).has(frame_id):
		# Leaving from a moon in a view of the planet (or the Sun): the ship starts at the moon, not at the planet.
		var anc: Dictionary = leg["anc_offsets"][frame_id]
		total += _faded(anc["offset"], base - (anc["ref"] as Vector2))
	if str(leg.get("to_body", "")) == frame_id:
		if leg.has("to_hyp"):
			# In the view of the target only the local course is shown (the hyperbola round the body, a straight
			# line far away); it is not blended with the transfer's own course, which aims at the body's centre and
			# comes in from another direction when the target orbit has an axis offset (B-018).
			var to_hyp: Dictionary = leg["to_hyp"]
			total = _hyperbola_pos(to_hyp, (jd - float(to_hyp["t0"])) * 86400.0)
		else:
			total += _faded(leg["to_offset"], base - (leg["to_ref"] as Vector2))
		if leg.has("to_mirror"):   # B-015: mirrored about the capture axis so that the approach sweeps counter-clockwise
			total = _mirrored(leg, total)
	return total


## Leaving a moon for a planet (B-035, B-008): the course round the moon's planet, relative to the planet: the escape
## hyperbola that passes through the moon's place with the ship's velocity at the moment of the burn, which far away becomes
## the transfer's own path (it starts at the planet's centre).
static func _planet_course(leg: Dictionary, jd: float) -> Vector2:
	var hyp: Dictionary = leg["planet_hyp"]
	return _blend_hyperbola(hyp, _leg_rel(leg, str(leg["planet_id"]), jd), (jd - float(hyp["t0"])) * 86400.0)


## The same course relative to the moon the ship leaves.
static func _moon_far_course(leg: Dictionary, jd: float) -> Vector2:
	return _planet_course(leg, jd) - body_rel(str(leg["from_body"]), jd)


## A hyperbolic escape orbit round a body (gravity mu) that passes through the point (relative to the body) with the
## given velocity direction, with the speed at infinity v_inf; the periapsis time is worked out from t_dep (B-030).
## direction: 1 if the ship runs counter-clockwise round the body, -1 if clockwise (the hyperbola is the mirror image).
static func _escape_hyperbola(mu: float, point: Vector2, velocity: Vector2, v_inf: float, t_dep: float, direction := 1) -> Dictionary:
	var radius := point.length()
	var v_h2 := v_inf * v_inf + 2.0 * mu / radius
	var cos_gamma := clampf(float(direction) * point.cross(velocity) / maxf(radius * velocity.length(), 1.0e-12), 0.0001, 1.0)
	var ang_mom := radius * sqrt(v_h2) * cos_gamma
	var p_semi := ang_mom * ang_mom / mu
	var e_h := sqrt(1.0 + v_inf * v_inf * ang_mom * ang_mom / (mu * mu))
	var nu := acos(clampf((p_semi / radius - 1.0) / e_h, -1.0, 1.0))
	if velocity.dot(point) < 0.0:
		nu = -nu   # still on the way in: the periapsis is ahead
	var hyp := _hyperbola(mu, p_semi / (1.0 + e_h), point.angle() - float(direction) * nu, v_inf, direction)
	var anomaly := acosh(maxf((radius / float(hyp["a"]) + 1.0) / float(hyp["e"]), 1.0))
	var since_periapsis := (float(hyp["e"]) * sinh(anomaly) - anomaly) / float(hyp["n"])
	hyp["t0"] = t_dep - signf(nu) * since_periapsis / 86400.0
	return hyp


## Gives a transfer that leaves a moon for a planet the two escape orbits of its patched-conic course (step 3b of version 0.2):
## round the planet (planet_hyp, through the moon's place) and round the moon (from_hyp, from the ship's own orbit).
static func _add_moon_escape_course(leg: Dictionary, a_plan: Dictionary, parked: Dictionary) -> void:
	var escape: Dictionary = a_plan["moon_escape"]
	var origin_id := str(a_plan["origin_id"])
	var planet_id := str(bodies[origin_id]["parent"])
	var t_dep := float(a_plan["t_dep"])
	var moon_point := body_rel(origin_id, t_dep)
	var dt := minf(1.0, 0.25 * float(a_plan["flight_days"]))
	var planet_hyp := _escape_hyperbola(float(bodies[planet_id]["gm_km3_s2"]), moon_point,
			Vector2(float(escape["vx"]), float(escape["vy"])), float(escape["v_inf_planet_kms"]), t_dep)
	var far_step := _leg_rel(leg, planet_id, t_dep + dt) - _leg_rel(leg, planet_id, t_dep + 0.5 * dt)
	planet_hyp["delta"] = _asymptote_angle(planet_hyp, false) - far_step.angle()
	planet_hyp["shift"] = _asymptote_shift(planet_hyp, false)
	planet_hyp["scale"] = moon_point.length()   # (the course has to be the hyperbola as far out as the moon's orbit)
	leg["planet_id"] = planet_id
	leg["planet_hyp"] = planet_hyp
	# Round the moon: from the ship's place in its orbit, tangentially, with the speed at infinity relative to the moon.
	var parked_segment: Dictionary = parked["segment"]
	var departure_point: Vector2 = Kepler.position_at(parked_segment, t_dep)
	var h_day := 0.001
	var orbit_velocity := (Kepler.position_at(parked_segment, t_dep + h_day) - Kepler.position_at(parked_segment, t_dep - h_day)) \
			/ (2.0 * h_day * 86400.0)
	var moon_hyp := _escape_hyperbola(float(bodies[origin_id]["gm_km3_s2"]), departure_point, orbit_velocity,
			float(escape["v_inf_moon_kms"]), t_dep, Kepler.direction(parked_segment))
	var step_a := _moon_far_course(leg, t_dep + 0.025)
	var step_b := _moon_far_course(leg, t_dep + 0.05)
	moon_hyp["delta"] = _asymptote_angle(moon_hyp, false) - (step_b - step_a).angle()
	moon_hyp["shift"] = _asymptote_shift(moon_hyp, false)
	moon_hyp["scale"] = float(parked_segment["semi_major_axis_km"]) * (1.0 + float(parked_segment["eccentricity"]))
	leg["from_hyp"] = moon_hyp


## The approach course of a leg in the view of its target, mirrored about the capture axis when the leg has to_mirror (B-015).
static func _mirrored(leg: Dictionary, position: Vector2) -> Vector2:
	if not leg.has("to_mirror"):
		return position
	var axis := float(leg["to_mirror"])
	return (position.rotated(-axis) * Vector2(1.0, -1.0)).rotated(axis)


## A hyperbolic escape or approach around a body: periapsis radius rp at the angle phi (the point where the
## ship leaves / enters its orbit, so the path joins that orbit tangentially), speed at infinity v_inf (km/s).
## direction: 1 for a ship that sweeps round the body counter-clockwise, -1 for one that sweeps clockwise (the mirror
## image about the axis through the periapsis).
static func _hyperbola(mu: float, rp: float, phi: float, v_inf: float, direction := 1) -> Dictionary:
	var v2 := v_inf * v_inf
	var a_abs := mu / v2
	return {"e": 1.0 + rp * v2 / mu, "a": a_abs, "n": sqrt(mu / pow(a_abs, 3.0)), "rp": rp, "phi": phi, "dir": float(direction)}


## Position on the hyperbola the given number of seconds after (positive) or before (negative) the periapsis.
static func _hyperbola_pos(h: Dictionary, seconds: float) -> Vector2:
	var e := float(h["e"])
	var a_abs := float(h["a"])
	var m := float(h["n"]) * seconds
	var anomaly := asinh(m / e)
	for _i in 40:
		anomaly -= (e * sinh(anomaly) - anomaly - m) / (e * cosh(anomaly) - 1.0)
	return Vector2(a_abs * (e - cosh(anomaly)), float(h.get("dir", 1.0)) * a_abs * sqrt(e * e - 1.0) * sinh(anomaly)).rotated(float(h["phi"]))


## Direction (angle) the ship travels along the far arm of the hyperbola.
static func _asymptote_angle(h: Dictionary, incoming: bool) -> float:
	var slope := sqrt(float(h["e"]) * float(h["e"]) - 1.0) * float(h.get("dir", 1.0))
	return Vector2(1.0 if incoming else -1.0, slope).angle() + float(h["phi"])


## The sideways distance of the far arm of the hyperbola from a line through the body with the same direction
## (the impact parameter, as a vector): the far path is the transfer's own path moved by this much.
static func _asymptote_shift(h: Dictionary, incoming: bool) -> Vector2:
	var e := float(h["e"])
	var a_abs := float(h["a"])
	var anomaly := -12.0 if incoming else 12.0
	var far := Vector2(a_abs * (e - cosh(anomaly)), float(h.get("dir", 1.0)) * a_abs * sqrt(e * e - 1.0) * sinh(anomaly)).rotated(float(h["phi"]))
	var travel := Vector2.from_angle(_asymptote_angle(h, incoming))
	var outward := -travel if incoming else travel
	return far - outward * far.dot(outward)


## Near the body the path follows the hyperbola; far away the transfer's own path, turned by h["delta"] so
## that it comes in (goes out) along the same direction as the hyperbola, and moved sideways by h["shift"] so
## that it also lies on the same line (the path does not aim at the body's centre but passes it at the
## impact parameter and swings round it).
static func _blend_hyperbola(h: Dictionary, base: Vector2, seconds: float) -> Vector2:
	var hyperbola := _hyperbola_pos(h, seconds)
	var rp := maxf(float(h["rp"]), float(h.get("scale", 0.0)))   # (the size of the parking orbit, if it is bigger than the periapsis)
	var outer := clampf(6.0 * float(h["a"]), 12.0 * rp, 1.0e8)
	var weight := clampf(1.0 - (hyperbola.length() - 3.0 * rp) / (outer - 3.0 * rp), 0.0, 1.0)
	weight = weight * weight * (3.0 - 2.0 * weight)
	var far: Vector2 = base.rotated(float(h["delta"])) + (h.get("shift", Vector2.ZERO) as Vector2)
	if seconds > 0.0 and h.has("delta_out"):   # a fly-by: the way out is turned by the swing round the body
		far = base.rotated(float(h["delta_out"])) + (h["shift_out"] as Vector2)
	return hyperbola * weight + far * (1.0 - weight)


## offset * a factor that is 1 at the point of the jump and falls to 0 once the path has moved a few times
## the size of the jump away from it.
static func _faded(offset: Vector2, moved: Vector2) -> Vector2:
	var length := offset.length()
	if length < 1.0:
		return Vector2.ZERO
	var factor := clampf(1.0 - moved.length() / (ROUTE_FADE_LENGTHS * length), 0.0, 1.0)
	return offset * factor * factor


## The transfer leg of a plan. The model switches from the orbit around the origin to the transfer orbit
## (and from it to the orbit around the target) at one point, so the path would jump; from_offset / to_offset
## hold that jump (relative to the origin / target body) and from_ref / to_ref the transfer's own position
## there, so that leg_rel_with_offsets can blend it out. parked is the leg the ship leaves (empty during a
## course change in flight).
static func transfer_leg_for_plan(a_plan: Dictionary, parked: Dictionary) -> Dictionary:
	var leg := {"parent": a_plan["frame"], "segment": a_plan["transfer_segment"], "t_start": a_plan["t_dep"],
			"label": ("Orbit change around %s" if a_plan.get("orbit_change", false) else "Transfer orbit to %s") % a_plan["target_name"],
			"kind": "transfer"}
	if a_plan.get("midflight", false) and a_plan.has("mid_offsets"):
		# A course change in flight: the ship may be somewhere else than the raw path says (for example near the moon it
		# has just left, while the raw transfer starts at the planet's centre): start at the real place and fade it out.
		var mid_anc := {}
		for body_id in (a_plan["mid_offsets"] as Dictionary).keys():
			mid_anc[str(body_id)] = {"offset": a_plan["mid_offsets"][body_id],
					"ref": _leg_rel(leg, str(body_id), float(a_plan["t_dep"]))}
		leg["anc_offsets"] = mid_anc
	if not parked.is_empty() and str(parked["parent"]) == str(a_plan["origin_id"]) and not a_plan.get("midflight", false):
		var base := _leg_rel(leg, str(a_plan["origin_id"]), float(a_plan["t_dep"]))
		leg["from_body"] = str(a_plan["origin_id"])
		leg["from_ref"] = base
		leg["from_offset"] = Kepler.position_at(parked["segment"], float(a_plan["t_dep"])) - base
		var departure_point: Vector2 = Kepler.position_at(parked["segment"], float(a_plan["t_dep"]))
		var departure_speed := (_leg_rel(leg, str(a_plan["origin_id"]), float(a_plan["t_dep"]) + 3600.0 / 86400.0) - base).length() / 3600.0
		if str(a_plan["frame"]) != str(a_plan["origin_id"]) and departure_speed > 0.01 and departure_point.length() > 1.0 \
				and base.length() < 2.0 * departure_point.length():   # the transfer must start at the body itself
			var origin_mu := float(bodies[str(a_plan["origin_id"])]["gm_km3_s2"])
			var way := Kepler.direction(parked["segment"])   # (1 counter-clockwise parking orbit, -1 clockwise)
			var hyp := _hyperbola(origin_mu, departure_point.length(), departure_point.angle(), departure_speed, way)
			hyp["t0"] = float(a_plan["t_dep"])
			# The route leaves tangentially: in the direction the ship is flying in its orbit. That is across the radius
			# only at an apsis; on an eccentric orbit the hyperbola is made to pass through the departure point in the
			# direction of the orbit's velocity (same radius, speed at infinity and direction; B-030).
			var h_day := 0.001
			var orbit_velocity := (Kepler.position_at(parked["segment"], float(a_plan["t_dep"]) + h_day) \
					- Kepler.position_at(parked["segment"], float(a_plan["t_dep"]) - h_day)) / (2.0 * h_day * 86400.0)
			var radius_now := departure_point.length()
			var cos_gamma := float(way) * departure_point.cross(orbit_velocity) / maxf(radius_now * orbit_velocity.length(), 1.0e-12)
			if cos_gamma > 0.05 and cos_gamma < 0.98:   # an orbit that is not across the radius here (the sign: the way it runs)
				var v_h2 := departure_speed * departure_speed + 2.0 * origin_mu / radius_now
				var ang_mom := radius_now * sqrt(v_h2) * cos_gamma
				var p_semi := ang_mom * ang_mom / origin_mu
				var e_h := sqrt(1.0 + departure_speed * departure_speed * ang_mom * ang_mom / (origin_mu * origin_mu))
				var nu := acos(clampf((p_semi / radius_now - 1.0) / e_h, -1.0, 1.0))
				if orbit_velocity.dot(departure_point) < 0.0:
					nu = -nu   # still on the way in: the periapsis of the hyperbola is ahead
				hyp = _hyperbola(origin_mu, p_semi / (1.0 + e_h), departure_point.angle() - float(way) * nu, departure_speed, way)
				var anomaly := acosh(maxf((radius_now / float(hyp["a"]) + 1.0) / float(hyp["e"]), 1.0))
				var since_periapsis := (float(hyp["e"]) * sinh(anomaly) - anomaly) / float(hyp["n"])
				hyp["t0"] = float(a_plan["t_dep"]) - signf(nu) * since_periapsis / 86400.0
			var dt := minf(1.0, 0.25 * float(a_plan["flight_days"]))
			var far_step := _leg_rel(leg, str(a_plan["origin_id"]), float(a_plan["t_dep"]) + dt) - _leg_rel(leg, str(a_plan["origin_id"]), float(a_plan["t_dep"]) + 0.5 * dt)
			hyp["delta"] = _asymptote_angle(hyp, false) - far_step.angle()
			hyp["shift"] = _asymptote_shift(hyp, false)
			# The local course has to cover the whole parking orbit before it changes over to the transfer's own course:
			# the size is the apoapsis of the parking orbit (B-027: with an eccentric orbit the change-over was inside it).
			var parked_segment: Dictionary = parked["segment"]
			hyp["scale"] = float(parked_segment["semi_major_axis_km"]) * (1.0 + float(parked_segment["eccentricity"]))
			leg["from_hyp"] = hyp
		# The transfer is calculated from the centre of the planet the origin moon orbits. In the views of the
		# planet (and the bodies above it) the ship has to start at the moon, so the jump from the moon's place
		# to the planet's centre is added and faded out as the ship moves away.
		var origin_parent: Variant = bodies[str(a_plan["origin_id"])]["parent"]
		if origin_parent != null and str(origin_parent) != str(a_plan["frame"]) and str(a_plan["frame"]) != str(a_plan["origin_id"]):
			var anc_offsets := {}
			var t_departure := float(a_plan["t_dep"])
			var parked_point: Vector2 = Kepler.position_at(parked["segment"], t_departure)
			for ancestor in _ancestors(str(a_plan["origin_id"])).slice(1):
				var base_ancestor := _leg_rel(leg, str(ancestor), t_departure)
				anc_offsets[str(ancestor)] = {
					"offset": body_rel_to(str(ancestor), str(a_plan["origin_id"]), t_departure) + parked_point - base_ancestor,
					"ref": base_ancestor,
				}
			leg["anc_offsets"] = anc_offsets
			if a_plan.has("moon_escape"):
				_add_moon_escape_course(leg, a_plan, parked)
	var captures: Array = a_plan.get("capture_legs", [])
	var fly_aero: Dictionary = a_plan.get("aero", {})
	var fly_propulsive: bool = bool(a_plan.get("flyby_propulsive", false))
	if captures.is_empty() and str(a_plan.get("outcome", "ok")) == "flyby" and (fly_aero.get("enabled", false) or fly_propulsive) \
			and str(a_plan["frame"]) != str(a_plan["target_id"]) and float(a_plan.get("arrival_energy", -1.0)) > 0.0:
		# A fly-by: the ship swings round the target through the upper atmosphere (periapsis at the aerobraking
		# altitude) and flies on. The local course is a hyperbola around the target; far away it is the transfer's own path.
		var target_id := str(a_plan["target_id"])
		var rp_fly := float(bodies[target_id]["radius_km"]) + float(fly_aero.get("h_km", 0.0)) if not fly_propulsive else float(a_plan["rp_t"])
		var t_pass := float(a_plan["t_arr"])
		var dt_fly := minf(1.0, 0.25 * float(a_plan["flight_days"]))
		leg["to_body"] = target_id
		leg["to_ref"] = _leg_rel(leg, target_id, t_pass)
		leg["to_offset"] = Vector2.ZERO
		var hyp_fly := _hyperbola(float(a_plan["gm_target"]), rp_fly, 0.0, sqrt(2.0 * float(a_plan["arrival_energy"])))
		var in_step := _leg_rel(leg, target_id, t_pass - 0.5 * dt_fly) - _leg_rel(leg, target_id, t_pass - dt_fly)
		var out_step := _leg_rel(leg, target_id, t_pass + dt_fly) - _leg_rel(leg, target_id, t_pass + 0.5 * dt_fly)
		var slope_fly := sqrt(float(hyp_fly["e"]) * float(hyp_fly["e"]) - 1.0)
		hyp_fly["phi"] = in_step.angle() - Vector2(1.0, slope_fly).angle()   # the approach direction is the real one
		hyp_fly["delta"] = _asymptote_angle(hyp_fly, true) - in_step.angle()
		hyp_fly["shift"] = _asymptote_shift(hyp_fly, true)
		hyp_fly["delta_out"] = _asymptote_angle(hyp_fly, false) - out_step.angle()
		hyp_fly["shift_out"] = _asymptote_shift(hyp_fly, false)
		hyp_fly["t0"] = t_pass
		leg["to_hyp"] = hyp_fly
	if not captures.is_empty() and str(captures[0]["parent"]) == str(a_plan["target_id"]):
		var base_end := _leg_rel(leg, str(a_plan["target_id"]), float(a_plan["t_arr"]))
		leg["to_body"] = str(a_plan["target_id"])
		leg["to_ref"] = base_end
		leg["to_offset"] = Kepler.position_at(captures[0]["segment"], float(captures[0]["t_start"])) - base_end
		var capture_point: Vector2 = Kepler.position_at(captures[0]["segment"], float(captures[0]["t_start"]))
		var energy := float(a_plan.get("arrival_energy", -1.0))
		# (The transfer is calculated to the body, but it may miss the centre by a few thousand km: the curved
		# approach is used unless it misses by an absurd distance. With the old limit of twice the capture radius
		# the course went straight through Earth, and through Ceres with an axis offset.)
		if energy > 0.0 and str(a_plan["frame"]) != str(a_plan["target_id"]) and capture_point.length() > 1.0 \
				and base_end.length() < APPROACH_MAX_MISS_KM:
			var capture_way := Kepler.direction(captures[0]["segment"])   # (a clockwise orbit: the approach sweeps clockwise)
			var hyp_in := _hyperbola(float(a_plan["gm_target"]), capture_point.length(), capture_point.angle(), sqrt(2.0 * energy), capture_way)
			var dt_in := minf(1.0, 0.25 * float(a_plan["flight_days"]))
			var near_step := _leg_rel(leg, str(a_plan["target_id"]), float(a_plan["t_arr"]) - 0.5 * dt_in) - _leg_rel(leg, str(a_plan["target_id"]), float(a_plan["t_arr"]) - dt_in)
			hyp_in["delta"] = _asymptote_angle(hyp_in, true) - near_step.angle()
			hyp_in["t0"] = float(a_plan["t_arr"])
			hyp_in["shift"] = _asymptote_shift(hyp_in, true)
			leg["to_hyp"] = hyp_in
		var diag := "approach to %s: miss %.0f km, capture radius %.0f km, curved approach: %s" % [a_plan["target_id"], base_end.length(), capture_point.length(), str(leg.has("to_hyp"))]
		if diag != _last_approach_diag:   # for the Godot output: shows why a course is straight or curved
			_last_approach_diag = diag
			print(diag)
		# B-015: the orbit runs counter-clockwise (the body's rotation). If the approach as drawn sweeps
		# clockwise round the target, mirror it about the axis through the capture point.
		var sweep := 0.0
		var previous_point := Vector2.ZERO
		var have_previous := false
		for k in 41:
			var days_before := 2.0 * pow(1.0 / 2880.0, float(k) / 40.0)
			var point := leg_rel_with_offsets(leg, str(a_plan["target_id"]), float(a_plan["t_arr"]) - days_before)
			if have_previous and point.length() > 0.0 and previous_point.length() > 0.0:
				sweep += previous_point.angle_to(point)
			previous_point = point
			have_previous = true
		if sweep < -0.01 and Kepler.direction(captures[0]["segment"]) > 0:
			leg["to_mirror"] = capture_point.angle()   # (a clockwise orbit has its own mirrored hyperbola: nothing to mirror)
	return leg


## The transfer leg to draw for a plan: the real one once it is launched, otherwise a fresh one.
static func plan_transfer_leg(a_plan: Dictionary) -> Dictionary:
	if a_plan.is_empty():
		return {}
	if a_plan["committed"]:
		for leg in legs:
			if leg["kind"] == "transfer" and absf(float(leg["t_start"]) - float(a_plan["t_dep"])) < 1.0e-9:
				return leg
		return {}
	return transfer_leg_for_plan(a_plan, parked_leg())


## Gives the legs of a launched plan the time their changes of orbit take: the burn time of the burn, or the
## time of one pass through the atmosphere. During that time the displayed orbit morphs from the old orbit
## to the new one (see morph_at).
static func set_morph_times(a_plan: Dictionary, transfer_leg: Dictionary) -> void:
	transfer_leg["morph_days"] = burn_days(float(a_plan["dv_departure"]))
	var aero: Dictionary = a_plan.get("aero", {})
	var aero_used: bool = aero.get("enabled", false) and str(aero.get("outcome", "ok")) == "ok"
	if str(a_plan.get("outcome", "ok")) == "flyby" and aero.get("enabled", false):
		# The pass of a fly-by: the heat glow, the plasma and the turn tail first belong to the transfer leg (no capture leg).
		transfer_leg["flyby_t"] = float(a_plan["t_arr"])
		transfer_leg["flyby_days"] = maxf(float(aero.get("pass_days", 0.0)), 60.0 / 86400.0)
		transfer_leg["flyby_heat"] = heat_effect_strength(float(aero.get("peak_flux", 0.0)))
	var captures: Array = a_plan.get("capture_legs", [])
	for i in captures.size():
		var capture_leg: Dictionary = captures[i]
		capture_leg["is_pass"] = aero_used and i < int(aero["n"])
		capture_leg["heat_peak"] = heat_effect_strength(float(aero.get("peak_flux", 0.0))) if capture_leg["is_pass"] else 0.0
		if aero_used and i < int(aero["n"]):
			capture_leg["morph_days"] = float(aero.get("pass_days", 0.0))
		else:
			# The burns after the passes (or the whole capture): the axis turn is its own burn (its own leg), the rest is
			# what remains of the delta-v.
			var total := float(aero.get("final_dv", 0.0)) if aero_used else float(a_plan["dv_arrival"])
			var turn_dv := AeroBraking.axis_turn_dv(a_plan)
			capture_leg["morph_days"] = burn_days(turn_dv if capture_leg.get("axis_turn", false) else maxf(total - turn_dv, 0.0))


## While a burn or an aerobraking pass changes the orbit, the orbit to show: periapsis, apoapsis and axis move
## linearly from the old orbit to the new one. Returns {"parent", "segment"} (a copy of the new segment with
## the shown shape), or {} when no change is going on.
static func _morph_visible(i: int) -> bool:
	# Leaving for another body is not morphed: the route is drawn instead.
	return float(legs[i].get("morph_days", 0.0)) > 0.0 and not (str(legs[i - 1]["parent"]) != str(legs[i]["parent"]) and legs[i]["kind"] == "transfer")


## The start of the next morph (before jd_end), or -1.
static func _next_morph_window(jd_end: float) -> Dictionary:
	var best := {}
	for window: Dictionary in manoeuvre_windows():
		var t_turn := float(window["t0"]) - float(window["lead"])   # where the turn begins
		if t_turn > time_jd and t_turn <= jd_end and (best.is_empty() or t_turn < float(best["t_turn"])):
			best = window.duplicate()
			best["t_turn"] = t_turn
	return best


## Strength (0 to 1) of the heating effect for a heat flux in MW/m2: logarithmic between the two thresholds.
static func heat_effect_strength(flux_mw_m2: float) -> float:
	if flux_mw_m2 <= heat_effect_min_mw_m2:
		return 0.0
	return clampf(log(flux_mw_m2 / heat_effect_min_mw_m2) / log(heat_effect_max_mw_m2 / heat_effect_min_mw_m2), 0.0, 1.0)


## The heating effect now (0 to 1): during an aerobraking pass it rises and falls over the pass (the morph window
## of the pass leg), peaking at the strength of the pass's peak heat flux.
static func heat_at(jd: float) -> float:
	for i in range(1, legs.size()):
		var leg: Dictionary = legs[i]
		if leg.has("flyby_t"):
			var fly_span := float(leg["flyby_days"])
			var fly_t0 := float(leg["flyby_t"]) - 0.5 * fly_span
			if jd >= fly_t0 and jd <= fly_t0 + fly_span:
				var fly_bell := sin(PI * (jd - fly_t0) / fly_span)
				return float(leg["flyby_heat"]) * fly_bell * fly_bell
		var span := float(leg.get("morph_days", 0.0))
		if span <= 0.0 or not bool(leg.get("is_pass", false)):
			continue
		var t0 := float(leg["t_start"]) - 0.5 * span
		if jd >= t0 and jd <= t0 + span:
			var bell := sin(PI * (jd - t0) / span)
			return float(leg.get("heat_peak", 0.0)) * bell * bell
	return 0.0


## How fast the ship turns (degrees per game second): the heavier the ship, the slower (inertia, and the loads
## of turning a big craft). Logarithmic between a light and a heavy mass.
static func rotation_rate_deg_s() -> float:
	var mass := maxf(dry_mass_kg() + maxf(ship_fuel_kg, 0.0), 1.0)
	var w := clampf(log(mass / rotation_light_mass_kg) / log(rotation_heavy_mass_kg / rotation_light_mass_kg), 0.0, 1.0)
	return rotation_max_deg_s * pow(rotation_min_deg_s / rotation_max_deg_s, w)


## Time (days) the ship needs to turn half a turn.
static func half_turn_days() -> float:
	return 180.0 / rotation_rate_deg_s() / 86400.0


## Does the burn that starts leg i speed the ship up (prograde)? Found from the velocity just before and after.
static func _burn_is_prograde(i: int) -> bool:
	var leg: Dictionary = legs[i]
	if leg.has("prograde"):
		return bool(leg["prograde"])
	var before_leg: Dictionary = legs[i - 1]
	var t0 := float(leg["t_start"])
	# The velocity is measured relative to the lower of the two bodies: arriving at a moon, relative to the moon (in
	# the frame of its planet the ship may overtake or trail the moon and the sign of the capture burn would be wrong).
	var frame := str(before_leg["parent"])
	if _ancestors(str(leg["parent"])).has(frame):
		frame = str(leg["parent"])
	var dt := 30.0 / 86400.0
	var before := leg_rel_with_offsets(before_leg, frame, t0) - leg_rel_with_offsets(before_leg, frame, t0 - dt)
	var after := leg_rel_with_offsets(leg, frame, t0 + dt) - leg_rel_with_offsets(leg, frame, t0)
	var change := after - before
	var result := change.dot(before) >= 0.0
	# B-047: the ship points along the thrust (the velocity change), so after the burn it is tail first if that points against
	# the new velocity. Normally the same as during the burn; after a turn-round (the velocity reverses) it is the opposite.
	leg["after_tail"] = change.dot(after) < 0.0
	leg["prograde"] = result
	return result


## Is the ship tail first (against its direction of flight) right after the burn that starts leg i?
static func _burn_after_tail(i: int) -> bool:
	_burn_is_prograde(i)   # (works it out and keeps it)
	return bool(legs[i]["after_tail"])


## The direction (angle on the screen, radians) in which the ship has to point for the axis-turning burn that starts
## leg i: along the change of velocity at the point where the two orbits cross (the thrust points along the nose).
static func _burn_heading(i: int) -> float:
	var leg: Dictionary = legs[i]
	if leg.has("burn_heading"):
		return float(leg["burn_heading"])
	var t := float(leg["t_start"])
	var h := 0.001   # days
	var old_segment: Dictionary = legs[i - 1]["segment"]
	var new_segment: Dictionary = leg["segment"]
	var v_old := Kepler.position_at(old_segment, t + h) - Kepler.position_at(old_segment, t - h)
	var v_new := Kepler.position_at(new_segment, t + h) - Kepler.position_at(new_segment, t - h)
	var dv := v_new - v_old
	var angle := Vector2(dv.x, -dv.y).angle() if dv.length_squared() > 0.0 else 0.0
	leg["burn_heading"] = angle
	return angle


## The burns and aerobraking passes of the ship in time order, with the attitude each one needs and when the
## ship has to start turning for it: {t0, t1, tail_first, is_pass, from_retro (the attitude before: 0 nose first,
## 1 tail first), lead (days the turn takes: 0 if the ship already points the right way)}. The ship keeps the
## attitude of its last burn or pass until the next one needs another, and then turns by the half turn.
static func manoeuvre_windows() -> Array:
	var result: Array = []
	var turn := half_turn_days()
	var previous := 0.0
	for i in range(1, legs.size()):
		var leg: Dictionary = legs[i]
		var span := float(leg.get("morph_days", 0.0))
		if span > 0.0:
			var is_pass := bool(leg.get("is_pass", false))
			if bool(leg.get("axis_turn", false)) and str(legs[i - 1]["parent"]) == str(leg["parent"]):
				# The radial burn that turns the axis: the ship points along the velocity change, fixed in space, for the
				# whole burn. It turns to that heading before the burn and back to its course after it.
				var fixed_t0 := float(leg["t_start"]) - 0.5 * span
				result.append({"t0": fixed_t0, "t1": fixed_t0 + span, "tail_first": previous > 0.5, "is_pass": false, "label": str(leg["label"]),
						"from_retro": previous, "lead": turn, "fixed": true, "fixed_angle": _burn_heading(i)})
				continue
			var tail_first := is_pass or not _burn_is_prograde(i)
			var wanted := 1.0 if tail_first else 0.0
			var after := 1.0 if (is_pass or _burn_after_tail(i)) else 0.0   # (differs from wanted after a turn-round)
			var t0 := float(leg["t_start"]) - 0.5 * span
			result.append({"t0": t0, "t1": t0 + span, "tail_first": tail_first, "is_pass": is_pass, "label": str(leg["label"]),
					"from_retro": previous, "lead": turn if wanted != previous else 0.0,
					"after_retro": after, "t_mid": float(leg["t_start"])})
			previous = after
		if leg.has("flyby_t"):
			var fly_span := float(leg["flyby_days"])
			var fly_t0 := float(leg["flyby_t"]) - 0.5 * fly_span
			result.append({"t0": fly_t0, "t1": fly_t0 + fly_span, "tail_first": true, "is_pass": true, "label": "Fly-by of " + str(leg["label"]).trim_prefix("Transfer orbit to "),
					"from_retro": previous, "lead": turn if previous != 1.0 else 0.0})
			previous = 1.0
	return result


## The attitude of the ship at a time: {"retro": 0 to 1, "burn": 0 none / 1 prograde burn / -1 retrograde burn}.
## retro is how far the ship has turned from flying nose first to flying tail first (the engine and the heat shield
## are at the tail). Only a function of time, so it is right at every warp.
static func attitude_at(jd: float) -> Dictionary:
	var retro := 0.0
	var burn := 0
	var fixed := 0.0          # 0 to 1: how far the ship has turned from its course to the fixed heading of an axis-turning burn
	var fixed_angle := 0.0
	var flips := 0            # turn-round burns passed so far (the velocity reversed at the middle of each): the view needs them
	var windows := manoeuvre_windows()
	for window: Dictionary in windows:
		var wanted := 1.0 if bool(window["tail_first"]) else 0.0
		var from_retro := float(window["from_retro"])
		var t0 := float(window["t0"])
		var lead := float(window["lead"])
		if jd < t0 - lead:
			retro = from_retro
			break
		if bool(window.get("fixed", false)):
			retro = from_retro
			fixed_angle = float(window["fixed_angle"])
			# (the turn itself, at the turning rate, is done by the view: this is the heading the ship wants)
			if jd <= float(window["t1"]):
				fixed = 1.0
				if jd >= t0:
					burn = 2
				break
			fixed = 0.0
			continue
		fixed = 0.0
		if jd < t0:
			retro = lerpf(from_retro, wanted, smoothstep(t0 - lead, t0, jd))
			break
		retro = wanted
		var after_retro := float(window.get("after_retro", wanted))
		if after_retro != wanted and jd >= float(window["t_mid"]):
			retro = after_retro   # B-047: a turn-round: from the middle of the burn the velocity points the other way
			flips += 1
		if not bool(window["is_pass"]) and jd <= float(window["t1"]):
			burn = -1 if wanted > 0.5 else 1
	return {"retro": retro, "burn": burn, "fixed": fixed, "fixed_angle": fixed_angle, "flips": flips}

## Radius (km) of the sphere of influence of a body (Laplace). Bodies where this is smaller than the body itself
## (tiny moons) have none: 0.
static func soi_radius_km(id: String) -> float:
	var parent: Variant = bodies[id]["parent"]
	if parent == null:
		return INF
	var segment: Dictionary = bodies[id]["orbit_segments"][0]
	var soi := float(segment["semi_major_axis_km"]) * pow(float(bodies[id]["gm_km3_s2"]) / float(bodies[str(parent)]["gm_km3_s2"]), 0.4)
	return soi if soi > float(bodies[id]["radius_km"]) else 0.0


const ROUTE_MAX_SPEED_KMS := 80.0   # no relative speed in the system is higher: bounds how fast the ship can reach a body


## The first body (other than the origin, the target and the bodies they orbit) whose sphere of influence the
## planned route passes through, as {"body", "t"}; {} if the route is clear. For plans from the parking orbit.
static func route_conflict(a_plan: Dictionary, parked: Dictionary) -> Dictionary:
	if a_plan.is_empty() or a_plan.get("midflight", false) or parked.is_empty():
		return {}
	var saved := legs
	var transfer_leg := transfer_leg_for_plan(a_plan, parked)
	legs = [parked, transfer_leg]
	legs.append_array(a_plan.get("capture_legs", []))
	var result := _route_conflict_between(a_plan, float(a_plan["t_dep"]), float(a_plan["t_arr"]))
	legs = saved
	return result


static func _route_conflict_between(a_plan: Dictionary, t0: float, t1: float) -> Dictionary:
	var skip := {}
	for key in ["origin_id", "target_id"]:
		for id in _ancestors(str(a_plan[key])):
			skip[id] = true
	var coarse := 0.5
	for key in bodies.keys():
		var id := str(key)
		if skip.has(id) or id == str(a_plan["origin_id"]) or id == str(a_plan["target_id"]):
			continue
		var radius := soi_radius_km(id)
		if radius <= 0.0 or is_inf(radius):
			continue
		var reach := radius + ROUTE_MAX_SPEED_KMS * coarse * 86400.0
		var fine := maxf(0.4 * radius / ROUTE_MAX_SPEED_KMS / 86400.0, coarse / 400.0)
		var t := t0
		while t <= t1:
			var distance := ship_rel(id, t).length()
			if distance <= radius:
				return {"body": id, "t": t}
			if distance <= reach:
				var u := t
				var u_end := minf(t + coarse, t1)
				while u <= u_end:
					if ship_rel(id, u).length() <= radius:
						return {"body": id, "t": u}
					u += fine
			t += coarse
	return {}


## The orbit during the radial burn that turns the axis (w from 0 to 1): the ship stays at the point P where the
## two orbits cross, and its velocity changes from the old one to the new one (only the radial part changes), so
## every orbit in between is the one through P with that velocity. The orbit turns about P and shrinks and grows
## again a little on the way (a stretch), instead of morphing from one orbit to the other. {} if it cannot be made.
static func _axis_turn_orbit(old_segment: Dictionary, new_segment: Dictionary, t_burn: float, w: float) -> Dictionary:
	var h := 0.001   # days
	var a := float(new_segment["semi_major_axis_km"])
	var n_rad_s := deg_to_rad(float(new_segment["mean_motion_deg_per_day"])) / 86400.0
	var mu := n_rad_s * n_rad_s * a * a * a
	var p := Kepler.position_at(new_segment, t_burn)
	var v_old := (Kepler.position_at(old_segment, t_burn + h) - Kepler.position_at(old_segment, t_burn - h)) / (2.0 * h * 86400.0)
	var v_new := (Kepler.position_at(new_segment, t_burn + h) - Kepler.position_at(new_segment, t_burn - h)) / (2.0 * h * 86400.0)
	return CourseChange.state_segment(mu, p, v_old.lerp(v_new, clampf(w, 0.0, 1.0)), t_burn)


static func morph_at(jd: float) -> Dictionary:
	for i in range(1, legs.size()):
		var leg: Dictionary = legs[i]
		var span := float(leg.get("morph_days", 0.0))
		if span <= 0.0:
			continue
		var t0 := float(leg["t_start"]) - 0.5 * span
		if jd < t0 or jd > t0 + span:
			continue
		var before: Dictionary = legs[i - 1]
		var new_segment: Dictionary = leg["segment"]
		var old_segment: Dictionary = before["segment"]
		if str(before["parent"]) != str(leg["parent"]):
			if leg["kind"] == "transfer":
				continue   # leaving for another body: the route is drawn instead
			# Insertion: the orbit shrinks from a very wide one with the same periapsis.
			var rp_new := float(new_segment["semi_major_axis_km"]) * (1.0 - float(new_segment["eccentricity"]))
			var wide := view_radius_km(str(leg["parent"]), jd) * 1.5
			old_segment = AeroBraking._ellipse(1.0, rp_new, maxf(wide, rp_new * 2.0), jd, float(new_segment["argument_of_periapsis_deg"]), 0.0, Kepler.direction(new_segment))
		var w := (jd - t0) / span
		if leg.get("axis_turn", false) and str(before["parent"]) == str(leg["parent"]):
			var turning := _axis_turn_orbit(old_segment, new_segment, float(leg["t_start"]), w)
			if not turning.is_empty():
				return {"parent": str(leg["parent"]), "segment": turning}
		var rp0 := float(old_segment["semi_major_axis_km"]) * (1.0 - float(old_segment["eccentricity"]))
		var ra0 := float(old_segment["semi_major_axis_km"]) * (1.0 + float(old_segment["eccentricity"]))
		var rp1 := float(new_segment["semi_major_axis_km"]) * (1.0 - float(new_segment["eccentricity"]))
		var ra1 := float(new_segment["semi_major_axis_km"]) * (1.0 + float(new_segment["eccentricity"]))
		var axis0 := float(old_segment["argument_of_periapsis_deg"])
		var axis1 := float(new_segment["argument_of_periapsis_deg"])
		if float(old_segment["eccentricity"]) < 0.002:
			axis0 = axis1   # a circular orbit has no axis: use the other one
		elif float(new_segment["eccentricity"]) < 0.002:
			axis1 = axis0
		var rp := lerpf(rp0, rp1, w)
		var ra := lerpf(ra0, ra1, w)
		var shown: Dictionary = new_segment.duplicate()
		shown["semi_major_axis_km"] = 0.5 * (rp + ra)
		shown["eccentricity"] = (ra - rp) / (ra + rp)
		shown["argument_of_periapsis_deg"] = axis0 + wrapf(axis1 - axis0, -180.0, 180.0) * w
		return {"parent": str(leg["parent"]), "segment": shown}
	return {}


# ---------------------------------------------------------------- views

## The distance that the view of a body is scaled to: the widest orbit of its children (or of the ship, if the
## body has no children), at least four body radii.
static func view_extent_km(frame_id: String, jd: float) -> float:
	var kid_ids: Array = children[frame_id]
	var extent := float(bodies[frame_id]["radius_km"]) * 4.0
	var leg: Dictionary = legs[leg_index_at(jd)]
	if kid_ids.is_empty() and leg["parent"] == frame_id:
		extent = maxf(extent, float(leg["segment"]["semi_major_axis_km"]) * 1.5)
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], jd)
		extent = maxf(extent, float(segment["semi_major_axis_km"]) * (1.0 + float(segment["eccentricity"])))
	# A ship that stays in orbit around the body keeps its whole orbit in the view (apoapsis + 10%), so it does not
	# get zoomed out to the next system when the orbit is wider than the moons, and the time flow does not drop every
	# time it passes the edge of the view. This goes for the orbit it is on and for the orbits it will be on (the
	# legs of a launched plan) and for the intended orbit of the plan in the planner. Not if the apoapsis is beyond
	# the highest orbit the body can have (then it is not staying in orbit).
	var limit := max_orbit_radius_km(frame_id)
	for index in range(leg_index_at(jd), legs.size()):
		var orbit_leg: Dictionary = legs[index]
		if orbit_leg["parent"] == frame_id and orbit_leg["kind"] != "transfer":
			var apoapsis := float(orbit_leg["segment"]["semi_major_axis_km"]) * (1.0 + float(orbit_leg["segment"]["eccentricity"]))
			if apoapsis <= limit:
				extent = maxf(extent, apoapsis * 1.1)
	if not plan.is_empty() and str(plan.get("target_id", "")) == frame_id and plan.has("ra_t"):
		if float(plan["ra_t"]) <= limit:
			extent = maxf(extent, float(plan["ra_t"]) * 1.1)
	return extent


## The largest distance from the centre of a body that an orbit around it can reach: the edge of its sphere of
## influence; for tiny bodies without one, 100 body radii above the surface.
static func max_orbit_radius_km(id: String) -> float:
	var radius := float(bodies[id]["radius_km"])
	var soi := soi_radius_km(id)
	if is_inf(soi):
		return INF
	if soi < radius * TINY_SOI_RADII:
		return radius * 101.0
	return maxf(soi, radius * 2.0)


## The highest altitude (km above the surface) that an orbit around a body can have: the edge of its sphere of
## influence. Tiny bodies (a sphere of influence smaller than TINY_SOI_RADII body radii, which is none or hardly
## more than the body itself, like Phobos and Deimos) keep a generous limit of 100 body radii.
static func max_orbit_altitude_km(id: String) -> float:
	var radius := float(bodies[id]["radius_km"])
	var soi := soi_radius_km(id)
	if is_inf(soi) or soi < radius * TINY_SOI_RADII:
		return radius * 100.0
	return maxf(soi - radius, radius)


## The distance from a body's centre that its view shows at the edge of a portrait screen.
static func view_radius_km(frame_id: String, jd: float) -> float:
	return view_extent_km(frame_id, jd) / VIEW_FILL


## The distance from the centre of a body up to which it is the ship's context: the distance its view shows at the
## edge of a portrait screen (view_radius_km, which contains the orbits of its moons and of the ship), but not
## beyond the edge of its sphere of influence (max_orbit_radius_km). Every body that can have a local view has one,
## small moons, asteroids and comets included. Leaving it changes the context to the next larger body; entering a
## smaller one slows the time flow and changes the view. jd < 0: now.
static func context_radius_km(id: String, jd := -1.0) -> float:
	return minf(max_orbit_radius_km(id), view_radius_km(id, time_jd if jd < 0.0 else jd))


## Works out the context of the ship (a parameter of the ship, ship_context_id): the body with the smallest
## context radius that contains the ship. A context is left only when the ship is CONTEXT_HYSTERESIS times
## further out than its radius, so a ship on the edge does not flip between two contexts. Returns the context.
static func update_ship_context(jd: float) -> String:
	var best := "sun"
	var best_radius := INF
	for id in bodies.keys():
		var radius := context_radius_km(str(id), jd)
		if radius < best_radius and ship_rel(str(id), jd).length() <= radius:
			best = str(id)
			best_radius = radius
	if ship_context_id != "" and bodies.has(ship_context_id) and best != ship_context_id:
		var current_radius := context_radius_km(ship_context_id, jd)
		if best_radius > current_radius and ship_rel(ship_context_id, jd).length() <= current_radius * CONTEXT_HYSTERESIS:
			return ship_context_id   # just outside the edge of the context: keep it
	ship_context_id = best
	return best


## The body with the smallest view that contains the ship (the view of a body is only used inside its context).
static func smallest_view(jd: float) -> String:
	var best := "sun"
	var best_radius := INF
	for id in bodies.keys():
		var radius := view_radius_km(str(id), jd)
		if radius < best_radius and ship_rel(str(id), jd).length() <= minf(radius, context_radius_km(str(id), jd)):
			best = str(id)
			best_radius = radius
	return best


## If the ship gets inside the context of a smaller body than the one it is in now before jd_end, when it gets in (else -1).
## The whole interval is sampled: at a high warp a step can carry the ship through a small view (Mars) and out
## again, so comparing only the two ends would miss it.
static func _next_context_entry(jd_end: float) -> float:
	var now_radius := context_radius_km(update_ship_context(time_jd), time_jd)
	var candidates: Array = []
	for id in bodies.keys():
		if context_radius_km(str(id), time_jd) < now_radius:
			candidates.append(str(id))
	if candidates.is_empty():
		return -1.0
	var span := jd_end - time_jd
	var samples := clampi(ceili(span / 0.01), 1, 160)
	var previous := time_jd
	for k in range(1, samples + 1):
		var t := time_jd + span * float(k) / float(samples)
		for id in candidates:
			if ship_rel(id, t).length() <= context_radius_km(id, t):
				var low := previous
				var high := t
				for _i in 24:
					var middle := 0.5 * (low + high)
					if ship_rel(id, middle).length() <= context_radius_km(id, middle):
						high = middle
					else:
						low = middle
				return high
		previous = t
	return -1.0


## Position (km) of the ship relative to the Sun.
static func ship_abs(jd: float) -> Vector2:
	var leg: Dictionary = legs[leg_index_at(jd)]
	return body_abs(str(leg["parent"]), jd) + Kepler.position_at(leg["segment"], jd)
