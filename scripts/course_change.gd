class_name CourseChange
extends RefCounted
## Changing the mission while the ship is in flight. The ship's position and velocity on its current
## transfer are known, so the planner solves Lambert's problem (the conic through two points in a given time)
## from the ship to the chosen destination for many flight times and takes the cheapest total delta-v (the
## course-change burn plus the capture at the destination). Destinations are the bodies that orbit the body
## the ship is flying around (for example the Moon on a transfer around Earth, any planet on a transfer
## around the Sun). Everything is 2D and counter-clockwise; hyperbolic and retrograde solutions are skipped.

const SAMPLES := 160
const REFINE_SAMPLES := 60


## Stumpff functions: returns Vector2(C, S).
static func _stumpff(z: float) -> Vector2:
	if z > 1.0e-6:
		var root := sqrt(z)
		return Vector2((1.0 - cos(root)) / z, (root - sin(root)) / (root * z))
	if z < -1.0e-6:
		var root := sqrt(-z)
		return Vector2((cosh(root) - 1.0) / -z, (sinh(root) - root) / (root * -z))
	return Vector2(0.5, 1.0 / 6.0)


## Lambert's problem for a counter-clockwise transfer from r1v to r2v (km, relative to the central body) in
## tof seconds. Returns {"v1": Vector2, "v2": Vector2} (km/s) or {} if there is no solution.
static func lambert(mu: float, r1v: Vector2, r2v: Vector2, tof: float) -> Dictionary:
	var r1 := r1v.length()
	var r2 := r2v.length()
	var cos_dnu := clampf(r1v.dot(r2v) / (r1 * r2), -1.0, 1.0)
	var dnu := acos(cos_dnu)
	if r1v.cross(r2v) < 0.0:
		dnu = TAU - dnu
	if 1.0 - cos_dnu < 1.0e-12:
		return {}
	var a_coef := sin(dnu) * sqrt(r1 * r2 / (1.0 - cos_dnu))
	if absf(a_coef) < 1.0e-9:
		return {}
	var sqrt_mu := sqrt(mu)
	var z_hi := TAU * TAU - 1.0e-3
	var z_lo := -100.0
	for _i in 400:
		if _y(z_lo, r1, r2, a_coef) > 0.0 or z_lo >= z_hi:
			break
		z_lo += 1.0
	if _y(z_lo, r1, r2, a_coef) <= 0.0:
		return {}
	if _f(z_lo, r1, r2, a_coef, sqrt_mu, tof) > 0.0 or _f(z_hi, r1, r2, a_coef, sqrt_mu, tof) < 0.0:
		return {}
	for _i in 100:
		var middle := 0.5 * (z_lo + z_hi)
		if _y(middle, r1, r2, a_coef) <= 0.0 or _f(middle, r1, r2, a_coef, sqrt_mu, tof) < 0.0:
			z_lo = middle
		else:
			z_hi = middle
	var z := 0.5 * (z_lo + z_hi)
	var y := _y(z, r1, r2, a_coef)
	if y <= 0.0:
		return {}
	var f := 1.0 - y / r1
	var g := a_coef * sqrt(y / mu)
	var g_dot := 1.0 - y / r2
	return {"v1": (r2v - r1v * f) / g, "v2": (r2v * g_dot - r1v) / g}


static func _y(z: float, r1: float, r2: float, a_coef: float) -> float:
	var cs := _stumpff(z)
	return r1 + r2 + a_coef * (z * cs.y - 1.0) / sqrt(maxf(cs.x, 1.0e-12))


static func _f(z: float, r1: float, r2: float, a_coef: float, sqrt_mu: float, tof: float) -> float:
	var cs := _stumpff(z)
	var y := _y(z, r1, r2, a_coef)
	if y <= 0.0:
		return -1.0e30
	return pow(y / maxf(cs.x, 1.0e-12), 1.5) * cs.y + a_coef * sqrt(y) - sqrt_mu * tof


## Orbit segment (same format as the body data) of the ellipse through position r with velocity v at epoch_jd,
## or {} if it is not a counter-clockwise ellipse.
static func state_segment(mu: float, r: Vector2, v: Vector2, epoch_jd: float) -> Dictionary:
	var rm := r.length()
	var vm2 := v.length_squared()
	var energy := 0.5 * vm2 - mu / rm
	if energy >= 0.0 or r.cross(v) <= 0.0:
		return {}
	var a := -mu / (2.0 * energy)
	var ecc_vector := (r * (vm2 - mu / rm) - v * r.dot(v)) / mu
	var e := ecc_vector.length()
	if e >= 0.999:
		return {}
	var omega := ecc_vector.angle() if e > 1.0e-9 else r.angle()
	var nu := wrapf(r.angle() - omega, -PI, PI)
	var ecc_anomaly := 2.0 * atan2(sqrt(1.0 - e) * sin(0.5 * nu), sqrt(1.0 + e) * cos(0.5 * nu))
	var mean_anomaly := ecc_anomaly - e * sin(ecc_anomaly)
	return {
		"epoch_jd": epoch_jd,
		"semi_major_axis_km": a,
		"eccentricity": e,
		"longitude_of_ascending_node_deg": 0.0,
		"argument_of_periapsis_deg": rad_to_deg(omega),
		"mean_anomaly_deg": rad_to_deg(mean_anomaly),
		"mean_motion_deg_per_day": TransferPlanner.mean_motion_deg_per_day(mu, a),
	}


