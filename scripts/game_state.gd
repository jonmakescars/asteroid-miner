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
const VIEW_FILL := 0.9          # share of the half screen width that the widest orbit of a view fills
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


# ---------------------------------------------------------------- clock

## Advances the game clock by delta real seconds. On departure and arrival the burns are taken from
## the tanks; on arrival the plan is finished and the time flow drops to real time.
static func advance(delta: float) -> void:
	if not paused:
		var step := delta * float(WARP_STEPS[warp_index])
		var entry := _next_atmosphere_entry()
		var decay_entry := _next_decay_entry(time_jd + step)
		if decay_entry > 0.0 and (entry < 0.0 or decay_entry < entry):
			entry = decay_entry
		if warp_index > AERO_WARP_INDEX:
			# Stop at the EARLIEST of the events that need a slow warp: the start of an aerobraking pass (never jump
			# over it), the start of a visible burn / pass morph, and the moment the ship gets inside a smaller view.
			var stop := -1.0
			if entry > 0.0 and time_jd + step >= entry:
				stop = entry
			var morph_start := _next_morph_start(time_jd + step)
			if morph_start > 0.0 and (stop < 0.0 or morph_start < stop):
				stop = morph_start
			var entry_time := _next_view_entry(time_jd + step)
			if entry_time > 0.0 and (stop < 0.0 or entry_time < stop):
				stop = entry_time
			if stop > 0.0:
				time_jd = maxf(time_jd, stop)
				warp_index = AERO_WARP_INDEX
				step = delta * float(WARP_STEPS[warp_index])
		var lost_at := _loss_time()
		if lost_at > 0.0 and time_jd + step >= lost_at:
			time_jd = maxf(time_jd, lost_at)   # stop exactly where the ship blows up
		else:
			time_jd += step
	_decay_orbit()
	var running := running_plan()
	if not running.is_empty() and running["committed"]:
		if not running["departure_done"] and time_jd >= float(running["t_dep"]):
			running["departure_done"] = true
			apply_burn(float(running["dv_departure"]))
		var lost_at_end := _loss_time()
		var end_time := lost_at_end if lost_at_end > 0.0 else float(running.get("t_end", running["t_arr"]))
		if time_jd >= end_time:
			var aero: Dictionary = running.get("aero", {})
			if str(running.get("outcome", "ok")) != "ok":
				# The planner only warned about this; now it happens. (Placeholder rules: the ship is wrecked.)
				ship_health = 0.0
				message = _lost_text(str(running["outcome"]), str(running["target_name"]))
				_lose_ship(message, str(running["outcome"]) != "crash" and bodies[str(running["target_id"])].get("atmosphere") is Dictionary)
			else:
				apply_burn(float(running["dv_arrival"]))
				message = "Arrived at %s." % running["target_name"]
				if aero.get("enabled", false):
					message += " " + _take_aerobraking_effects(aero)
			plan = {}
			saved_plan = {}
			warp_index = 0
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
			return "%s%s: altitude %s km | Speed %.2f km/s (relative to %s)" % [verb, str(bodies[near_id]["name"]), _km_text(near_altitude), near_speed, str(bodies[near_id]["name"])]
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
	return "%s: periapsis %s km | apoapsis %s km | axis %s | altitude %s km | %s %.2f km/s" % [
			("Orbit around " if leg["kind"] == "orbit" else "Flight around ") + str(body["name"]),
			_km_text(periapsis), _km_text(apoapsis), axis_text, _km_text(altitude), speed_name, speed]


static func _km_text(value: float) -> String:
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
	var to_periapsis_deg := fposmod(-float(segment["mean_anomaly_deg"]), 360.0)
	return float(segment["epoch_jd"]) + to_periapsis_deg / float(segment["mean_motion_deg_per_day"])


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
	var t_pass := t_start + fposmod(-m_deg, 360.0) / n_rate
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
		segment["mean_motion_deg_per_day"] = TransferPlanner.mean_motion_deg_per_day(gm, a_new)
		message = "The orbit is decaying: " + text


