class_name GameState
extends RefCounted
## The shared state of the running game, kept in static variables so that it survives switching
## between screens (scenes) and needs no autoload. Every screen reads and writes it directly:
## the game clock, the loaded body data, the ship and its mission plan.

const DATA_PATH := "res://data/bodies.json"
const FACILITIES_PATH := "res://data/facilities.json"
const DESIGN_PATH := "user://ship_design.json"  # written by the ship design screen
const DEFAULT_SHIP_DV_KMS := 10.0
const DEFAULT_SHIP_PROPELLANT_KG := 120000.0
const DEFAULT_SHIP_VE_MS := 3900.0   # effective exhaust velocity of the default ship
const WARP_STEPS := [1.0 / 86400.0, 1.0 / 1440.0, 1.0 / 24.0, 1.0, 10.0, 100.0, 1000.0]  # game days per real second
const WARP_LABELS := ["real time", "1 min/s", "1 h/s", "1 day/s", "10 days/s", "100 days/s", "1000 days/s"]

# Body data (loaded once from bodies.json).
static var data_loaded := false
static var bodies: Dictionary = {}    # id -> body dictionary
static var children: Dictionary = {}  # id -> array of child ids
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
static var message := ""
static var ship_name := "Ship"

# The ship's tanks: a delta-v tank. The design gives a capacity in kg of propellant and in km/s; the
# two are linked by the rocket equation for an equivalent single stage (effective exhaust velocity and
# dry mass), so burning delta-v uses up propellant mass and refuelling restores it.
static var ship_dv_kms := DEFAULT_SHIP_DV_KMS           # capacity
static var ship_fuel_capacity_kg := DEFAULT_SHIP_PROPELLANT_KG
static var ship_ve_ms := DEFAULT_SHIP_VE_MS
static var ship_dry_kg := DEFAULT_SHIP_PROPELLANT_KG / (exp(DEFAULT_SHIP_DV_KMS * 1000.0 / DEFAULT_SHIP_VE_MS) - 1.0)
static var ship_fuel_kg := -1.0                         # current propellant; negative = not set yet
static var ship_burned := false                         # true once the ship has used any delta-v
static var ship_dv_source := "default value; design a ship on the ship design screen"

# Facilities: id -> state dictionary (definition values plus stock_kg and last_jd).
static var facilities: Dictionary = {}
static var facility_defs: Array = []

# Per-screen choices that are kept when switching screens.
static var mission_frame_index := 0
static var mission_target_id := "moon"


## Loads the body data once and makes sure the game has been started. Returns false if the data is missing.
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
		facility_defs = facility_data["facilities"] if typeof(facility_data) == TYPE_DICTIONARY else []
		data_loaded = true
	if not initialized:
		reset_mission()
	load_ship_design()
	return true


## Back to the start: time paused at the start date, the ship in a parking orbit around Earth, no plan.
static func reset_mission() -> void:
	initialized = true
	time_jd = start_jd
	paused = true
	warp_index = 0
	plan = {}
	message = ""
	var earth_gm := float(bodies["earth"]["gm_km3_s2"])
	var radius := float(bodies["earth"]["radius_km"]) + float(bodies["earth"]["default_orbit_altitude_km"])
	var parking := TransferPlanner.circular_segment(radius, earth_gm, start_jd, 0.0)
	legs = [{"parent": "earth", "segment": parking, "t_start": start_jd, "label": "Orbit around Earth", "kind": "orbit"}]
	ship_burned = false
	ship_fuel_kg = ship_fuel_capacity_kg
	facilities = {}
	for def in facility_defs:
		var state: Dictionary = (def as Dictionary).duplicate()
		state["stock_kg"] = float(def["start_stock_kg"])
		state["last_jd"] = start_jd
		facilities[def["id"]] = state