## The bodies the ship can be sent to from where it is flying: those that orbit the body it is flying around.
static func destinations() -> Array:
	var leg: Dictionary = GameState.legs[GameState.leg_index_at(GameState.time_jd)]
	if leg["kind"] != "transfer":
		return []
	var frame := str(leg["parent"])
	var result: Array = (GameState.children[frame] as Array).duplicate()
	if frame != "sun":
		result.append(frame)   # a new orbit around the body the ship is flying to
	return result


## Plans a course change at t_burn to target_id, into the target orbit (see MissionPlanner.make_plan). The plan
## has the same fields as a plan from MissionPlanner, plus "midflight": true.
static func make_plan(target_id: String, t_burn: float, target_orbit: Dictionary = {}) -> Dictionary:
	var bodies := GameState.bodies
	var leg: Dictionary = GameState.legs[GameState.leg_index_at(GameState.time_jd)]
	if leg["kind"] != "transfer":
		return {"error": "The course cannot be changed during aerobraking."}
	var frame := str(leg["parent"])
	var target: Dictionary = bodies[target_id]
	if target["parent"] != frame and target_id != frame:
		return {"error": "%s cannot be reached from this flight yet." % target["name"]}
	var mu := float(bodies[frame]["gm_km3_s2"])
	var target_gm := float(target["gm_km3_s2"])
	var segment: Dictionary = leg["segment"]
	var ship_fn := func(t: float) -> Vector2: return Kepler.position_at(segment, t)
	var target_fn := func(t: float) -> Vector2: return GameState.body_rel(target_id, t)
	var r1: Vector2 = ship_fn.call(t_burn)
	var ship_velocity := TransferPlanner.velocity_kms(ship_fn, t_burn)

	var orbit := MissionPlanner.default_target_orbit(target_id)
	orbit.merge(target_orbit, true)
	var pair := OrbitControl.normalise(float(orbit["rp_alt_km"]), float(orbit["ra_alt_km"]), "rp")
	orbit["rp_alt_km"] = pair.x
	orbit["ra_alt_km"] = pair.y
	var rp_t := float(target["radius_km"]) + pair.x
	var ra_t := float(target["radius_km"]) + pair.y
	var frame_radius := float(bodies[frame]["radius_km"])
	if target_id == frame:
		return _central_plan(frame, t_burn, r1, ship_velocity, mu, orbit, rp_t, ra_t)

	var reference_days := PI * sqrt(pow(0.5 * (r1.length() + (target_fn.call(t_burn) as Vector2).length()), 3.0) / mu) / 86400.0
	var best: Dictionary = {}
	var low := 0.1 * reference_days
	var high := 3.0 * reference_days
	for round_index in 2:
		var samples := SAMPLES if round_index == 0 else REFINE_SAMPLES
		for i in samples + 1:
			var tof_days := low * pow(high / low, float(i) / float(samples))
			var candidate := _evaluate(mu, r1, ship_velocity, target_fn, target_id, target_gm, t_burn, tof_days,
					rp_t, ra_t, frame_radius)
			if not candidate.is_empty() and (best.is_empty() or float(candidate["cost"]) < float(best["cost"])):
				best = candidate
		if best.is_empty():
			break
		low = float(best["tof_days"]) * 0.93
		high = float(best["tof_days"]) * 1.07
	if best.is_empty():
		return {"error": "No course to %s was found from here." % target["name"]}
	var plan := {
		"origin_id": frame,
		"target_id": target_id,
		"target_name": target["name"],
		"frame": frame,
		"t_dep": t_burn,
		"t_arr": t_burn + float(best["tof_days"]),
		"flight_days": float(best["tof_days"]),
		"dv_departure": float(best["dv_burn"]),
		"dv_arrival": float(best["dv_capture"]),
		"transfer_segment": best["segment"],
		"committed": false,
		"departure_done": false,
		"arrival_seen": false,
		"target_orbit": orbit,
		"rp_t": rp_t,
		"ra_t": ra_t,
		"offset_deg": float(orbit["offset_deg"]),
		"aimable": true,
		"dv_circularize": 0.0,
		"arrival_energy": float(best["energy"]),
		"capture_phase_deg": 0.0,
		"gm_target": target_gm,
		"dv_capture": float(best["dv_capture"]),
		"midflight": true,
	}
	AeroBraking.setup_plan(plan)   # the aerobraking data, the capture legs, the outcome and the end time
	return plan


