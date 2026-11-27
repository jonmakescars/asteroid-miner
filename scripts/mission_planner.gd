class_name MissionPlanner
extends RefCounted
## Plans a mission from the body the ship is orbiting to a destination, using the transfers in
## TransferPlanner (patched conics: Hohmann-style legs between bodies, with the burns estimated
## at each sphere of influence). Everything is 2D, so inclinations are ignored.

const SYNODIC_SEARCH_DAYS := 2000.0   # search period for windows between planets
const MAX_ORBIT_SEARCH_PERIODS := 40.0   # never search longer than this many orbits of the ship
const ORBIT_SEARCH_PERIODS := 1.5     # for a ship in orbit around the origin: how many orbits to search
const MOON_WINDOW_STEPS := 48         # departure times tried over one orbit of a moon when it leaves for a planet (B-035)
const MOON_ESCAPE_CLEARANCE_KM := 300.0   # an escape orbit from a moon has to pass the planet at least this far above its surface
const NEARLY_CIRCULAR := 0.05         # if periapsis and apoapsis differ by less than this share of the apoapsis, the axis is ignored
const AXIS_TOLERANCE_DEG := 10.0      # a departure from an elliptical orbit may be this far off the periapsis direction
const VIA_PERIAPSIS_SHARE := 0.9      # on the way to a moon of another planet: the periapsis of the orbit round the planet, as a share of the moon's distance
const VIA_APSIS_MATCH := 0.02         # the apoapsis counts as "at the orbit of the moon" within this share of the moon's distance


## The destinations offered at a body: the bodies in its own sphere of influence (its moons, and
## if it is a moon, its planet and the planet's other moons), plus the other planets and dwarf
## planets that orbit the Sun.
static func destinations(origin_id: String) -> Array:
	var bodies := GameState.bodies
	var children := GameState.children
	var result: Array = [origin_id]   # a new orbit around the body the ship is at
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
	# The moons of the other planets (on the way to them the ship aerobrakes at the planet, see _plan_via_planet).
	for planet in children["sun"]:
		if str(planet) == origin_id or str(planet) == str(origin_parent):
			continue
		for id in children[planet]:
			if id != origin_id and not result.has(id):
				result.append(id)
	return result


## The default target orbit of a body: circular, at the body's default altitude (as altitudes above the surface).
static func default_target_orbit(target_id: String) -> Dictionary:
	var altitude := float(GameState.bodies[target_id]["default_orbit_altitude_km"])
	return {"rp_alt_km": altitude, "ra_alt_km": altitude + OrbitControl.EPS, "offset_deg": 0.0,
			"dir": GameState.natural_orbit_dir(target_id)}