## Adds the heat of the aerobraking passes to the shield and damages the ship if the shield or the g
## limit was exceeded. Returns a sentence for the message.
static func _take_aerobraking_effects(aero: Dictionary) -> String:
	var heat := float(aero["heat"])
	var left := shield_left_mj_m2()
	var excess_heat := 0.0
	if heat > left:
		excess_heat = 1.0 if left <= 0.0 else heat / left - 1.0
	var excess_g := maxf(float(aero["peak_g"]) / AeroBraking.G_LIMIT - 1.0, 0.0)
	shield_used_mj_m2 += heat
	ship_health = maxf(ship_health - excess_heat - excess_g, 0.0)
	var text := "Aerobraking used %.0f MJ/m2 of the heat shield." % heat
	if excess_heat > 0.0 or excess_g > 0.0:
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
		return legs[leg_index_at(time_jd)]["kind"] == "transfer"   # a course change can be planned in flight
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
	var from_pos := Vector2.ZERO
	for id in from_chain:
		if str(id) == common:
			break
		from_pos += body_rel(str(id), jd)
	var to_pos := Vector2.ZERO
	for id in to_chain:
		if str(id) == common:
			break
		to_pos += body_rel(str(id), jd)
	return to_pos - from_pos


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
	var total: Vector2 = Kepler.position_at(leg["segment"], jd)
	var current := str(leg["parent"])
	# The frame is a body inside the leg's own system (for example a moon of the planet the ship orbits):
	# subtract the body's position around that planet, which keeps the full precision.
	var down := Vector2.ZERO
	var walker := frame_id
	while walker != current:
		var up: Variant = bodies[walker]["parent"]
		if up == null:
			break
		down += body_rel(walker, jd)
		walker = str(up)
	if walker == current:
		return total - down
	while current != frame_id:
		var parent_id: Variant = bodies[current]["parent"]
		if parent_id == null:
			return body_abs(str(leg["parent"]), jd) + Kepler.position_at(leg["segment"], jd) - body_abs(frame_id, jd)
		total += body_rel(current, jd)
		current = str(parent_id)
	return total


static func leg_rel_with_offsets(leg: Dictionary, frame_id: String, jd: float) -> Vector2:
	var base := _leg_rel(leg, frame_id, jd)
	if leg["kind"] != "transfer":
		return base
	var total := base
	if str(leg.get("from_body", "")) == frame_id:
		if leg.has("from_hyp"):
			var from_hyp: Dictionary = leg["from_hyp"]
			total = _blend_hyperbola(from_hyp, base, (jd - float(from_hyp["t0"])) * 86400.0)
		else:
			total += _faded(leg["from_offset"], base - (leg["from_ref"] as Vector2))
	if str(leg.get("to_body", "")) == frame_id:
		if leg.has("to_hyp"):
			var to_hyp: Dictionary = leg["to_hyp"]
			total = _blend_hyperbola(to_hyp, base, (jd - float(to_hyp["t0"])) * 86400.0)
		else:
			total += _faded(leg["to_offset"], base - (leg["to_ref"] as Vector2))
	return total


## A hyperbolic escape or approach around a body: periapsis radius rp at the angle phi (the point where the
## ship leaves / enters its orbit, so the path joins that orbit tangentially), speed at infinity v_inf (km/s).
static func _hyperbola(mu: float, rp: float, phi: float, v_inf: float) -> Dictionary:
	var v2 := v_inf * v_inf
	var a_abs := mu / v2
	return {"e": 1.0 + rp * v2 / mu, "a": a_abs, "n": sqrt(mu / pow(a_abs, 3.0)), "rp": rp, "phi": phi}


## Position on the hyperbola the given number of seconds after (positive) or before (negative) the periapsis.
static func _hyperbola_pos(h: Dictionary, seconds: float) -> Vector2:
	var e := float(h["e"])
	var a_abs := float(h["a"])
	var m := float(h["n"]) * seconds
	var anomaly := asinh(m / e)
	for _i in 40:
		anomaly -= (e * sinh(anomaly) - anomaly - m) / (e * cosh(anomaly) - 1.0)
	return Vector2(a_abs * (e - cosh(anomaly)), a_abs * sqrt(e * e - 1.0) * sinh(anomaly)).rotated(float(h["phi"]))


## Direction (angle) the ship travels along the far arm of the hyperbola.
static func _asymptote_angle(h: Dictionary, incoming: bool) -> float:
	var slope := sqrt(float(h["e"]) * float(h["e"]) - 1.0)
	return Vector2(1.0 if incoming else -1.0, slope).angle() + float(h["phi"])