## A course change to a new orbit around the body the ship is flying to (for example a different periapsis on
## the way back to Earth). The new path has the periapsis rp_t; the burn is the smallest one over all the ways
## to turn the current path into such a path (the angle of its periapsis is free).
static func _central_plan(frame: String, t_burn: float, r1: Vector2, ship_velocity: Vector2, mu: float,
		orbit: Dictionary, rp_t: float, ra_t: float) -> Dictionary:
	var r1m := r1.length()
	if rp_t >= r1m * 0.999:
		return {"error": "The ship is already closer than that periapsis."}
	var radial := r1.normalized()
	var tangential := radial.rotated(PI / 2.0)
	var best_dv := 1.0e30
	var best_velocity := Vector2.ZERO
	for i in range(1, 360):
		var nu := -PI * float(i) / 360.0   # inbound: between apoapsis and periapsis
		var cos_nu := cos(nu)
		var denominator := r1m * cos_nu - rp_t
		if absf(denominator) < 1.0e-9:
			continue
		var e := (rp_t - r1m) / denominator
		if e < 0.0 or e >= 0.999:
			continue
		var p := rp_t * (1.0 + e)
		var v_new := radial * (sqrt(mu / p) * e * sin(nu)) + tangential * (sqrt(mu / p) * (1.0 + e * cos_nu))
		var dv := (v_new - ship_velocity).length()
		if dv < best_dv:
			best_dv = dv
			best_velocity = v_new
	if best_dv >= 1.0e29:
		return {"error": "No course to that orbit was found from here."}
	var segment := state_segment(mu, r1, best_velocity, t_burn)
	if segment.is_empty():
		return {"error": "No course to that orbit was found from here."}
	var anomaly := wrapf(float(segment["mean_anomaly_deg"]), -180.0, 180.0)
	var tof_days := -anomaly / float(segment["mean_motion_deg_per_day"])
	if tof_days <= 0.0:
		return {"error": "No course to that orbit was found from here."}
	var energy := -mu / (2.0 * float(segment["semi_major_axis_km"]))
	var dv_capture := TransferPlanner.capture_dv(mu, energy, rp_t, ra_t)
	var plan := {
		"origin_id": frame,
		"target_id": frame,
		"target_name": GameState.bodies[frame]["name"],
		"frame": frame,
		"t_dep": t_burn,
		"t_arr": t_burn + tof_days,
		"flight_days": tof_days,
		"dv_departure": best_dv,
		"dv_arrival": dv_capture,
		"transfer_segment": segment,
		"committed": false,
		"departure_done": false,
		"arrival_seen": false,
		"target_orbit": orbit,
		"rp_t": rp_t,
		"ra_t": ra_t,
		"offset_deg": float(orbit["offset_deg"]),
		"aimable": false,
		"dv_circularize": 0.0,
		"arrival_energy": energy,
		"capture_phase_deg": float(segment["argument_of_periapsis_deg"]),
		"gm_target": mu,
		"dv_capture": dv_capture,
		"midflight": true,
	}
	AeroBraking.setup_plan(plan)
	return plan


static func _evaluate(mu: float, r1: Vector2, ship_velocity: Vector2, target_fn: Callable, _target_id: String,
		target_gm: float, t_burn: float, tof_days: float, rp_t: float, ra_t: float, frame_radius: float) -> Dictionary:
	var t_arr := t_burn + tof_days
	var r2: Vector2 = target_fn.call(t_arr)
	var solution := lambert(mu, r1, r2, tof_days * 86400.0)
	if solution.is_empty():
		return {}
	var v1: Vector2 = solution["v1"]
	var v2: Vector2 = solution["v2"]
	var segment := state_segment(mu, r1, v1, t_burn)
	if segment.is_empty():
		return {}
	var periapsis := float(segment["semi_major_axis_km"]) * (1.0 - float(segment["eccentricity"]))
	if periapsis < frame_radius * 1.05:
		return {}
	var dv_burn := (v1 - ship_velocity).length()
	var v_inf := (v2 - TransferPlanner.velocity_kms(target_fn, t_arr)).length()
	var energy := 0.5 * v_inf * v_inf
	var dv_capture := TransferPlanner.capture_dv(target_gm, energy, rp_t, ra_t)
	return {"cost": dv_burn + dv_capture, "tof_days": tof_days, "dv_burn": dv_burn, "dv_capture": dv_capture,
			"segment": segment, "energy": energy}