## Plans the next departure from the orbit orbit_segment around origin_id to target_id, not before t_start,
## into the target orbit {"rp_alt_km", "ra_alt_km", "offset_deg"} (altitudes above the surface; the default
## orbit of the body if empty). Returns the plan, or {"error": text} if no plan is possible.
static func make_plan(origin_id: String, orbit_segment: Dictionary, target_id: String, t_start: float,
		target_orbit: Dictionary = {}, fixed_departure := -1.0, quick := false) -> Dictionary:
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
	var origin_dir := Kepler.direction(orbit_segment)   # (1 the ship runs counter-clockwise round the origin, -1 clockwise)
	var orbit := default_target_orbit(target_id)
	if target_id == origin_id:   # changing the orbit around the body the ship is at: start from the current orbit
		orbit = {"rp_alt_km": origin_orbit_radius - float(target["radius_km"]),
				"ra_alt_km": origin_apoapsis - float(target["radius_km"]), "offset_deg": 0.0, "dir": origin_dir}
	orbit.merge(target_orbit, true)
	var target_dir := -1 if int(orbit.get("dir", 1)) < 0 else 1
	orbit["dir"] = target_dir
	var pair := OrbitControl.normalise(float(orbit["rp_alt_km"]), float(orbit["ra_alt_km"]), "rp")
	orbit["rp_alt_km"] = pair.x
	orbit["ra_alt_km"] = pair.y
	var rp_t := float(target["radius_km"]) + pair.x
	var ra_t := float(target["radius_km"]) + pair.y
	var capture_radius := maxf(rp_t, 1.0)   # the arrival radius of a transfer to the central body
	var arrival_energy := 0.0
	if target_id == origin_id:
		return _plan_orbit_change(origin_id, orbit_segment, t_start, orbit, rp_t, ra_t)
	var target_fn := func(t: float) -> Vector2: return GameState.body_rel(target_id, t)

	var frame := ""
	var transfer: Dictionary = {}
	var dv_departure := 0.0
	var dv_arrival := 0.0
	var capture_phase_deg := 0.0
	var moon_escape: Dictionary = {}   # the escape orbit from a moon to a planet (TransferPlanner.moon_escape), empty otherwise
	var aimable := true   # arriving from outside the sphere of influence: the periapsis direction can be aimed

	if target_parent == origin_id:
		# Down the gravity well's other side: to a moon of the body we orbit. The ship can leave from any
		# point of its orbit, so the search runs over its orbit period.
		frame = origin_id
		var period_days := 360.0 / absf(float(orbit_segment["mean_motion_deg_per_day"]))
		var origin_fn := func(t: float) -> Vector2: return Kepler.position_at(orbit_segment, t)
		# The ship meets the moon's position again only after a synodic period, which can be several ship
		# orbits when the ship's orbit period is close to the moon's: search at least a bit more than that.
		var horizon := period_days * ORBIT_SEARCH_PERIODS
		var target_period := _period_days(target_id)
		var rate_difference := absf(1.0 / period_days - 1.0 / target_period)
		var synodic_days := MAX_ORBIT_SEARCH_PERIODS * period_days if rate_difference < 1.0e-9 else 1.0 / rate_difference
		horizon = minf(maxf(horizon, 1.2 * synodic_days), MAX_ORBIT_SEARCH_PERIODS * period_days)
		if origin_dir < 0:
			# A ship in a clockwise orbit leaves clockwise (the same burn as from a counter-clockwise orbit): the transfer is
			# planned in the mirror, where the ship runs counter-clockwise and the moon clockwise, and mirrored back. The
			# launch window is a different one, and the ship meets the moon head-on (the capture there costs more).
			var mirrored_origin := func(t: float) -> Vector2:
				var p: Vector2 = origin_fn.call(t)
				return Vector2(p.x, -p.y)
			var mirrored_target := func(t: float) -> Vector2:
				var p: Vector2 = target_fn.call(t)
				return Vector2(p.x, -p.y)
			transfer = TransferPlanner.mirror_transfer(TransferPlanner.find_window(origin_gm, mirrored_origin, mirrored_target,
					t_start, horizon, period_days / 180.0))
		else:
			transfer = TransferPlanner.find_window(origin_gm, origin_fn, target_fn, t_start, horizon, period_days / 180.0)
		if transfer.is_empty():
			return {"error": "No launch window found."}
		dv_departure = TransferPlanner.departure_dv_bound(transfer, origin_gm)
		var v_inf := float(TransferPlanner.arrival_dv(transfer, target_fn, target_gm, capture_radius)["v_inf_kms"])
		arrival_energy = 0.5 * v_inf * v_inf

	elif origin_parent == target_id:
		# From a moon to its own planet: no window, the ship can leave at once.
		frame = target_id
		var origin_fn := func(t: float) -> Vector2: return GameState.body_rel(origin_id, t)
		transfer = TransferPlanner.transfer_to_central(target_gm, origin_fn, t_start, capture_radius, target_dir)
		var origin_velocity := TransferPlanner.velocity_kms(origin_fn, t_start)
		dv_departure = TransferPlanner.departure_dv_escape(transfer, origin_velocity, origin_gm, origin_orbit_radius)
		if not origin_circular and origin_apoapsis - origin_orbit_radius >= NEARLY_CIRCULAR * origin_apoapsis:
			var needed_axis := TransferPlanner.escape_axis_deg(transfer, origin_velocity, origin_gm, origin_orbit_radius, origin_dir)
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
		transfer = _transfer(frame_gm, origin_fn, target_fn, t_start, horizon, step, fixed_departure)
		if transfer.is_empty():
			return {"error": "No launch window found."}
		var origin_velocity := TransferPlanner.velocity_kms(origin_fn, float(transfer["t_dep"]))
		dv_departure = TransferPlanner.departure_dv_escape(transfer, origin_velocity, origin_gm, origin_orbit_radius)
		if not origin_circular and origin_apoapsis - origin_orbit_radius >= NEARLY_CIRCULAR * origin_apoapsis:
			var needed_axis := TransferPlanner.escape_axis_deg(transfer, origin_velocity, origin_gm, origin_orbit_radius, origin_dir)
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
		transfer = _transfer(sun_gm, planet_fn, target_fn, t_start, SYNODIC_SEARCH_DAYS, 1.0, fixed_departure)
		if transfer.is_empty():
			return {"error": "No launch window found."}
		var t_dep := float(transfer["t_dep"])
		var planet_gm := float(bodies[planet_id]["gm_km3_s2"])
		var moon_fn := func(t: float) -> Vector2: return GameState.body_rel(origin_id, t)
		var planet_velocity := TransferPlanner.velocity_kms(planet_fn, t_dep)
		var moon_orbit_radius := GameState.body_rel(origin_id, t_dep).length()
		# The old estimate (the best direction, whatever the phase of the moon) is the fallback.
		dv_departure = TransferPlanner.departure_dv_from_moon(transfer, planet_velocity, planet_gm, moon_orbit_radius, origin_gm, origin_orbit_radius)
		# Patched conics (B-008, B-035): the ship has to leave on an escape orbit of the planet that passes through the moon's
		# place, so the burn depends on where the moon is. The moon is in the right place for one stretch of every orbit of
		# the moon: the departure is searched over one orbit of the moon around the best time of the transfer.
		var moon_period := _period_days(origin_id)
		var first := t_dep
		var last := t_dep
		if fixed_departure < 0.0:
			first = maxf(t_start, t_dep - 0.5 * moon_period)
			last = first + moon_period
		var best_escape := {}
		var best_transfer: Dictionary = {}
		var candidates := 1 if fixed_departure >= 0.0 else MOON_WINDOW_STEPS + 1
		for k in candidates:
			var t_try := first + (last - first) * float(k) / float(MOON_WINDOW_STEPS)
			var try_transfer := transfer
			if fixed_departure < 0.0:
				try_transfer = _transfer(sun_gm, planet_fn, target_fn, t_start, SYNODIC_SEARCH_DAYS, 1.0, t_try)
				if try_transfer.is_empty():
					continue
			var escape := TransferPlanner.moon_escape(TransferPlanner.departure_velocity(try_transfer),
					TransferPlanner.velocity_kms(planet_fn, float(try_transfer["t_dep"])), planet_gm,
					moon_fn.call(float(try_transfer["t_dep"])), TransferPlanner.velocity_kms(moon_fn, float(try_transfer["t_dep"])),
					origin_gm, origin_orbit_radius, float(bodies[planet_id]["radius_km"]) + MOON_ESCAPE_CLEARANCE_KM)
			if not escape.is_empty() and (best_escape.is_empty() or float(escape["dv_kms"]) < float(best_escape["dv_kms"])):
				best_escape = escape
				best_transfer = try_transfer
		if not best_escape.is_empty():
			transfer = best_transfer
			dv_departure = float(best_escape["dv_kms"])
			moon_escape = best_escape
		var v_inf := float(TransferPlanner.arrival_dv(transfer, target_fn, target_gm, capture_radius)["v_inf_kms"])
		arrival_energy = 0.5 * v_inf * v_inf

	elif target_parent != null and target_parent != "sun" and target_parent != origin_id and target_parent != origin_parent:
		# A moon of another planet: first to the planet (see _plan_via_planet).
		return _plan_via_planet(origin_id, orbit_segment, target_id, t_start, target_orbit, fixed_departure, quick)

	else:
		return {"error": "No route to %s from here yet." % target["name"]}

	# A transfer that cannot be aimed (from a moon to its planet) is turned round where the ship is slowest: going down, at
	# the departure from the moon (the transfer itself runs clockwise, see transfer_to_central); going up, at the arrival,
	# at the apoapsis of the transfer. An aimed arrival passes the target on either side for the same cost.
	var reverse_capture := not aimable and target_dir < 0 and int(transfer.get("dir", 1)) > 0
	dv_arrival = TransferPlanner.capture_dv(target_gm, arrival_energy, rp_t, ra_t, reverse_capture)
	if aimable and arrival_energy > 0.0:
		# The capture point is where the ship really arrives (passing on the side that gives a counter-clockwise
		# orbit), not a fixed direction; no mirroring of the approach is needed.
		capture_phase_deg = GameState.natural_capture_axis_deg(TransferPlanner.transfer_segment(transfer, float(transfer["gm"])),
				target_id, float(transfer["t_arr"]), rp_t, target_gm, arrival_energy, target_dir)
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
		"orbit_dir": target_dir,
		"origin_dir": origin_dir,
		"reverse_capture": reverse_capture,
	}
	if not moon_escape.is_empty():
		plan["moon_escape"] = moon_escape
	if quick:
		plan["dv_arrival"] = float(plan["dv_arrival"]) + AeroBraking.axis_turn_dv(plan)   # (what aiming cannot turn)
		plan["aero"] ={"available": false, "enabled": false, "outcome": "ok", "message": ""}
		plan["capture_legs"] = []   # (only the departure and the cost matter for a quick check of a different departure time)
		plan["outcome"] = "ok"
		return plan
	AeroBraking.setup_plan(plan)   # adds the aerobraking data and the capture legs
	return plan