## The sideways distance of the far arm of the hyperbola from a line through the body with the same direction
## (the impact parameter, as a vector): the far path is the transfer's own path moved by this much.
static func _asymptote_shift(h: Dictionary, incoming: bool) -> Vector2:
	var e := float(h["e"])
	var a_abs := float(h["a"])
	var anomaly := -12.0 if incoming else 12.0
	var far := Vector2(a_abs * (e - cosh(anomaly)), a_abs * sqrt(e * e - 1.0) * sinh(anomaly)).rotated(float(h["phi"]))
	var travel := Vector2.from_angle(_asymptote_angle(h, incoming))
	var outward := -travel if incoming else travel
	return far - outward * far.dot(outward)


## Near the body the path follows the hyperbola; far away the transfer's own path, turned by h["delta"] so
## that it comes in (goes out) along the same direction as the hyperbola, and moved sideways by h["shift"] so
## that it also lies on the same line (the path does not aim at the body's centre but passes it at the
## impact parameter and swings round it).
static func _blend_hyperbola(h: Dictionary, base: Vector2, seconds: float) -> Vector2:
	var hyperbola := _hyperbola_pos(h, seconds)
	var rp := float(h["rp"])
	var outer := clampf(6.0 * float(h["a"]), 12.0 * rp, 1.0e8)
	var weight := clampf(1.0 - (hyperbola.length() - 3.0 * rp) / (outer - 3.0 * rp), 0.0, 1.0)
	weight = weight * weight * (3.0 - 2.0 * weight)
	var far: Vector2 = base.rotated(float(h["delta"])) + (h.get("shift", Vector2.ZERO) as Vector2)
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
	if not parked.is_empty() and str(parked["parent"]) == str(a_plan["origin_id"]) and not a_plan.get("midflight", false):
		var base := _leg_rel(leg, str(a_plan["origin_id"]), float(a_plan["t_dep"]))
		leg["from_body"] = str(a_plan["origin_id"])
		leg["from_ref"] = base
		leg["from_offset"] = Kepler.position_at(parked["segment"], float(a_plan["t_dep"])) - base
		var departure_point: Vector2 = Kepler.position_at(parked["segment"], float(a_plan["t_dep"]))
		var departure_speed := (_leg_rel(leg, str(a_plan["origin_id"]), float(a_plan["t_dep"]) + 3600.0 / 86400.0) - base).length() / 3600.0
		if str(a_plan["frame"]) != str(a_plan["origin_id"]) and departure_speed > 0.01 and departure_point.length() > 1.0 \
				and base.length() < 2.0 * departure_point.length():   # the transfer must start at the body itself
			var hyp := _hyperbola(float(bodies[str(a_plan["origin_id"])]["gm_km3_s2"]), departure_point.length(), departure_point.angle(), departure_speed)
			var dt := minf(1.0, 0.25 * float(a_plan["flight_days"]))
			var far_step := _leg_rel(leg, str(a_plan["origin_id"]), float(a_plan["t_dep"]) + dt) - _leg_rel(leg, str(a_plan["origin_id"]), float(a_plan["t_dep"]) + 0.5 * dt)
			hyp["delta"] = _asymptote_angle(hyp, false) - far_step.angle()
			hyp["t0"] = float(a_plan["t_dep"])
			hyp["shift"] = _asymptote_shift(hyp, false)
			leg["from_hyp"] = hyp
	var captures: Array = a_plan.get("capture_legs", [])
	if not captures.is_empty() and str(captures[0]["parent"]) == str(a_plan["target_id"]):
		var base_end := _leg_rel(leg, str(a_plan["target_id"]), float(a_plan["t_arr"]))
		leg["to_body"] = str(a_plan["target_id"])
		leg["to_ref"] = base_end
		leg["to_offset"] = Kepler.position_at(captures[0]["segment"], float(captures[0]["t_start"])) - base_end
		var capture_point: Vector2 = Kepler.position_at(captures[0]["segment"], float(captures[0]["t_start"]))
		var energy := float(a_plan.get("arrival_energy", -1.0))
		if energy > 0.0 and str(a_plan["frame"]) != str(a_plan["target_id"]) and capture_point.length() > 1.0 \
				and base_end.length() < 2.0 * capture_point.length():
			var hyp_in := _hyperbola(float(a_plan["gm_target"]), capture_point.length(), capture_point.angle(), sqrt(2.0 * energy))
			var dt_in := minf(1.0, 0.25 * float(a_plan["flight_days"]))
			var near_step := _leg_rel(leg, str(a_plan["target_id"]), float(a_plan["t_arr"]) - 0.5 * dt_in) - _leg_rel(leg, str(a_plan["target_id"]), float(a_plan["t_arr"]) - dt_in)
			hyp_in["delta"] = _asymptote_angle(hyp_in, true) - near_step.angle()
			hyp_in["t0"] = float(a_plan["t_arr"])
			hyp_in["shift"] = _asymptote_shift(hyp_in, true)
			leg["to_hyp"] = hyp_in
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
	var captures: Array = a_plan.get("capture_legs", [])
	for i in captures.size():
		var capture_leg: Dictionary = captures[i]
		capture_leg["is_pass"] = aero_used and i < int(aero["n"])
		if aero_used and i < int(aero["n"]):
			capture_leg["morph_days"] = float(aero.get("pass_days", 0.0))
		elif aero_used:
			capture_leg["morph_days"] = burn_days(float(aero.get("final_dv", 0.0)))
		else:
			capture_leg["morph_days"] = burn_days(float(a_plan["dv_arrival"]))


