class_name TransferPlanner
extends RefCounted
## Hohmann-style transfers between bodies on rails (2D), for the mission planner (build step 6).
## Only outward transfers are supported (the target is farther from the central body than the
## departure point). Positions are Vector2 in km relative to the central body, times are Julian
## Dates, GM is in km^3/s^2 and velocities are in km/s.
##
## A transfer is a half ellipse: periapsis at the departure point (at radius r1), apoapsis at the
## target's position at arrival (at radius r2). Departure and arrival are tied together because
## the target moves while the ship flies, so the arrival position is found by iteration.
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


## Orbit segment of the transfer ellipse, starting at periapsis at the departure time.
static func transfer_segment(transfer: Dictionary, gm: float) -> Dictionary:
	var a := float(transfer["a"])
	return {
		"epoch_jd": float(transfer["t_dep"]),
		"semi_major_axis_km": a,
		"eccentricity": float(transfer["e"]),
		"longitude_of_ascending_node_deg": 0.0,
		"argument_of_periapsis_deg": rad_to_deg(float(transfer["peri_longitude"])),
		"mean_anomaly_deg": 0.0,
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
	return {
		"gm": gm,
		"t_dep": t_dep,
		"t_arr": t_arr,
		"flight_days": flight_days,
		"r1": r1,
		"r2": r2,
		"a": a,
		"e": absf(r2 - r1) / (r1 + r2),
		"peri_longitude": origin.angle(),
		"origin": origin,
		"target_pos": target_pos,
		"angle_error": wrapf(target_pos.angle() - (origin.angle() + PI), -PI, PI),
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
	var v_periapsis := sqrt(gm * (2.0 / r1 - 1.0 / float(transfer["a"])))
	return v_periapsis - sqrt(gm / r1)


## Burn to leave a planet's sphere of influence onto a transfer around the Sun. origin_velocity is the
## planet's own velocity; body_gm and parking_radius_km describe the circular parking orbit.
static func departure_dv_escape(transfer: Dictionary, origin_velocity: Vector2, body_gm: float, parking_radius_km: float) -> float:
	var r1 := float(transfer["r1"])
	var v_periapsis := sqrt(float(transfer["gm"]) * (2.0 / r1 - 1.0 / float(transfer["a"])))
	var direction := (transfer["origin"] as Vector2).normalized().rotated(PI / 2.0)
	var v_inf := (direction * v_periapsis - origin_velocity).length()
	return sqrt(v_inf * v_inf + 2.0 * body_gm / parking_radius_km) - sqrt(body_gm / parking_radius_km)


## Capture burn into a circular orbit around the target. Returns {"v_inf_kms", "dv_kms"}.
static func arrival_dv(transfer: Dictionary, target_fn: Callable, target_gm: float, capture_radius_km: float) -> Dictionary:
	var r2 := float(transfer["r2"])
	var v_apoapsis := sqrt(float(transfer["gm"]) * (2.0 / r2 - 1.0 / float(transfer["a"])))
	var apoapsis_direction := Vector2.from_angle(float(transfer["peri_longitude"]) + PI)
	var ship_velocity := apoapsis_direction.rotated(PI / 2.0) * v_apoapsis
	var target_velocity := velocity_kms(target_fn, float(transfer["t_arr"]))
	var v_inf := (target_velocity - ship_velocity).length()
	var v_circular := sqrt(target_gm / capture_radius_km)
	return {
		"v_inf_kms": v_inf,
		"dv_kms": sqrt(v_inf * v_inf + 2.0 * v_circular * v_circular) - v_circular,
	}