## Reads the ship's name, delta-v and tank data from the ship design screen's saved design.
static func load_ship_design() -> void:
	if FileAccess.file_exists(DESIGN_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("total_dv_ms"):
			ship_dv_kms = float(parsed["total_dv_ms"]) / 1000.0
			ship_dv_source = "from the ship design screen"
			ship_name = str(parsed.get("name", ship_name))
			if parsed.has("propellant_kg") and parsed.has("ve_eff_ms"):
				ship_fuel_capacity_kg = float(parsed["propellant_kg"])
				ship_ve_ms = float(parsed["ve_eff_ms"])
				ship_dry_kg = float(parsed["dry_eff_kg"])
	# Until the ship has used any fuel the tanks are full; afterwards a new design can only lower the level.
	if not ship_burned or ship_fuel_kg < 0.0:
		ship_fuel_kg = ship_fuel_capacity_kg
	else:
		ship_fuel_kg = minf(ship_fuel_kg, ship_fuel_capacity_kg)


## Propellant mass (kg) that corresponds to a delta-v (km/s) for the equivalent single stage.
static func fuel_for_dv(dv_kms: float) -> float:
	return ship_dry_kg * (exp(dv_kms * 1000.0 / ship_ve_ms) - 1.0)


## Delta-v (km/s) that a propellant mass (kg) gives.
static func dv_for_fuel(fuel_kg: float) -> float:
	return ship_ve_ms * log(1.0 + fuel_kg / ship_dry_kg) / 1000.0


static func dv_left_kms() -> float:
	return dv_for_fuel(ship_fuel_kg)


## Uses up delta-v from the tanks.
static func apply_burn(dv_kms: float) -> void:
	ship_burned = true
	ship_fuel_kg = fuel_for_dv(maxf(dv_left_kms() - dv_kms, 0.0))


# ---------------------------------------------------------------- clock

## Advances the game clock by delta real seconds. On arrival the time flow drops to real time.
static func advance(delta: float) -> void:
	if not paused:
		time_jd += delta * float(WARP_STEPS[warp_index])
	if not plan.is_empty() and plan["committed"]:
		if not plan["departure_done"] and time_jd >= float(plan["t_dep"]):
			plan["departure_done"] = true
			apply_burn(float(plan["dv_departure"]))
		if not plan["arrival_seen"] and time_jd >= float(plan["t_arr"]):
			plan["arrival_seen"] = true
			apply_burn(float(plan["dv_arrival"]))
			warp_index = 0
	_update_facilities()


## Facilities produce continuously: output per day is the peak output times the availability of the
## resource on the body, up to the storage capacity.
static func _update_facilities() -> void:
	for id in facilities:
		var facility: Dictionary = facilities[id]
		var days := time_jd - float(facility["last_jd"])
		if days <= 0.0:
			continue
		facility["last_jd"] = time_jd
		var resource: Dictionary = bodies[facility["body"]]["resources"].get(facility["resource"], {})
		var availability := float(resource.get("availability", 0.0))
		var output_per_day := float(facility["peak_output_kg_per_day"]) * availability * float(facility["conversion"])
		facility["stock_kg"] = minf(float(facility["stock_kg"]) + output_per_day * days, float(facility["storage_capacity_kg"]))


## Production per day (kg) of a facility right now.
static func facility_output_per_day(facility: Dictionary) -> float:
	var resource: Dictionary = bodies[facility["body"]]["resources"].get(facility["resource"], {})
	return float(facility["peak_output_kg_per_day"]) * float(resource.get("availability", 0.0)) * float(facility["conversion"])


## The facility at a body, or an empty dictionary.
static func facility_at(body_id: String) -> Dictionary:
	for id in facilities:
		if facilities[id]["body"] == body_id:
			return facilities[id]
	return {}


## True while the ship is on a transfer orbit between bodies.
static func ship_in_transit() -> bool:
	return legs[leg_index_at(time_jd)]["kind"] == "transfer"


## The leg the ship is parked on (an orbit around a body), or an empty dictionary during a transfer.
static func parked_leg() -> Dictionary:
	var leg: Dictionary = legs[leg_index_at(time_jd)]
	return leg if leg["kind"] == "orbit" else {}


## Fills the ship's tanks from the facility at the ship's location. Returns the propellant taken (kg).
static func refuel() -> float:
	var leg := parked_leg()
	if leg.is_empty():
		return 0.0
	var facility := facility_at(str(leg["parent"]))
	if facility.is_empty():
		return 0.0
	var amount := minf(float(facility["stock_kg"]), ship_fuel_capacity_kg - ship_fuel_kg)
	if amount <= 0.0:
		return 0.0
	facility["stock_kg"] = float(facility["stock_kg"]) - amount
	ship_fuel_kg += amount
	return amount


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
static func ship_rel(frame_id: String, jd: float) -> Vector2:
	var leg: Dictionary = legs[leg_index_at(jd)]
	var total: Vector2 = Kepler.position_at(leg["segment"], jd)
	var current := str(leg["parent"])
	while current != frame_id:
		var parent_id: Variant = bodies[current]["parent"]
		if parent_id == null:
			return ship_abs(jd) - body_abs(frame_id, jd)
		total += body_rel(current, jd)
		current = str(parent_id)
	return total


## Position (km) of the ship relative to the Sun.
static func ship_abs(jd: float) -> Vector2:
	var leg: Dictionary = legs[leg_index_at(jd)]
	return body_abs(str(leg["parent"]), jd) + Kepler.position_at(leg["segment"], jd)