## A moon of another planet (for example Earth to Phobos), stage 1 of 2 (Alpha v0.2.15, orbit controls changed in 0.2.16): the plan
## is the arrival at the planet, with aerobraking if that is cheaper, into an orbit whose apoapsis is at the orbit of the moon and
## whose periapsis is a bit lower (VIA_PERIAPSIS_SHARE of the moon's distance; the total cost of the way to the moon is the same
## for any periapsis). That Mars-side orbit is worked out here and cannot be edited. The target orbit of the player (the orbit
## control, GameState.target_orbits[moon]) is the orbit around the MOON (plan["via_moon_orbit"]); it is used for the estimate of
## the capture at the moon (via_moon_dv). Stage 2, the transfer to the moon from the planet orbit, is planned when the ship is
## there (the usual planet-to-moon plan).
static func _plan_via_planet(origin_id: String, orbit_segment: Dictionary, moon_id: String, t_start: float,
		target_orbit: Dictionary, fixed_departure: float, quick: bool) -> Dictionary:
	var bodies := GameState.bodies
	var moon: Dictionary = bodies[moon_id]
	var host_id := str(moon["parent"])
	var host: Dictionary = bodies[host_id]
	var host_radius := float(host["radius_km"])
	var moon_distance := GameState.body_rel(moon_id, t_start).length()
	var host_orbit := {"rp_alt_km": VIA_PERIAPSIS_SHARE * moon_distance - host_radius, "ra_alt_km": moon_distance - host_radius,
			"offset_deg": 0.0, "dir": GameState.natural_orbit_dir(host_id)}
	var moon_orbit := default_target_orbit(moon_id)
	moon_orbit.merge(target_orbit, true)
	moon_orbit["dir"] = -1 if int(moon_orbit.get("dir", 1)) < 0 else 1
	var pair := OrbitControl.normalise(float(moon_orbit["rp_alt_km"]), float(moon_orbit["ra_alt_km"]), "rp")
	moon_orbit["rp_alt_km"] = pair.x
	moon_orbit["ra_alt_km"] = pair.y
	# Stage 2 will need about the capture at the moon (+ 10 %): the aerobraking at the planet keeps that propellant back.
	var reserve_gm := float(host["gm_km3_s2"])
	var reserve_rp := VIA_PERIAPSIS_SHARE * moon_distance
	var reserve_v := absf(sqrt(reserve_gm / moon_distance) - sqrt(2.0 * reserve_gm * reserve_rp / (moon_distance * (reserve_rp + moon_distance))))
	var reserve := 1.1 * TransferPlanner.capture_dv(float(moon["gm_km3_s2"]), 0.5 * reserve_v * reserve_v,
			float(moon["radius_km"]) + float(moon_orbit["rp_alt_km"]), float(moon["radius_km"]) + float(moon_orbit["ra_alt_km"]))
	AeroBraking.reserve_kms = reserve
	var plan := make_plan(origin_id, orbit_segment, host_id, t_start, host_orbit, fixed_departure, quick)
	AeroBraking.reserve_kms = 0.0
	if plan.has("error"):
		return plan
	plan["via_reserve_kms"] = reserve
	plan["via_moon_id"] = moon_id
	plan["via_moon_name"] = moon["name"]
	plan["via_moon_orbit"] = moon_orbit
	plan["via_moon_dv"] = -1.0
	plan["via_wait_days"] = 0.0
	var gm := float(host["gm_km3_s2"])
	var rp := float(plan["rp_t"])
	var ra := float(plan["ra_t"])
	if absf(ra - moon_distance) <= VIA_APSIS_MATCH * moon_distance:
		# At the apoapsis the ship is at the orbit of the moon, a bit slower than the moon: what is left is the difference in
		# speed, which the capture by the moon has to take away (the moon's pull is small).
		var v_relative := absf(sqrt(gm / ra) - sqrt(2.0 * gm * rp / (ra * (rp + ra))))
		var moon_radius := float(moon["radius_km"])
		plan["via_moon_dv"] = TransferPlanner.capture_dv(float(moon["gm_km3_s2"]), 0.5 * v_relative * v_relative,
				moon_radius + float(moon_orbit["rp_alt_km"]), moon_radius + float(moon_orbit["ra_alt_km"]))
		# The ship meets the moon at the apoapsis only when the phases fit: at most one synodic period of the two orbits.
		var ship_period := TAU * sqrt(pow(0.5 * (rp + ra), 3.0) / gm) / 86400.0
		var rate_difference := absf(1.0 / ship_period - 1.0 / _period_days(moon_id))
		plan["via_wait_days"] = minf(1.0 / maxf(rate_difference, 1.0e-6), MAX_ORBIT_SEARCH_PERIODS * ship_period)
	update_follow_up(plan)
	return plan


