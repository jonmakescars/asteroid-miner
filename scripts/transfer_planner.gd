class_name TransferPlanner
extends RefCounted
## Hohmann-style transfers between bodies on rails (2D), for the mission planner.
## Positions are Vector2 in km relative to the central body, times are Julian Dates, GM is in
## km^3/s^2 and velocities are in km/s.
##
## A transfer is a half ellipse between the departure point (radius r1) and the target's position at
## arrival (radius r2), on opposite sides of the central body. Outward transfers (r2 > r1) start at
## periapsis, inward transfers start at apoapsis. Departure and arrival are tied together because the
## target moves while the ship flies, so the arrival position is found by iteration.
##
## origin_fn and target_fn are Callables taking a Julian Date and returning the position (Vector2).

const SECONDS_PER_DAY := 86400.0


## Mean motion in degrees per day of a circular or elliptical orbit with semi-major axis a_km.
static func mean_motion_deg_per_day(gm: float, a_km: float) -> float:
	return rad_to_deg(sqrt(gm / (a_km * a_km * a_km)) * SECONDS_PER_DAY)


## Orbit segment (same format as the body data) for a circular orbit that starts at angle phase_deg.
static func circular_segment(radius_km: float, gm: float, epoch_jd: float, phase_deg: float) -> Dictionary:
	return {
		"epoch_jd": epoch_jd,
		"semi_major_axis_km": radius_km,
		"eccentricity": 0.0,
		"longitude_of_ascending_node_deg": 0.0,
		"argument_of_periapsis_deg": phase_deg,
		"mean_anomaly_deg": 0.0,
		"mean_motion_deg_per_day": mean_motion_deg_per_day(gm, radius_km),
	}


## Orbit segment of the transfer ellipse at the departure time (the ship starts at periapsis for an
## outward transfer and at apoapsis for an inward one).
static func transfer_segment(transfer: Dictionary, gm: float) -> Dictionary:
	var a := float(transfer["a"])
	return {
		"epoch_jd": float(transfer["t_dep"]),
		"semi_major_axis_km": a,
		"eccentricity": float(transfer["e"]),
		"longitude_of_ascending_node_deg": 0.0,
		"argument_of_periapsis_deg": rad_to_deg(float(transfer["peri_longitude"])),
		"mean_anomaly_deg": float(transfer["mean_anomaly_start_deg"]),
		"mean_motion_deg_per_day": mean_motion_deg_per_day(gm, a),
	}


## Velocity (km/s) of something following pos_fn, from a numerical derivative.
static func velocity_kms(pos_fn: Callable, jd: float) -> Vector2:
	var h := 0.01  # days
	var ahead: Vector2 = pos_fn.call(jd + h)
	var behind: Vector2 = pos_fn.call(jd - h)
	return (ahead - behind) / (2.0 * h * SECONDS_PER_DAY)


## Transfer for departing at jd t_dep. The result includes angle_error: how far (radians) the target
## is from the apoapsis direction when the ship arrives. It is zero in a launch window.
static func transfer_for_departure(gm: float, origin_fn: Callable, target_fn: Callable, t_dep: float) -> Dictionary:
	var origin: Vector2 = origin_fn.call(t_dep)
	var r1 := origin.length()
	var r2 := r1
	var a := r1
	var flight_days := 0.0
	var t_arr := t_dep
	var target_pos := Vector2.ZERO
	for _i in 12:
		a = 0.5 * (r1 + r2)
		flight_days = PI * sqrt(a * a * a / gm) / SECONDS_PER_DAY
		t_arr = t_dep + flight_days
		target_pos = target_fn.call(t_arr)
		var new_r2 := target_pos.length()
		var change := absf(new_r2 - r2)
		r2 = new_r2
		if change < 0.01:
			break
	a = 0.5 * (r1 + r2)
	var outward := r2 >= r1
	return {
		"gm": gm,
		"t_dep": t_dep,
		"t_arr": t_arr,
		"flight_days": flight_days,
		"r1": r1,
		"r2": r2,
		"a": a,
		"e": absf(r2 - r1) / (r1 + r2),
		"peri_longitude": origin.angle() if outward else origin.angle() + PI,
		"mean_anomaly_start_deg": 0.0 if outward else 180.0,
		"origin": origin,
		"target_pos": target_pos,
		"angle_error": wrapf(target_pos.angle() - (origin.angle() + PI), -PI, PI),
	}


## Transfer from the departure point at jd t_dep down to a circular orbit of radius capture_radius_km
## around the central body itself (for example from the Moon to Earth). There is no target to meet, so
## there is no launch window: the ship can leave at any time, arriving on the opposite side.
static func transfer_to_central(gm: float, origin_fn: Callable, t_dep: float, capture_radius_km: float) -> Dictionary:
	var origin: Vector2 = origin_fn.call(t_dep)
	var r1 := origin.length()
	var r2 := capture_radius_km
	var a := 0.5 * (r1 + r2)
	var flight_days := PI * sqrt(a * a * a / gm) / SECONDS_PER_DAY
	return {
		"gm": gm,
		"t_dep": t_dep,
		"t_arr": t_dep + flight_days,
		"flight_days": flight_days,
		"r1": r1,
		"r2": r2,
		"a": a,
		"e": absf(r2 - r1) / (r1 + r2),
		"peri_longitude": origin.angle() + PI,
		"mean_anomaly_start_deg": 180.0,
		"origin": origin,
		"target_pos": Vector2.from_angle(origin.angle() + PI) * r2,
		"angle_error": 0.0,
	}


