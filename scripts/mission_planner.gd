class_name MissionPlanner
extends RefCounted
## Plans a mission from the body the ship is orbiting to a destination, using the transfers in
## TransferPlanner (patched conics: Hohmann-style legs between bodies, with the burns estimated
## at each sphere of influence). Everything is 2D, so inclinations are ignored.

const SYNODIC_SEARCH_DAYS := 2000.0   # search period for windows between planets
const ORBIT_SEARCH_PERIODS := 1.5     # for a ship in orbit around the origin: how many orbits to search
const NEARLY_CIRCULAR := 0.05         # if periapsis and apoapsis differ by less than this share of the apoapsis, the axis is ignored
const AXIS_TOLERANCE_DEG := 10.0      # a departure from an elliptical orbit may be this far off the periapsis direction


## The destinations offered at a body: the bodies in its own sphere of influence (its moons, and
## if it is a moon, its planet and the planet's other moons), plus the other planets and dwarf
## planets that orbit the Sun.
static func destinations(origin_id: String) -> Array:
	var bodies := GameState.bodies
	var children := GameState.children
	var result: Array = []
	for id in children[origin_id]:
		result.append(id)
	var origin_parent: Variant = bodies[origin_id]["parent"]
	if origin_parent != null and origin_parent != "sun":
		result.append(origin_parent)
		for id in children[origin_parent]:
			if id != origin_id:
				result.append(id)
	for id in children["sun"]:
		if id != origin_id and not result.has(id):
			result.append(id)
	return result


## The default target orbit of a body: circular, at the body's default altitude (as altitudes above the surface).
static func default_target_orbit(target_id: String) -> Dictionary:
	var altitude := float(GameState.bodies[target_id]["default_orbit_altitude_km"])
	return {"rp_alt_km": altitude, "ra_alt_km": altitude + OrbitControl.EPS, "offset_deg": 0.0}


