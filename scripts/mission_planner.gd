class_name MissionPlanner
extends RefCounted
## Plans a mission from the body the ship is orbiting to a destination, using the transfers in
## TransferPlanner (patched conics: Hohmann-style legs between bodies, with the burns estimated
## at each sphere of influence). Everything is 2D, so inclinations are ignored.

const SYNODIC_SEARCH_DAYS := 2000.0   # search period for windows between planets
const ORBIT_SEARCH_PERIODS := 1.5     # for a ship in orbit around the origin: how many orbits to search


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


## Plans the next departure from the circular orbit orbit_segment around origin_id to target_id, not
## before t_start. Returns the plan, or {"error": text} if no plan is possible.
static func make_plan(origin_id: String, orbit_segment: Dictionary, target_id: String, t_start: float) -> Dictionary:
	var bodies := GameState.bodies
	var origin: Dictionary = bodies[origin_id]
	var target: Dictionary = bodies[target_id]
	var origin_parent: Variant = origin["parent"]
	var target_parent: Variant = target["parent"]
	var origin_gm := float(origin["gm_km3_s2"])
	var target_gm := float(target["gm_km3_s2"])
	var origin_orbit_radius := float(orbit_segment["semi_major_axis_km"])
	var capture_radius := float(target["radius_km"]) + float(target["default_orbit_altitude_km"])
	var target_fn := func(t: float) -> Vector2: return GameState.body_rel(target_id, t)

	var frame := ""
	var transfer: Dictionary = {}
	var dv_departure := 0.0
	var dv_arrival := 0.0
	var capture_phase_deg := 0.0

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
		dv_arrival = float(TransferPlanner.arrival_dv(transfer, target_fn, target_gm, capture_radius)["dv_kms"])

	elif origin_parent == target_id:
		# From a moon to its own planet: no window, the ship can leave at once.
		frame = target_id
		var origin_fn := func(t: float) -> Vector2: return GameState.body_rel(origin_id, t)
		transfer = TransferPlanner.transfer_to_central(target_gm, origin_fn, t_start, capture_radius)
		var origin_velocity := TransferPlanner.velocity_kms(origin_fn, t_start)
		dv_departure = TransferPlanner.departure_dv_escape(transfer, origin_velocity, origin_gm, origin_orbit_radius)
		dv_arrival = TransferPlanner.arrival_dv_central(transfer)
		capture_phase_deg = rad_to_deg((transfer["origin"] as Vector2).angle() + PI)

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
		dv_arrival = float(TransferPlanner.arrival_dv(transfer, target_fn, target_gm, capture_radius)["dv_kms"])

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
		dv_arrival = float(TransferPlanner.arrival_dv(transfer, target_fn, target_gm, capture_radius)["dv_kms"])

	else:
		return {"error": "No route to %s from here yet." % target["name"]}

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
		"capture_segment": TransferPlanner.circular_segment(capture_radius, target_gm, float(transfer["t_arr"]), capture_phase_deg),
		"committed": false,
		"departure_done": false,
		"arrival_seen": false,
		"capture_radius": capture_radius,
		"capture_phase_deg": capture_phase_deg,
		"gm_target": target_gm,
		"dv_capture": dv_arrival,
	}
	AeroBraking.setup_plan(plan)   # adds the aerobraking data and the capture legs
	return plan


static func _period_days(id: String) -> float:
	var segments: Array = GameState.bodies[id]["orbit_segments"]
	return 360.0 / float(segments[0]["mean_motion_deg_per_day"])