## Stage 2 of a plan via a planet (Alpha v0.2.17): the usual planet-to-moon plan from the orbit the ship is in when stage 1 is
## over (the last orbit leg of the capture), into the orbit round the moon the player chose. It is stored in plan["follow_up"]
## and launched by GameState at the end of stage 1, so the whole route is one plan for the player: via_moon_dv is its real
## cost (replacing the estimate), via_wait_days the time the ship waits at the planet for the window, via_total_days the time
## from the departure to the end of the capture at the moon. It has to be made again whenever stage 1 changes (the aerobraking
## settings change the orbit and the time the ship is in it), see OrbitView._apply_aero.
static func update_follow_up(plan: Dictionary) -> void:
	if not plan.has("via_moon_id"):
		return
	plan.erase("follow_up")
	plan.erase("follow_up_error")
	var captures: Array = plan.get("capture_legs", [])
	if captures.is_empty() or str(plan.get("outcome", "ok")) != "ok" or str(captures[captures.size() - 1]["kind"]) != "orbit":
		return
	var parked: Dictionary = captures[captures.size() - 1]
	var t_free := float(parked["t_start"])
	var follow := make_plan(str(plan["target_id"]), parked["segment"], str(plan["via_moon_id"]), t_free, plan["via_moon_orbit"], -1.0, false)
	if follow.has("error"):
		plan["follow_up_error"] = str(follow["error"])
		return
	plan["follow_up"] = follow
	plan["via_moon_dv"] = float(follow["dv_departure"]) + float(follow["dv_arrival"])
	plan["via_wait_days"] = float(follow["t_dep"]) - t_free
	plan["via_total_days"] = GameState._plan_finish_time(follow) - float(plan["t_dep"])


