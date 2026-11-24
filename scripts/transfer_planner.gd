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
	# Going down (r2 < r1) the ship starts at the apoapsis of the transfer ellipse, going up (r2 > r1) at its periapsis
	# (B-039: the ellipse of a moon leaving for a higher orbit round its planet started at the wrong end).
	var going_up := r2 > r1
	return {
		"gm": gm,
		"t_dep": t_dep,
		"t_arr": t_dep + flight_days,
		"flight_days": flight_days,
		"r1": r1,
		"r2": r2,
		"a": a,
		"e": absf(r2 - r1) / (r1 + r2),
		"peri_longitude": origin.angle() if going_up else origin.angle() + PI,
		"mean_anomaly_start_deg": 0.0 if going_up else 180.0,
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


## The ship's velocity (km/s) at the start of a transfer, relative to the central body: tangential for the
## Hohmann-style transfers, the velocity the transfer stores ("v_dep") for the others.
static func departure_velocity(transfer: Dictionary) -> Vector2:
	if transfer.has("v_dep"):
		return transfer["v_dep"]
	var r1 := float(transfer["r1"])
	var v_departure := sqrt(float(transfer["gm"]) * (2.0 / r1 - 1.0 / float(transfer["a"])))
	return (transfer["origin"] as Vector2).normalized().rotated(PI / 2.0) * v_departure


## The same at the end of a transfer (at the target).
static func arrival_velocity(transfer: Dictionary) -> Vector2:
	if transfer.has("v_arr"):
		return transfer["v_arr"]
	var r2 := float(transfer["r2"])
	var v_arrival := sqrt(float(transfer["gm"]) * (2.0 / r2 - 1.0 / float(transfer["a"])))
	var arrival_direction := Vector2.from_angle((transfer["origin"] as Vector2).angle() + PI)
	return arrival_direction.rotated(PI / 2.0) * v_arrival


static func _stumpff_c(z: float) -> float:
	if absf(z) < 1.0e-8:
		return 0.5
	if z > 0.0:
		return (1.0 - cos(sqrt(z))) / z
	return (cosh(sqrt(-z)) - 1.0) / -z


static func _stumpff_s(z: float) -> float:
	if absf(z) < 1.0e-8:
		return 1.0 / 6.0
	if z > 0.0:
		var root := sqrt(z)
		return (root - sin(root)) / (root * root * root)
	var root_n := sqrt(-z)
	return (sinh(root_n) - root_n) / (root_n * root_n * root_n)


## A transfer that leaves the origin at t_dep and reaches the target flight_days later: the conic through the two
## positions (Lambert's problem, counter-clockwise, no full revolutions). It is not tangential at the departure or at
## the arrival, so the transfer stores the velocities ("v_dep", "v_arr"). Returns {} if there is no ellipse.
static func lambert_transfer(gm: float, origin_fn: Callable, target_fn: Callable, t_dep: float, flight_days: float) -> Dictionary:
	var r1v: Vector2 = origin_fn.call(t_dep)
	var t_arr := t_dep + flight_days
	var r2v: Vector2 = target_fn.call(t_arr)
	var r1 := r1v.length()
	var r2 := r2v.length()
	var dtheta := fposmod(r2v.angle() - r1v.angle(), TAU)
	if absf(dtheta - PI) < 1.0e-4 or dtheta < 1.0e-4:
		return {}   # (a half turn or no turn: the formulas have no single solution there; the window itself is the Hohmann transfer)
	var tof := flight_days * SECONDS_PER_DAY
	var a_term := sin(dtheta) * sqrt(r1 * r2 / (1.0 - cos(dtheta)))
	var low := -40.0
	var high := TAU * TAU - 1.0e-6
	var z := 0.0
	var y := 0.0
	for _i in 200:
		z = 0.5 * (low + high)
		var c := _stumpff_c(z)
		var s_value := _stumpff_s(z)
		y = r1 + r2 + a_term * (z * s_value - 1.0) / sqrt(c)
		var f_value := -1.0
		if y > 0.0:
			f_value = pow(y / c, 1.5) * s_value + a_term * sqrt(y) - sqrt(gm) * tof
		if f_value < 0.0:
			low = z
		else:
			high = z
	var c_final := _stumpff_c(z)
	y = r1 + r2 + a_term * (z * _stumpff_s(z) - 1.0) / sqrt(c_final)
	if y <= 0.0:
		return {}
	var f := 1.0 - y / r1
	var g := a_term * sqrt(y / gm)
	var g_dot := 1.0 - y / r2
	if absf(g) < 1.0e-12:
		return {}
	var v1 := (r2v - f * r1v) / g
	var v2 := (g_dot * r2v - r1v) / g
	if r1v.cross(v1) <= 0.0:
		return {}   # (clockwise: against the direction every orbit in the system runs)
	var speed2 := v1.length_squared()
	var energy_term := 2.0 / r1 - speed2 / gm
	if energy_term <= 1.0e-12:
		return {}   # not an ellipse
	var a := 1.0 / energy_term
	var e_vector := ((speed2 - gm / r1) * r1v - r1v.dot(v1) * v1) / gm
	var e := e_vector.length()
	var peri := e_vector.angle() if e > 1.0e-9 else r1v.angle()
	var nu := r1v.angle() - peri
	var ecc_anomaly := 2.0 * atan2(sqrt(maxf(1.0 - e, 0.0)) * sin(0.5 * nu), sqrt(1.0 + e) * cos(0.5 * nu))
	var mean_anomaly := ecc_anomaly - e * sin(ecc_anomaly)
	return {
		"gm": gm, "t_dep": t_dep, "t_arr": t_arr, "flight_days": flight_days, "r1": r1, "r2": r2, "a": a, "e": e,
		"peri_longitude": peri, "mean_anomaly_start_deg": rad_to_deg(mean_anomaly), "origin": r1v, "target_pos": r2v,
		"angle_error": 0.0, "v_dep": v1, "v_arr": v2,
	}


## Burn from a circular parking orbit straight onto the transfer (both around the same body).
static func departure_dv_bound(transfer: Dictionary, gm: float) -> float:
	var r1 := float(transfer["r1"])
	var v_departure := sqrt(gm * (2.0 / r1 - 1.0 / float(transfer["a"])))
	return absf(v_departure - sqrt(gm / r1))


## Burn to leave the sphere of influence of the origin body (a planet or a moon) onto the transfer.
## origin_velocity is the body's own velocity around the central body; body_gm and parking_radius_km
## describe the ship's circular parking orbit around the origin body.
static func departure_dv_escape(transfer: Dictionary, origin_velocity: Vector2, body_gm: float, parking_radius_km: float) -> float:
	var v_inf := (departure_velocity(transfer) - origin_velocity).length()
	var v_circular := sqrt(body_gm / parking_radius_km)
	return sqrt(v_inf * v_inf + 2.0 * v_circular * v_circular) - v_circular


## Direction (degrees) the periapsis of the ship's orbit around the origin body must have to leave onto the
## transfer: the escape hyperbola's outgoing asymptote is turned by the true anomaly acos(-1/e) from its
## periapsis (the orbits run counter-clockwise). Used with departure_dv_escape.
static func escape_axis_deg(transfer: Dictionary, origin_velocity: Vector2, body_gm: float, periapsis_radius_km: float) -> float:
	var v_inf_vector := departure_velocity(transfer) - origin_velocity
	var v_inf := v_inf_vector.length()
	var e := 1.0 + periapsis_radius_km * v_inf * v_inf / body_gm
	return rad_to_deg(v_inf_vector.angle() - acos(-1.0 / e))


## Burn from a parking orbit around a moon to a transfer around the Sun (the moon's planet is the
## origin of the transfer). Estimate in two steps: the excess speed needed relative to the planet, then
## the burn that gives the ship that speed from the moon's orbit, assuming the best direction. The
## phase of the moon in its orbit is not modelled.
static func departure_dv_from_moon(transfer: Dictionary, planet_velocity: Vector2, planet_gm: float,
		moon_orbit_radius_km: float, moon_gm: float, parking_radius_km: float) -> float:
	var v_inf_planet := (departure_velocity(transfer) - planet_velocity).length()
	var v_required := sqrt(v_inf_planet * v_inf_planet + 2.0 * planet_gm / moon_orbit_radius_km)
	var v_moon := sqrt(planet_gm / moon_orbit_radius_km)
	var v_inf_moon := absf(v_required - v_moon)
	var v_circular := sqrt(moon_gm / parking_radius_km)
	return sqrt(v_inf_moon * v_inf_moon + 2.0 * v_circular * v_circular) - v_circular


## The direction (radians, minus the wanted one) in which the outgoing asymptote of the escape orbit points, for a ship that
## leaves the position moon_pos (relative to the planet) with the speed v_required at the angle psi from the radius (counter-clockwise).
static func _asymptote_error(psi: float, moon_pos: Vector2, v_required: float, planet_gm: float, wanted: float) -> float:
	var radius_hat := moon_pos.normalized()
	var velocity := (radius_hat * cos(psi) + radius_hat.rotated(PI / 2.0) * sin(psi)) * v_required
	var ecc_vector := (moon_pos * (v_required * v_required - planet_gm / moon_pos.length()) - velocity * moon_pos.dot(velocity)) / planet_gm
	var ecc := ecc_vector.length()
	if ecc <= 1.0:
		return 0.0
	return wrapf(ecc_vector.angle() + acos(-1.0 / ecc) - wanted, -PI, PI)


## Leaving a moon for a transfer around the Sun, as patched conics (B-008, B-035): the transfer starts at the centre of the
## planet with the velocity v_dep (km/s, around the Sun), so relative to the planet the ship needs the excess speed
## v_dep - planet_velocity, and it has to be on an escape orbit of the planet that passes through the moon's place with that
## excess speed and direction. Of the escape orbits that do (counter-clockwise, outward bound), the one that needs the
## least burn from the circular parking orbit round the moon (the excess speed relative to the moon is the speed of the
## escape orbit at the moon minus the moon's own velocity) is used. moon_pos and moon_velocity are relative to the planet.
## Returns {"dv_kms", "v_inf_moon_kms", "axis_deg"}, empty if no such orbit exists with the moon where it is.
static func moon_escape(v_dep: Vector2, planet_velocity: Vector2, planet_gm: float, moon_pos: Vector2, moon_velocity: Vector2,
		moon_gm: float, parking_radius_km: float, min_periapsis_km := 0.0) -> Dictionary:
	var v_inf_vector := v_dep - planet_velocity
	var v_inf := v_inf_vector.length()
	var radius := moon_pos.length()
	if v_inf < 1.0e-6 or radius < 1.0:
		return {}
	var wanted := v_inf_vector.angle()
	var v_required := sqrt(v_inf * v_inf + 2.0 * planet_gm / radius)
	var steps := 90
	var psi_max := PI / 2.0
	var best := {}
	var previous_psi := 0.01
	var previous_error := _asymptote_error(previous_psi, moon_pos, v_required, planet_gm, wanted)
	for i in range(1, steps + 1):
		var psi := lerpf(0.01, psi_max, float(i) / float(steps))
		var error := _asymptote_error(psi, moon_pos, v_required, planet_gm, wanted)
		if previous_error * error <= 0.0 and absf(previous_error - error) < 1.0:   # a crossing (not the jump at +-180 degrees)
			var low := previous_psi
			var high := psi
			var low_error := previous_error
			for _k in 40:
				var mid := 0.5 * (low + high)
				var mid_error := _asymptote_error(mid, moon_pos, v_required, planet_gm, wanted)
				if low_error * mid_error <= 0.0:
					high = mid
				else:
					low = mid
					low_error = mid_error
			var root := 0.5 * (low + high)
			var radius_hat := moon_pos.normalized()
			var velocity := (radius_hat * cos(root) + radius_hat.rotated(PI / 2.0) * sin(root)) * v_required
			# The escape orbit must not run through the planet: its periapsis has to be above min_periapsis_km (B-035).
			var ang_mom := radius * v_required * sin(root)
			var ecc_planet := sqrt(1.0 + v_inf * v_inf * ang_mom * ang_mom / (planet_gm * planet_gm))
			if ang_mom * ang_mom / planet_gm / (1.0 + ecc_planet) < min_periapsis_km:
				previous_psi = psi
				previous_error = error
				continue
			var relative := velocity - moon_velocity
			var v_inf_moon := relative.length()
			var v_circular := sqrt(moon_gm / parking_radius_km)
			var dv := sqrt(v_inf_moon * v_inf_moon + 2.0 * v_circular * v_circular) - v_circular
			if best.is_empty() or dv < float(best["dv_kms"]):
				var ecc_moon := 1.0 + parking_radius_km * v_inf_moon * v_inf_moon / moon_gm
				best = {"dv_kms": dv, "v_inf_moon_kms": v_inf_moon, "v_inf_planet_kms": v_inf,
						"vx": velocity.x, "vy": velocity.y,   # the ship's velocity round the planet at the moon's place
						"axis_deg": rad_to_deg(relative.angle() - acos(-1.0 / ecc_moon))}
		previous_psi = psi
		previous_error = error
	return best


## Capture burn into a circular orbit around the target. Returns {"v_inf_kms", "dv_kms"}.
static func arrival_dv(transfer: Dictionary, target_fn: Callable, target_gm: float, capture_radius_km: float) -> Dictionary:
	var ship_velocity := arrival_velocity(transfer)
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


## Burn (km/s) that puts a ship arriving with the specific energy energy (km2/s2, relative to the body: half
## the hyperbolic excess speed squared, or negative for an arrival on a bound orbit) into the orbit with the
## periapsis radius rp and the apoapsis radius ra. The burn is made at the periapsis of the target orbit; the
## orientation of the orbit is not part of the cost. For a circular orbit this is the usual capture burn.
static func capture_dv(gm: float, energy: float, rp: float, ra: float) -> float:
	var arrival_speed := sqrt(maxf(2.0 * (energy + gm / rp), 0.0))
	var orbit_speed := sqrt(2.0 * gm * ra / (rp * (rp + ra)))
	return absf(arrival_speed - orbit_speed)
