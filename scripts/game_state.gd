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
static var cargo: Array = []   # facility type ids of the kits the ship carries

# The ship's tanks: a delta-v tank. The design gives a capacity in kg of propellant and in km/s; the
# two are linked by the rocket equation for an equivalent single stage (effective exhaust velocity and
# dry mass), so burning delta-v uses up propellant mass and refuelling restores it.
static var ship_dv_kms := DEFAULT_SHIP_DV_KMS           # capacity
static var ship_payload_kg := DEFAULT_SHIP_PAYLOAD_KG   # cargo capacity
static var ship_fuel_capacity_kg := DEFAULT_SHIP_PROPELLANT_KG
static var ship_ve_ms := DEFAULT_SHIP_VE_MS
static var ship_dry_kg := DEFAULT_SHIP_PROPELLANT_KG / (exp(DEFAULT_SHIP_DV_KMS * 1000.0 / DEFAULT_SHIP_VE_MS) - 1.0)
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
	message = ""
	cargo = []
	var earth_gm := float(bodies["earth"]["gm_km3_s2"])
	var radius := float(bodies["earth"]["radius_km"]) + float(bodies["earth"]["default_orbit_altitude_km"])
	var parking := TransferPlanner.circular_segment(radius, earth_gm, start_jd, 0.0)
	legs = [{"parent": "earth", "segment": parking, "t_start": start_jd, "label": "Orbit around Earth", "kind": "orbit"}]
	ship_burned = false
	ship_fuel_kg = ship_fuel_capacity_kg
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
				ship_dry_kg = float(parsed["dry_eff_kg"])
	# Until the ship has used any fuel the tanks are full; afterwards a new design can only lower the level.
	if not ship_burned or ship_fuel_kg < 0.0:
		ship_fuel_kg = ship_fuel_capacity_kg
	else:
		ship_fuel_kg = minf(ship_fuel_kg, ship_fuel_capacity_kg)
	# Kits that no longer fit into a smaller payload are taken off the ship and refunded.
	while not cargo.is_empty() and cargo_mass_kg() > ship_payload_kg:
		var type_id: String = cargo.pop_back()
		budget_eur += float(facility_types[type_id]["kit"]["cost_eur"])


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

## Advances the game clock by delta real seconds. On departure and arrival the burns are taken from
## the tanks; on arrival the plan is finished and the time flow drops to real time.
static func advance(delta: float) -> void:
	if not paused:
		time_jd += delta * float(WARP_STEPS[warp_index])
	if not plan.is_empty() and plan["committed"]:
		if not plan["departure_done"] and time_jd >= float(plan["t_dep"]):
			plan["departure_done"] = true
			apply_burn(float(plan["dv_departure"]))
		if time_jd >= float(plan["t_arr"]):
			apply_burn(float(plan["dv_arrival"]))
			message = "Arrived at %s." % plan["target_name"]
			plan = {}
			warp_index = 0
	_update_facilities()


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
	return legs[leg_index_at(time_jd)]["kind"] == "transfer"


## The mission planner is offered in a system that contains a ship that can launch: the ship is in
## orbit around the body in view, or a plan is waiting.
static func planner_available(focus_id: String) -> bool:
	var body := ship_body()
	if body == "":
		return false
	return body == focus_id or bodies[body]["parent"] == focus_id or not plan.is_empty()


## The ship designer is offered in a system with a shipbuilding facility, when the ship is at it.
static func design_available(focus_id: String) -> bool:
	return ship_body() == focus_id and not facility_of_kind(focus_id, "shipyard").is_empty()


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