## While a burn or an aerobraking pass changes the orbit, the orbit to show: periapsis, apoapsis and axis move
## linearly from the old orbit to the new one. Returns {"parent", "segment"} (a copy of the new segment with
## the shown shape), or {} when no change is going on.
static func _morph_visible(i: int) -> bool:
	# Leaving for another body is not morphed: the route is drawn instead.
	return float(legs[i].get("morph_days", 0.0)) > 0.0 and not (str(legs[i - 1]["parent"]) != str(legs[i]["parent"]) and legs[i]["kind"] == "transfer")


## The start of the next morph (before jd_end), or -1.
static func _next_morph_start(jd_end: float) -> float:
	var best := -1.0
	for i in range(1, legs.size()):
		if not _morph_visible(i):
			continue
		var t0 := float(legs[i]["t_start"]) - 0.5 * float(legs[i]["morph_days"])
		if t0 > time_jd and t0 <= jd_end and (best < 0.0 or t0 < best):
			best = t0
	return best


## True while the engine burns (a burn, not an aerobraking pass, is changing the orbit): the engine flame is shown.
static func burning_at(jd: float) -> bool:
	for i in range(1, legs.size()):
		var leg: Dictionary = legs[i]
		var span := float(leg.get("morph_days", 0.0))
		if span <= 0.0 or bool(leg.get("is_pass", false)):
			continue
		var t0 := float(leg["t_start"]) - 0.5 * span
		if jd >= t0 and jd <= t0 + span:
			return true
	return false


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
			old_segment = AeroBraking._ellipse(1.0, rp_new, maxf(wide, rp_new * 2.0), jd, float(new_segment["argument_of_periapsis_deg"]), 0.0)
		var w := (jd - t0) / span
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
	return extent


## The distance from a body's centre that its view shows at the edge of a portrait screen.
static func view_radius_km(frame_id: String, jd: float) -> float:
	return view_extent_km(frame_id, jd) / VIEW_FILL


## The body with the smallest view that contains the ship.
static func smallest_view(jd: float) -> String:
	var best := "sun"
	var best_radius := INF
	for id in bodies.keys():
		var radius := view_radius_km(str(id), jd)
		if radius < best_radius and ship_rel(str(id), jd).length() <= radius:
			best = str(id)
			best_radius = radius
	return best


## If the ship gets inside a smaller view than the one it is in now before jd_end, when it gets in (else -1).
## The whole interval is sampled: at a high warp a step can carry the ship through a small view (Mars) and out
## again, so comparing only the two ends would miss it.
static func _next_view_entry(jd_end: float) -> float:
	var now_radius := view_radius_km(smallest_view(time_jd), time_jd)
	var candidates: Array = []
	for id in bodies.keys():
		if view_radius_km(str(id), time_jd) < now_radius:
			candidates.append(str(id))
	if candidates.is_empty():
		return -1.0
	var span := jd_end - time_jd
	var samples := clampi(ceili(span / 0.01), 1, 160)
	var previous := time_jd
	for k in range(1, samples + 1):
		var t := time_jd + span * float(k) / float(samples)
		for id in candidates:
			if ship_rel(id, t).length() <= view_radius_km(id, t):
				var low := previous
				var high := t
				for _i in 24:
					var middle := 0.5 * (low + high)
					if ship_rel(id, middle).length() <= view_radius_km(id, middle):
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