## Searches forward from t_start for the first launch window: scans in steps of step_days for a
## sign change of angle_error, then narrows it down by bisection. Returns {} if none is found.
static func find_window(gm: float, origin_fn: Callable, target_fn: Callable,
		t_start: float, horizon_days: float, step_days: float) -> Dictionary:
	var prev_t := t_start
	var prev_error := float(transfer_for_departure(gm, origin_fn, target_fn, prev_t)["angle_error"])
	var t := t_start
	while t < t_start + horizon_days:
		t += step_days
		var step_error := float(transfer_for_departure(gm, origin_fn, target_fn, t)["angle_error"])
		# A sign change is a crossing, unless the error just wrapped around from +pi to -pi.
		if prev_error * step_error <= 0.0 and absf(prev_error - step_error) < PI:
			var low := prev_t
			var high := t
			var low_error := prev_error
			for _k in 60:
				var mid := 0.5 * (low + high)
				var mid_error := float(transfer_for_departure(gm, origin_fn, target_fn, mid)["angle_error"])
				if low_error * mid_error <= 0.0:
					high = mid
				else:
					low = mid
					low_error = mid_error
			return transfer_for_departure(gm, origin_fn, target_fn, 0.5 * (low + high))
		prev_t = t
		prev_error = step_error
	return {}


## Burn from a circular parking orbit straight onto the transfer (both around the same body).
static func departure_dv_bound(transfer: Dictionary, gm: float) -> float:
	var r1 := float(transfer["r1"])
	var v_departure := sqrt(gm * (2.0 / r1 - 1.0 / float(transfer["a"])))
	return absf(v_departure - sqrt(gm / r1))


## Burn to leave the sphere of influence of the origin body (a planet or a moon) onto the transfer.
## origin_velocity is the body's own velocity around the central body; body_gm and parking_radius_km
## describe the ship's circular parking orbit around the origin body.
static func departure_dv_escape(transfer: Dictionary, origin_velocity: Vector2, body_gm: float, parking_radius_km: float) -> float:
	var r1 := float(transfer["r1"])
	var v_departure := sqrt(float(transfer["gm"]) * (2.0 / r1 - 1.0 / float(transfer["a"])))
	var direction := (transfer["origin"] as Vector2).normalized().rotated(PI / 2.0)
	var v_inf := (direction * v_departure - origin_velocity).length()
	var v_circular := sqrt(body_gm / parking_radius_km)
	return sqrt(v_inf * v_inf + 2.0 * v_circular * v_circular) - v_circular


## Burn from a parking orbit around a moon to a transfer around the Sun (the moon's planet is the
## origin of the transfer). Estimate in two steps: the excess speed needed relative to the planet, then
## the burn that gives the ship that speed from the moon's orbit, assuming the best direction. The
## phase of the moon in its orbit is not modelled.
static func departure_dv_from_moon(transfer: Dictionary, planet_velocity: Vector2, planet_gm: float,
		moon_orbit_radius_km: float, moon_gm: float, parking_radius_km: float) -> float:
	var r1 := float(transfer["r1"])
	var v_departure := sqrt(float(transfer["gm"]) * (2.0 / r1 - 1.0 / float(transfer["a"])))
	var direction := (transfer["origin"] as Vector2).normalized().rotated(PI / 2.0)
	var v_inf_planet := (direction * v_departure - planet_velocity).length()
	var v_required := sqrt(v_inf_planet * v_inf_planet + 2.0 * planet_gm / moon_orbit_radius_km)
	var v_moon := sqrt(planet_gm / moon_orbit_radius_km)
	var v_inf_moon := absf(v_required - v_moon)
	var v_circular := sqrt(moon_gm / parking_radius_km)
	return sqrt(v_inf_moon * v_inf_moon + 2.0 * v_circular * v_circular) - v_circular


## Capture burn into a circular orbit around the target. Returns {"v_inf_kms", "dv_kms"}.
static func arrival_dv(transfer: Dictionary, target_fn: Callable, target_gm: float, capture_radius_km: float) -> Dictionary:
	var r2 := float(transfer["r2"])
	var v_arrival := sqrt(float(transfer["gm"]) * (2.0 / r2 - 1.0 / float(transfer["a"])))
	var arrival_direction := Vector2.from_angle((transfer["origin"] as Vector2).angle() + PI)
	var ship_velocity := arrival_direction.rotated(PI / 2.0) * v_arrival
	var target_velocity := velocity_kms(target_fn, float(transfer["t_arr"]))
	var v_inf := (target_velocity - ship_velocity).length()
	var v_circular := sqrt(target_gm / capture_radius_km)
	return {
		"v_inf_kms": v_inf,
		"dv_kms": sqrt(v_inf * v_inf + 2.0 * v_circular * v_circular) - v_circular,
	}


## Burn at the end of a transfer to the central body: into a circular orbit at the arrival radius.
static func arrival_dv_central(transfer: Dictionary) -> float:
	var r2 := float(transfer["r2"])
	var gm := float(transfer["gm"])
	return absf(sqrt(gm * (2.0 / r2 - 1.0 / float(transfer["a"]))) - sqrt(gm / r2))