## Plans the next departure from the orbit orbit_segment around origin_id to target_id, not before t_start,
## into the target orbit {"rp_alt_km", "ra_alt_km", "offset_deg"} (altitudes above the surface; the default
## orbit of the body if empty). Returns the plan, or {"error": text} if no plan is possible.
static func make_plan(origin_id: String, orbit_segment: Dictionary, target_id: String, t_start: float,
		target_orbit: Dictionary = {}) -> Dictionary:
	var bodies := GameState.bodies
	var origin: Dictionary = bodies[origin_id]
	var target: Dictionary = bodies[target_id]
	var origin_parent: Variant = origin["parent"]
	var target_parent: Variant = target["parent"]
	var origin_gm := float(origin["gm_km3_s2"])
	var target_gm := float(target["gm_km3_s2"])
	# The ship leaves from the periapsis of its orbit (the same as the radius for a circular orbit).
	var origin_orbit_radius := float(orbit_segment["semi_major_axis_km"]) * (1.0 - float(orbit_segment["eccentricity"]))
	var origin_apoapsis := float(orbit_segment["semi_major_axis_km"]) * (1.0 + float(orbit_segment["eccentricity"]))
	var origin_circular := OrbitControl.is_circular(origin_orbit_radius, origin_apoapsis)
	var dv_circularize := 0.0
	var orbit := default_target_orbit(target_id)
	orbit.merge(target_orbit, true)
	var pair := OrbitControl.normalise(float(orbit["rp_alt_km"]), float(orbit["ra_alt_km"]), "rp")
	orbit["rp_alt_km"] = pair.x
	orbit["ra_alt_km"] = pair.y
	var rp_t := float(target["radius_km"]) + pair.x
	var ra_t := float(target["radius_km"]) + pair.y
	var capture_radius := maxf(rp_t, 1.0)   # the arrival radius of a transfer to the central body
	var arrival_energy := 0.0
	var target_fn := func(t: float) -> Vector2: return GameState.body_rel(target_id, t)

	var frame := ""
	var transfer: Dictionary = {}
	var dv_departure := 0.0
	var dv_arrival := 0.0
	var capture_phase_deg := 0.0
	var aimable := true   # arriving from outside the sphere of influence: the periapsis direction can be aimed

	if target_parent == origin_id:
		# Down the gravity well's other side: to a moon of the body we orbit. The ship can leave from any
		# point of its orbit, so the search runs over its orbit period.
		frame = origin_id
		var period_days := 360.0 / float(orbit_segment["mean_motion_deg_per_day"])
		var origin_fn := func(t: float) -> Vector2: return Kepler.position_at(orbit_segment, t)
		transfer = TransferPlanner.find_window(origin_gm, origin_fn, target_fn, t_start,
				period_days * ORBIT_SEARCH_PERIODS, period_days / 180.0)
		if transfer.is_empty():
			return {"error": "No launch window found."}
		dv_departure = TransferPlanner.departure_dv_bound(transfer, origin_gm)
		var v_inf := float(TransferPlanner.arrival_dv(transfer, target_fn, target_gm, capture_radius)["v_inf_kms"])
		arrival_energy = 0.5 * v_inf * v_inf

	elif origin_parent == target_id:
		# From a moon to its own planet: no window, the ship can leave at once.
		frame = target_id
		var origin_fn := func(t: float) -> Vector2: return GameState.body_rel(origin_id, t)
		transfer = TransferPlanner.transfer_to_central(target_gm, origin_fn, t_start, capture_radius)
		var origin_velocity := TransferPlanner.velocity_kms(origin_fn, t_start)
		dv_departure = TransferPlanner.departure_dv_escape(transfer, origin_velocity, origin_gm, origin_orbit_radius)
		if not origin_circular and origin_apoapsis - origin_orbit_radius >= NEARLY_CIRCULAR * origin_apoapsis:
			var needed_axis := TransferPlanner.escape_axis_deg(transfer, origin_velocity, origin_gm, origin_orbit_radius)
			var turn := absf(wrapf(float(orbit_segment["argument_of_periapsis_deg"]) - needed_axis, -180.0, 180.0))
			if turn > AXIS_TOLERANCE_DEG:
				# The periapsis points the wrong way: circularise at the apoapsis first, then leave from there.
				dv_circularize = sqrt(origin_gm / origin_apoapsis) - sqrt(2.0 * origin_gm * origin_orbit_radius \
						/ (origin_apoapsis * (origin_orbit_radius + origin_apoapsis)))
				dv_departure = dv_circularize + TransferPlanner.departure_dv_escape(transfer, origin_velocity, origin_gm, origin_apoapsis)
		arrival_energy = -target_gm / (2.0 * float(transfer["a"]))   # energy of the transfer orbit itself
		capture_phase_deg = rad_to_deg((transfer["origin"] as Vector2).angle() + PI)
		aimable = false

	elif origin_parent != null and origin_parent == target_parent:
		# Two bodies orbiting the same body: two planets, or two moons of one planet.
		frame = str(origin_parent)
		var frame_gm := float(bodies[frame]["gm_km3_s2"])
		var origin_fn := func(t: float) -> Vector2: return GameState.body_rel(origin_id, t)
		var horizon := SYNODIC_SEARCH_DAYS
		var step := 1.0
		if frame != "sun":
			var origin_period := _period_days(origin_id)
			var target_period := _period_days(target_id)
			horizon = 20.0 * maxf(origin_period, target_period)
			step = minf(origin_period, target_period) / 100.0
		transfer = TransferPlanner.find_window(frame_gm, origin_fn, target_fn, t_start, horizon, step)
		if transfer.is_empty():
			return {"error": "No launch window found."}
		var origin_velocity := TransferPlanner.velocity_kms(origin_fn, float(transfer["t_dep"]))
		dv_departure = TransferPlanner.departure_dv_escape(transfer, origin_velocity, origin_gm, origin_orbit_radius)
		if not origin_circular and origin_apoapsis - origin_orbit_radius >= NEARLY_CIRCULAR * origin_apoapsis:
			var needed_axis := TransferPlanner.escape_axis_deg(transfer, origin_velocity, origin_gm, origin_orbit_radius)
			var turn := absf(wrapf(float(orbit_segment["argument_of_periapsis_deg"]) - needed_axis, -180.0, 180.0))
			if turn > AXIS_TOLERANCE_DEG:
				# The periapsis points the wrong way: circularise at the apoapsis first, then leave from there.
				dv_circularize = sqrt(origin_gm / origin_apoapsis) - sqrt(2.0 * origin_gm * origin_orbit_radius \
						/ (origin_apoapsis * (origin_orbit_radius + origin_apoapsis)))
				dv_departure = dv_circularize + TransferPlanner.departure_dv_escape(transfer, origin_velocity, origin_gm, origin_apoapsis)
		var v_inf := float(TransferPlanner.arrival_dv(transfer, target_fn, target_gm, capture_radius)["v_inf_kms"])
		arrival_energy = 0.5 * v_inf * v_inf

	elif origin_parent != null and origin_parent != "sun" and target_parent == "sun":
		# From a moon to another planet: the transfer starts at the moon's planet.
		frame = "sun"
		var planet_id := str(origin_parent)
		var sun_gm := float(bodies["sun"]["gm_km3_s2"])
		var planet_fn := func(t: float) -> Vector2: return GameState.body_rel(planet_id, t)
		transfer = TransferPlanner.find_window(sun_gm, planet_fn, target_fn, t_start, SYNODIC_SEARCH_DAYS, 1.0)
		if transfer.is_empty():
			return {"error": "No launch window found."}
		var t_dep := float(transfer["t_dep"])
		var planet_velocity := TransferPlanner.velocity_kms(planet_fn, t_dep)
		var moon_orbit_radius := GameState.body_rel(origin_id, t_dep).length()
		dv_departure = TransferPlanner.departure_dv_from_moon(transfer, planet_velocity,
				float(bodies[planet_id]["gm_km3_s2"]), moon_orbit_radius, origin_gm, origin_orbit_radius)
		var v_inf := float(TransferPlanner.arrival_dv(transfer, target_fn, target_gm, capture_radius)["v_inf_kms"])
		arrival_energy = 0.5 * v_inf * v_inf

	else:
		return {"error": "No route to %s from here yet." % target["name"]}

	dv_arrival = TransferPlanner.capture_dv(target_gm, arrival_energy, rp_t, ra_t)
	var plan := {
		"origin_id": origin_id,
		"target_id": target_id,
		"target_name": target["name"],
		"frame": frame,
		"t_dep": float(transfer["t_dep"]),
		"t_arr": float(transfer["t_arr"]),
		"flight_days": float(transfer["flight_days"]),
		"dv_departure": dv_departure,
		"dv_arrival": dv_arrival,
		"transfer_segment": TransferPlanner.transfer_segment(transfer, float(transfer["gm"])),
		"target_orbit": orbit,
		"rp_t": rp_t,
		"ra_t": ra_t,
		"offset_deg": float(orbit["offset_deg"]),
		"aimable": aimable,
		"dv_circularize": dv_circularize,
		"arrival_energy": arrival_energy,
		"committed": false,
		"departure_done": false,
		"arrival_seen": false,
		"capture_phase_deg": capture_phase_deg,
		"gm_target": target_gm,
		"dv_capture": dv_arrival,
	}
	AeroBraking.setup_plan(plan)   # adds the aerobraking data and the capture legs
	return plan


static func _period_days(id: String) -> float:
	var segments: Array = GameState.bodies[id]["orbit_segments"]
	return 360.0 / float(segments[0]["mean_motion_deg_per_day"])