## The transfer for a plan: the next launch window after t_start, or, with fixed_departure (a Julian Date), a
## transfer that leaves at that time and takes as long as the window's own transfer would (so the ship leaves a bit
## earlier or later than the best time, with a different burn).
static func _transfer(gm: float, origin_fn: Callable, target_fn: Callable, t_start: float, horizon: float, step: float,
		fixed_departure: float) -> Dictionary:
	if fixed_departure < 0.0:
		return TransferPlanner.find_window(gm, origin_fn, target_fn, t_start, horizon, step)
	var reference := TransferPlanner.transfer_for_departure(gm, origin_fn, target_fn, fixed_departure)
	return TransferPlanner.lambert_transfer(gm, origin_fn, target_fn, fixed_departure, float(reference["flight_days"]))


## A change of the ship's orbit around the body it is at (a new periapsis, apoapsis and axis): two burns at the
## apsides of the current orbit, as in AeroBraking.final_dv. The first burn waits for the apsis it needs.
## A change of direction (the target orbit runs the other way round) turns the ship round at the burn at the higher of the two
## apoapsides, where the ship is slowest: the speeds before and after add up there instead of being subtracted.
static func _plan_orbit_change(body_id: String, segment: Dictionary, t_start: float, orbit: Dictionary,
		rp_t: float, ra_t: float) -> Dictionary:
	var body: Dictionary = GameState.bodies[body_id]
	var old_dir := Kepler.direction(segment)
	var new_dir := -1 if int(orbit.get("dir", old_dir)) < 0 else 1
	var flip := new_dir != old_dir
	var gm := float(body["gm_km3_s2"])
	var a := float(segment["semi_major_axis_km"])
	var e := float(segment["eccentricity"])
	var rp := a * (1.0 - e)
	var ra := a * (1.0 + e)
	var axis := float(segment["argument_of_periapsis_deg"])
	var circular := OrbitControl.is_circular(rp, ra)
	# B-046: the order of the two burns. The apoapsis is raised first (burn at the periapsis) when the target periapsis lies above
	# the current apoapsis, and also when the direction changes and the target apoapsis is higher than the current one: the ship
	# is then turned round in the second burn, at the higher apoapsis, where it is slowest. Otherwise the first burn is at the
	# current apoapsis (which is then the higher one, or the same).
	var raise_apoapsis_first := ra < rp_t or (flip and ra_t > ra + 1.0)
	var t_burn := t_start
	var middle_axis := axis
	var way := float(old_dir)   # (a clockwise orbit runs its angles backwards)
	var motion_abs := absf(float(segment["mean_motion_deg_per_day"]))
	if not circular:
		var target_anomaly := 0.0 if raise_apoapsis_first else 180.0
		var anomaly := float(segment["mean_anomaly_deg"]) + float(segment["mean_motion_deg_per_day"]) * (t_start - float(segment["epoch_jd"]))
		t_burn = t_start + fposmod(way * (target_anomaly - anomaly), 360.0) / motion_abs
	elif not OrbitControl.is_circular(rp_t, ra_t):
		# From a circular orbit to one with an axis: the new periapsis (and apoapsis) must lie on the target axis, so
		# the first burn happens where the new periapsis (higher apoapsis) or apoapsis (lower periapsis) will be.
		middle_axis = float(orbit["offset_deg"])   # (the axis is universal, not counted from the old orbit)
		var burn_angle := middle_axis if raise_apoapsis_first else middle_axis + 180.0
		var angle_now := rad_to_deg(Kepler.position_at(segment, t_start).angle())
		t_burn = t_start + fposmod(way * (burn_angle - angle_now), 360.0) / motion_abs
	else:
		# Circular to circular: there is no axis, so the burn happens where the ship is, and the new ellipse touches
		# the old orbit there (periapsis at the ship for a higher apoapsis, apoapsis at the ship for a lower periapsis).
		var ship_angle := rad_to_deg(Kepler.position_at(segment, t_burn).angle())
		axis = ship_angle if raise_apoapsis_first else ship_angle - 180.0
		middle_axis = axis
	var middle_rp := rp if raise_apoapsis_first else rp_t
	var middle_ra := ra_t if raise_apoapsis_first else ra
	# The first burn happens at the periapsis when the apoapsis is raised first (no turn round: the middle ellipse still runs the old way)
	# and at the apoapsis otherwise (the ship is turned round there, so the middle ellipse runs the new way).
	var middle_dir := old_dir if raise_apoapsis_first else new_dir
	var middle := AeroBraking._ellipse(gm, middle_rp, middle_ra, t_burn, middle_axis, 0.0 if raise_apoapsis_first else 180.0, middle_dir)
	var half_days := TAU * sqrt(pow(0.5 * (middle_rp + middle_ra), 3.0) / gm) / 86400.0 * 0.5
	var dv_first: float
	var dv_second: float
	if raise_apoapsis_first:
		dv_first = absf(AeroBraking._speed_at_periapsis(gm, rp, ra_t) - AeroBraking._speed_at_periapsis(gm, rp, ra))
		dv_second = absf(AeroBraking._speed_at_apoapsis(gm, rp_t, ra_t) - AeroBraking._speed_at_apoapsis(gm, rp, ra_t))
		if flip:
			dv_second = AeroBraking._speed_at_apoapsis(gm, rp_t, ra_t) + AeroBraking._speed_at_apoapsis(gm, rp, ra_t)
	else:
		dv_first = absf(AeroBraking._speed_at_apoapsis(gm, rp_t, ra) - AeroBraking._speed_at_apoapsis(gm, rp, ra))
		dv_second = absf(AeroBraking._speed_at_periapsis(gm, rp_t, ra_t) - AeroBraking._speed_at_periapsis(gm, rp_t, ra))
		if flip:
			dv_first = AeroBraking._speed_at_apoapsis(gm, rp_t, ra) + AeroBraking._speed_at_apoapsis(gm, rp, ra)
	var t_departure := t_burn
	var t_arrival := t_burn + half_days
	if dv_first < 0.0001:
		# Only the second burn changes anything (for example from a circular orbit to one with a higher apoapsis): do
		# not wait for a first burn of zero. The second burn happens at the other apsis of the middle ellipse; take the
		# one the ship reaches first.
		t_arrival = t_burn - half_days if t_burn - half_days >= t_start else t_burn + half_days
		t_departure = maxf(t_arrival - 1.0 / 86400.0, t_start)
		middle = AeroBraking._ellipse(gm, middle_rp, middle_ra, t_arrival, middle_axis, 180.0 if raise_apoapsis_first else 0.0, middle_dir)
	var plan := {
		"origin_id": body_id,
		"target_id": body_id,
		"target_name": body["name"],
		"frame": body_id,
		"t_dep": t_departure,
		"t_arr": t_arrival,
		"flight_days": t_arrival - t_departure,
		"dv_departure": dv_first,
		"dv_arrival": dv_second,
		"transfer_segment": middle,
		"committed": false,
		"departure_done": false,
		"arrival_seen": false,
		"target_orbit": orbit,
		"rp_t": rp_t,
		"ra_t": ra_t,
		"offset_deg": float(orbit["offset_deg"]),
		"aimable": false,
		"dv_circularize": 0.0,
		"arrival_energy": -gm / (2.0 * a),
		"capture_phase_deg": middle_axis,   # the axis of the orbit the two burns lead to (a turn to the target axis is left over)
		"gm_target": gm,
		"dv_capture": dv_second,
		"orbit_change": true,
		"orbit_dir": new_dir,
		"origin_dir": old_dir,
	}
	# The propulsive orbit change: its capture is the second burn at the other apsis.
	plan["aero"] = {"available": false, "enabled": false, "outcome": "ok", "message": ""}
	var final_anomaly := 180.0 if raise_apoapsis_first else 0.0
	plan["capture_anomaly"] = final_anomaly
	AeroBraking._use_propulsive_capture(plan)
	if circular:
		plan["dv_arrival"] = dv_second   # from a circular orbit the axis needs no extra burn
	if float(plan["dv_arrival"]) < 0.0001:
		# Only one apsis changes (for example raising the periapsis with the same apoapsis): the first burn already
		# gives the final orbit, there is no second burn to wait for. The mission ends with the first burn.
		plan["t_arr"] = t_departure + 1.0 / 86400.0
		plan["flight_days"] = 1.0 / 86400.0
		plan["t_end"] = plan["t_arr"]
		plan["dv_arrival"] = 0.0
		plan["capture_legs"][0]["t_start"] = plan["t_arr"]
		final_anomaly = 0.0 if raise_apoapsis_first else 180.0   # the ship is where the burn was
		plan["capture_anomaly"] = final_anomaly
	var legs: Array = plan["capture_legs"]
	legs[0]["t_start"] = plan["t_arr"]
	if AeroBraking.axis_turn_deg(plan) > 0.5:
		# The two burns lead to the target shape at the axis of the old orbit. The axis is then turned by the radial burn
		# at the point where the two orbits cross (as after an arrival): the ship coasts there from where the burns ended.
		legs[0]["segment"] = AeroBraking._ellipse(gm, rp_t, ra_t, float(plan["t_arr"]), AeroBraking._arrival_axis(plan), final_anomaly, new_dir)
		legs.resize(1)
		plan["t_end"] = AeroBraking._append_turn_leg(legs, plan, float(plan["t_arr"]), final_anomaly)
	else:
		legs[0]["segment"] = AeroBraking._ellipse(gm, rp_t, ra_t, float(plan["t_arr"]), AeroBraking._axis_deg(plan), final_anomaly, new_dir)
	# Lowering the apoapsis in an atmosphere can also be done with aerobraking: a burn at the current apoapsis lowers the
	# periapsis into the atmosphere, the passes lower the apoapsis, and burns at the end set the target orbit. The plan holds
	# both variants and AeroBraking.setup_plan picks the cheaper one (the player can switch).
	var atmosphere = body.get("atmosphere")
	if atmosphere is Dictionary and ra_t < ra * 0.995 and not raise_apoapsis_first:
		var radius := float(body["radius_km"])
		var h_mid := 0.5 * (float(atmosphere["min_periapsis_altitude_km"]) + AeroBraking.interface_altitude_km(atmosphere) - 1.0)
		if radius + h_mid < rp:
			var inputs := {"gm": gm, "radius": radius, "rp": rp, "ra": ra, "rp_t": rp_t, "ra_t": ra_t,
					"t_burn": t_burn, "axis": middle_axis, "old_dir": old_dir, "new_dir": new_dir}
			var keep := {}
			for key in AeroBraking.VARIANT_KEYS:
				keep[key] = plan[key].duplicate(true) if plan[key] is Dictionary else plan[key]
			plan["orbit_variants"] = {"propulsive": keep, "aero": AeroBraking.orbit_aero_variant(inputs, h_mid), "aero_inputs": inputs}
			AeroBraking.setup_plan(plan)
	return plan


static func _period_days(id: String) -> float:
	var segments: Array = GameState.bodies[id]["orbit_segments"]
	return 360.0 / float(segments[0]["mean_motion_deg_per_day"])
