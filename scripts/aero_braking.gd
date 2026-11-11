class_name AeroBraking
extends RefCounted
## Aerobraking: slowing a ship down in the upper atmosphere of a planet instead of with a burn.
##
## A pass is simulated numerically (RK4) through an exponential atmosphere, with drag from the ship's
## ballistic coefficient (mass / (drag coefficient x area)). Heating uses the Sutton-Graves relation
## (flux = k * sqrt(density / nose radius) * speed^3); the heat load is its integral over the pass.
## Several passes at the same periapsis altitude lower the apoapsis step by step. The small burns that
## would keep the periapsis altitude between passes are ignored in this first version.
##
## The aerobraking data of a plan lives in plan["aero"]; the mission planner calls setup_plan() once, and
## the orbit view calls apply() when the player changes the number of passes or the periapsis altitude.
## Units: km, km/s, km^3/s^2 for orbits; the pass simulation works in metres internally.

const SHIP_DENSITY_KG_M3 := 300.0        # average density, to get a ship's size from its mass
const DRAG_COEFFICIENT := 1.5
const SHIELD_KG_PER_M2_CM := 3.0         # shield mass per m2 of area and cm of thickness
const SHIELD_MJ_PER_M2_CM := 15.0        # heat load a shield can take per cm of thickness
const G_LIMIT := 10.0                    # peak deceleration limit for cargo-only ships (g)
const HEAT_MARGIN := 0.8                 # the planner uses at most this share of the shield's capacity
const MAX_PASSES := 64
const PASS_COUNTS := [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]   # tried in this order by the planner
const SEARCH_DT := 2.0                   # time step (s) for searching
const FINAL_DT := 1.0                    # time step (s) for the numbers that are shown
const INTERFACE_DENSITY := 1.0e-8        # the pass starts where the density is this small (kg/m3)
const G0 := 9.80665
const BAND_KM := 8.0                     # the periapsis slider covers this far above and below the setting

static var _acc := PackedFloat64Array([0.0, 0.0, 0.0])   # scratch: radial accel, tangential accel, drag accel


# ---------------------------------------------------------------- ship size and shield

## Frontal area (m2) of a ship of a given mass: a sphere of average density.
static func area_for_mass(mass_kg: float) -> float:
	var volume := mass_kg / SHIP_DENSITY_KG_M3
	var radius := pow(3.0 * volume / (4.0 * PI), 1.0 / 3.0)
	return PI * radius * radius


static func shield_mass_kg(thickness_cm: float, area_m2: float) -> float:
	return thickness_cm * SHIELD_KG_PER_M2_CM * area_m2


static func shield_capacity_mj_m2(thickness_cm: float) -> float:
	return thickness_cm * SHIELD_MJ_PER_M2_CM


## Altitude (km) where a pass starts.
static func interface_altitude_km(atmosphere: Dictionary) -> float:
	return float(atmosphere["scale_height_km"]) * log(float(atmosphere["surface_density_kg_m3"]) / INTERFACE_DENSITY)


# ---------------------------------------------------------------- one pass

## Accelerations for the state (r, radial speed, tangential speed), in m and m/s: fills _acc.
static func _accel(r: float, vr: float, vt: float, mu: float, radius: float, rho0: float, scale_h: float, beta: float) -> void:
	var v := sqrt(vr * vr + vt * vt)
	var rho := rho0 * exp(-(r - radius) / scale_h)
	var drag := rho * v * v / (2.0 * beta)
	_acc[0] = -mu / (r * r) + vt * vt / r - drag * vr / v
	_acc[1] = -vr * vt / r - drag * vt / v
	_acc[2] = drag


## One pass through the atmosphere. The orbit before the pass has the specific energy energy (km2/s2) and its
## periapsis at periapsis_altitude_km. Returns {"crash": true} if the ship hits the ground or cannot leave the
## atmosphere again (it slows down too much), otherwise
## {"energy", "heat_mj_m2", "peak_g", "peak_flux_mw_m2", "seconds"} with the energy after the pass.
static func simulate_pass(gm: float, radius_km: float, atmosphere: Dictionary, periapsis_altitude_km: float,
		energy: float, beta: float, nose_radius_m: float, dt: float) -> Dictionary:
	var mu := gm * 1.0e9
	var radius := radius_km * 1000.0
	var rho0 := float(atmosphere["surface_density_kg_m3"])
	var scale_h := float(atmosphere["scale_height_km"]) * 1000.0
	var r0 := radius + interface_altitude_km(atmosphere) * 1000.0
	var rp := radius + periapsis_altitude_km * 1000.0
	if rp >= r0:
		return {"energy": energy, "heat_mj_m2": 0.0, "peak_g": 0.0, "peak_flux_mw_m2": 0.0, "seconds": 0.0}
	var e_si := energy * 1.0e6
	var vp := sqrt(2.0 * (e_si + mu / rp))
	var ang_mom := rp * vp
	var v0 := sqrt(2.0 * (e_si + mu / r0))
	var vt := ang_mom / r0
	var vr := -sqrt(maxf(v0 * v0 - vt * vt, 0.0))
	var r := r0
	var heat := 0.0
	var peak_g := 0.0
	var peak_flux := 0.0
	var seconds := 0.0
	for _step in int(30000.0 / dt):
		_accel(r, vr, vt, mu, radius, rho0, scale_h, beta)
		var a1r := _acc[0]
		var a1t := _acc[1]
		peak_g = maxf(peak_g, _acc[2] / G0)
		var v := sqrt(vr * vr + vt * vt)
		var flux := 1.7415e-4 * sqrt(rho0 * exp(-(r - radius) / scale_h) / nose_radius_m) * v * v * v
		peak_flux = maxf(peak_flux, flux)
		heat += flux * dt
		var h2 := 0.5 * dt
		_accel(r + h2 * vr, vr + h2 * a1r, vt + h2 * a1t, mu, radius, rho0, scale_h, beta)
		var a2r := _acc[0]
		var a2t := _acc[1]
		var k2r := vr + h2 * a1r
		_accel(r + h2 * k2r, vr + h2 * a2r, vt + h2 * a2t, mu, radius, rho0, scale_h, beta)
		var a3r := _acc[0]
		var a3t := _acc[1]
		var k3r := vr + h2 * a2r
		_accel(r + dt * k3r, vr + dt * a3r, vt + dt * a3t, mu, radius, rho0, scale_h, beta)
		var a4r := _acc[0]
		var a4t := _acc[1]
		var k4r := vr + dt * a3r
		var new_r := r + dt / 6.0 * (vr + 2.0 * k2r + 2.0 * k3r + k4r)
		var new_vr := vr + dt / 6.0 * (a1r + 2.0 * a2r + 2.0 * a3r + a4r)
		var new_vt := vt + dt / 6.0 * (a1t + 2.0 * a2t + 2.0 * a3t + a4t)
		r = new_r
		vr = new_vr
		vt = new_vt
		seconds += dt
		if r < radius:
			return {"crash": true}
		if r >= r0 and vr > 0.0:
			break
	if r < r0:
		return {"crash": true}   # still in the atmosphere after the time limit: the ship cannot leave it
	var speed := sqrt(vr * vr + vt * vt)
	return {
		"energy": (0.5 * speed * speed - mu / r) / 1.0e6,
		"heat_mj_m2": heat / 1.0e6,
		"peak_g": peak_g,
		"peak_flux_mw_m2": peak_flux / 1.0e6,
		"seconds": seconds,
	}


## Apoapsis radius (km) of the orbit with the periapsis radius rp and the specific energy energy. A huge
## number means the ship still has escape energy; 0 means the orbit would be below the periapsis (too deep).
static func apoapsis_from_energy(gm: float, rp: float, energy: float) -> float:
	if energy >= 0.0:
		return 1.0e12
	var ra := 2.0 * (-gm / (2.0 * energy)) - rp
	return ra if ra >= rp else 0.0


# ---------------------------------------------------------------- several passes

## ctx: {gm, radius, atmosphere, ra_t (apoapsis radius of the target orbit, the goal of the passes), energy
## (before the first pass), beta, nose, shield_left_mj_m2, shield_capacity_mj_m2}.
## Runs n passes at the periapsis altitude h_km. Returns {"status", "heat", "peak_g", "peak_flux", "ras"
## (apoapsis after each pass, km), "seconds" (the time spent in the atmosphere), "ra"}. The status is "ok",
## "escape" (the ship is still too fast to be captured) or "too_slow" (the ship slows down so much that it
## cannot leave the atmosphere again, or crashes).
static func run_passes(ctx: Dictionary, h_km: float, n: int, dt: float) -> Dictionary:
	var gm := float(ctx["gm"])
	var rp := float(ctx["radius"]) + h_km
	var energy := float(ctx["energy"])
	var heat := 0.0
	var peak_g := 0.0
	var peak_flux := 0.0
	var seconds := 0.0
	var ras: Array = []
	var status := "ok"
	var ra := 1.0e12
	for _i in n:
		var pass_result := simulate_pass(gm, float(ctx["radius"]), ctx["atmosphere"], h_km, energy,
				float(ctx["beta"]), float(ctx["nose"]), dt)
		if pass_result.has("crash"):
			status = "too_slow"
			ra = 0.0
			break
		energy = float(pass_result["energy"])
		heat += float(pass_result["heat_mj_m2"])
		peak_g = maxf(peak_g, float(pass_result["peak_g"]))
		peak_flux = maxf(peak_flux, float(pass_result["peak_flux_mw_m2"]))
		seconds += float(pass_result["seconds"])
		ra = apoapsis_from_energy(gm, rp, energy)
		ras.append(ra)
		if ra <= 0.0:
			status = "too_slow"
			break
	if status == "ok" and ra >= 1.0e11:
		status = "escape"
	return {"status": status, "heat": heat, "peak_g": peak_g, "peak_flux": peak_flux, "ras": ras,
			"seconds": seconds, "ra": ra}


## How far the result is from the goal: positive = the apoapsis is still above the target (braking missing),
## negative = the ship has slowed down too much.
static func _excess(result: Dictionary, ra_t: float) -> float:
	match str(result["status"]):
		"escape":
			return 1.0e12
		"too_slow":
			return -1.0
		_:
			return float(result["ra"]) - ra_t


## The periapsis altitude (km) at which n passes end with the apoapsis at (just above) the target apoapsis, or
## -1 if even the lowest allowed periapsis does not brake enough.
static func find_altitude(ctx: Dictionary, n: int, dt: float) -> float:
	var atmosphere: Dictionary = ctx["atmosphere"]
	var low := float(atmosphere["min_periapsis_altitude_km"])
	var high := interface_altitude_km(atmosphere) - 1.0
	var ra_t := float(ctx["ra_t"])
	if _excess(run_passes(ctx, low, n, dt), ra_t) > 0.0:
		return -1.0
	for _i in 12:
		var middle := 0.5 * (low + high)
		if _excess(run_passes(ctx, middle, n, dt), ra_t) > 0.0:
			high = middle
		else:
			low = middle
	return high


## The planner's suggestion: the fewest passes that stay within the shield's heat budget and the g limit.
## Heat grows with the number of passes while the g load falls, so the search stops at the first count that
## works, or gives up when the heat budget is already exceeded. Returns {"n", "h_km"} or {} if there is none.
static func suggest(ctx: Dictionary) -> Dictionary:
	var allowed := HEAT_MARGIN * float(ctx["shield_left_mj_m2"])
	for n_value in PASS_COUNTS:
		var n: int = n_value
		var h := find_altitude(ctx, n, SEARCH_DT)
		if h < 0.0:
			continue
		var result := run_passes(ctx, h, n, SEARCH_DT)
		if str(result["status"]) != "ok":
			continue
		if float(result["heat"]) > allowed:
			return {}
		if float(result["peak_g"]) <= G_LIMIT:
			return {"n": n, "h_km": h}
	return {}


# ---------------------------------------------------------------- burns after the passes

## Speed at the apoapsis (radius r2) of the ellipse with the periapsis radius r1 and the apoapsis radius r2.
static func _speed_at_apoapsis(gm: float, r1: float, r2: float) -> float:
	return sqrt(2.0 * gm * r1 / (r2 * (r1 + r2)))


## Speed at the periapsis (radius r1) of the same ellipse.
static func _speed_at_periapsis(gm: float, r1: float, r2: float) -> float:
	return sqrt(2.0 * gm * r2 / (r1 * (r1 + r2)))


## Delta-v (km/s) from the orbit after the passes (periapsis rp in the atmosphere, apoapsis ra) to the target
## orbit (rp_t, ra_t). If ra reaches rp_t: raise the periapsis to rp_t at the apoapsis, then move the apoapsis
## to ra_t at the new periapsis. Otherwise first raise the apoapsis to ra_t at the periapsis, then the
## periapsis at the new apoapsis.
static func final_dv(gm: float, rp: float, ra: float, rp_t: float, ra_t: float) -> float:
	if ra >= rp_t:
		var raise_periapsis := absf(_speed_at_apoapsis(gm, rp_t, ra) - _speed_at_apoapsis(gm, rp, ra))
		var move_apoapsis := absf(_speed_at_periapsis(gm, rp_t, ra_t) - _speed_at_periapsis(gm, rp_t, ra))
		return raise_periapsis + move_apoapsis
	var raise_apoapsis := absf(_speed_at_periapsis(gm, rp, ra_t) - _speed_at_periapsis(gm, rp, ra))
	var raise_periapsis_later := absf(_speed_at_apoapsis(gm, rp_t, ra_t) - _speed_at_apoapsis(gm, rp, ra_t))
	return raise_apoapsis + raise_periapsis_later


static func _period_days(gm: float, a_km: float) -> float:
	return TAU * sqrt(a_km * a_km * a_km / gm) / 86400.0


static func _ellipse(gm: float, rp: float, ra: float, epoch_jd: float, axis_deg: float, mean_anomaly_deg: float) -> Dictionary:
	var a := 0.5 * (rp + ra)
	return {
		"epoch_jd": epoch_jd,
		"semi_major_axis_km": a,
		"eccentricity": (ra - rp) / (ra + rp),
		"longitude_of_ascending_node_deg": 0.0,
		"argument_of_periapsis_deg": axis_deg,
		"mean_anomaly_deg": mean_anomaly_deg,
		"mean_motion_deg_per_day": TransferPlanner.mean_motion_deg_per_day(gm, a),
	}


# ---------------------------------------------------------------- the plan's aerobraking data

## Prepares plan["aero"] for a plan made by MissionPlanner (which provides rp_t, ra_t, offset_deg,
## arrival_energy, capture_phase_deg, gm_target and dv_capture) and switches the suggestion on if there is one.
static func setup_plan(plan: Dictionary) -> void:
	var target: Dictionary = GameState.bodies[plan["target_id"]]
	var aero := {"available": false, "enabled": false, "outcome": "ok", "message": ""}
	plan["aero"] = aero
	_use_propulsive_capture(plan)
	if not target.has("atmosphere"):
		return
	if GameState.ship_shield_cm <= 0.0:
		aero["message"] = "No heat shield: aerobraking is not possible."
		return
	var atmosphere: Dictionary = target["atmosphere"]
	var area := GameState.ship_shield_area_m2
	var mass := GameState.ship_mass_after_departure(float(plan["dv_departure"]))
	var ctx := {
		"gm": float(plan["gm_target"]), "radius": float(target["radius_km"]), "atmosphere": atmosphere,
		"ra_t": float(plan["ra_t"]), "energy": float(plan["arrival_energy"]),
		"beta": mass / (DRAG_COEFFICIENT * area), "nose": sqrt(area / PI),
		"shield_left_mj_m2": GameState.shield_left_mj_m2(),
		"shield_capacity_mj_m2": shield_capacity_mj_m2(GameState.ship_shield_cm),
	}
	aero["available"] = true
	aero["ctx"] = ctx
	aero["h_min_km"] = float(atmosphere["min_periapsis_altitude_km"])
	aero["h_max_km"] = interface_altitude_km(atmosphere) - 1.0
	var suggestion := suggest(ctx)
	if suggestion.is_empty():
		aero["n"] = 1
		aero["h_km"] = maxf(find_altitude(ctx, 1, SEARCH_DT), float(aero["h_min_km"]))
		center_band(aero, float(aero["h_km"]))
		aero["message"] = "The shield cannot take the heat of a safe aerobraking pass; the capture is propulsive."
		return
	apply(plan, true, int(suggestion["n"]), float(suggestion["h_km"]), true)


## Centres the range of the periapsis slider on altitude h_km.
static func center_band(aero: Dictionary, h_km: float) -> void:
	aero["band_lo"] = maxf(float(aero["h_min_km"]), h_km - BAND_KM)
	aero["band_hi"] = minf(float(aero["h_max_km"]), h_km + BAND_KM)


## Checks the target orbit itself: sets plan["outcome"] ("ok", "crash" or "burn_up"), plan["outcome_text"]
## (what will happen) and plan["warning"] (something to know that does not destroy the ship).
static func _set_target_outcome(plan: Dictionary) -> void:
	var target: Dictionary = GameState.bodies[plan["target_id"]]
	var rp_alt := float(plan["rp_t"]) - float(target["radius_km"])
	plan["outcome"] = "ok"
	plan["outcome_text"] = ""
	plan["warning"] = ""
	if rp_alt < 0.0:
		plan["outcome"] = "crash"
		plan["outcome_text"] = "The periapsis of the target orbit is below the surface: the ship will crash into %s." % target["name"]
	elif target.has("atmosphere"):
		var atmosphere: Dictionary = target["atmosphere"]
		if rp_alt < float(atmosphere["min_periapsis_altitude_km"]):
			plan["outcome"] = "burn_up"
			plan["outcome_text"] = "The periapsis of the target orbit is deep inside the atmosphere of %s: the ship will burn up." % target["name"]
		elif rp_alt < interface_altitude_km(atmosphere):
			plan["warning"] = "The periapsis of the target orbit is inside the upper atmosphere of %s: the orbit will decay." % target["name"]


## The angle of the axis of the target orbit. The offset counts from the arrival direction; a circular orbit
## has no axis, so it simply continues from the arrival.
static func _axis_deg(plan: Dictionary) -> float:
	var phase := float(plan["capture_phase_deg"])
	if OrbitControl.is_circular(float(plan["rp_t"]), float(plan["ra_t"])):
		return phase
	return phase + float(plan["offset_deg"])


## The direction of the periapsis of the orbit the ship arrives on (and of the aerobraking passes). When the
## arrival can be aimed (arriving from outside the sphere of influence) it is aimed at the axis of the target
## orbit, so the apoapsis after the passes is already where the target orbit wants it and nothing has to be
## turned. A transfer to the central body cannot be aimed: it arrives where it arrives.
static func _arrival_axis(plan: Dictionary) -> float:
	return _axis_deg(plan) if bool(plan["aimable"]) else float(plan["capture_phase_deg"])


## Delta-v (km/s) for turning the axis of the arrival orbit to the axis of the target orbit: zero if the
## arrival is aimed or the orbit is circular, otherwise a burn at the crossing point of the two ellipses.
static func axis_turn_dv(plan: Dictionary) -> float:
	if bool(plan["aimable"]) or OrbitControl.is_circular(float(plan["rp_t"]), float(plan["ra_t"])):
		return 0.0
	var rp := float(plan["rp_t"])
	var ra := float(plan["ra_t"])
	var e := (ra - rp) / (ra + rp)
	var p := 2.0 * rp * ra / (rp + ra)
	return 2.0 * e * sqrt(float(plan["gm_target"]) / p) * absf(sin(deg_to_rad(float(plan["offset_deg"])) * 0.5))


## Falls back to the propulsive capture burn at the target orbit.
static func _use_propulsive_capture(plan: Dictionary) -> void:
	plan["dv_arrival"] = float(plan["dv_capture"]) + axis_turn_dv(plan)
	plan["t_end"] = float(plan["t_arr"])
	plan["capture_legs"] = [{
		"parent": plan["target_id"],
		"segment": _ellipse(float(plan["gm_target"]), float(plan["rp_t"]), float(plan["ra_t"]),
				float(plan["t_arr"]), _arrival_axis(plan), 0.0),
		"t_start": float(plan["t_arr"]),
		"label": "Orbit around %s" % plan["target_name"],
		"kind": "orbit",
	}]
	_set_target_outcome(plan)


## Switches aerobraking on or off, or changes its passes and periapsis altitude, and recomputes the results,
## the orbit legs after arrival, the final burns and the end time of the capture. recenter moves the range
## of the periapsis slider to h_km (this also happens when h_km is outside of it).
static func apply(plan: Dictionary, enabled: bool, n: int, h_km: float, recenter := false) -> void:
	var aero: Dictionary = plan["aero"]
	aero["n"] = n
	aero["h_km"] = h_km
	if aero["available"] and (recenter or not aero.has("band_lo") or h_km < float(aero["band_lo"]) or h_km > float(aero["band_hi"])):
		center_band(aero, h_km)
	if not enabled or not aero["available"]:
		aero["enabled"] = false
		aero["outcome"] = "ok"
		_use_propulsive_capture(plan)
		return
	aero["enabled"] = true
	var ctx: Dictionary = aero["ctx"]
	var gm := float(ctx["gm"])
	var radius := float(ctx["radius"])
	var rp_t := float(plan["rp_t"])
	var ra_t := float(plan["ra_t"])
	var result := run_passes(ctx, h_km, n, FINAL_DT)
	var status := str(result["status"])
	aero["heat"] = float(result["heat"])
	aero["peak_g"] = float(result["peak_g"])
	aero["peak_flux"] = float(result["peak_flux"])
	aero["outcome"] = status
	# The shield display never goes beyond what the shield had before the manoeuvre, or below zero.
	var capacity := maxf(float(ctx["shield_capacity_mj_m2"]), 0.000001)
	var left := float(ctx["shield_left_mj_m2"])
	aero["shield_before"] = left / capacity
	aero["shield_after"] = clampf(left - float(result["heat"]), 0.0, left) / capacity
	if status != "ok":
		aero["message"] = "The ship slows down too much: it cannot get out of the atmosphere again, so there is no orbit." \
				if status == "too_slow" else "The ship is still too fast to be captured: it will fly past. Lower the periapsis or add passes."
		aero["days"] = 0.0
		aero["final_dv"] = 0.0
		_use_propulsive_capture(plan)   # only for the legs; the ship is lost on arrival
		plan["outcome"] = status
		plan["outcome_text"] = str(aero["message"])
		plan["dv_arrival"] = 0.0
		aero["entry_times"] = [float(plan["t_arr"]) - 300.0 / 86400.0]
		return
	aero["message"] = ""
	var ras: Array = result["ras"]
	var ra := float(result["ra"])
	var rp := radius + h_km
	var final_burn := final_dv(gm, rp, ra, rp_t, ra_t) + axis_turn_dv(plan)
	aero["final_dv"] = final_burn
	aero["ra"] = ra
	# Orbit legs: one ellipse after each pass (a full period each, the last only to its apoapsis), possibly an
	# ellipse for raising the periapsis, and finally the target orbit.
	var phase := _arrival_axis(plan)
	var t := float(plan["t_arr"])
	var legs: Array = []
	var entry_times: Array = []   # when the ship reaches the upper atmosphere before each pass
	var lead_days := (float(result["seconds"]) / float(n) * 0.5 + 60.0) / 86400.0
	var apoapsis_too_low := ra < rp_t
	for i in n:
		entry_times.append(t - lead_days)
		var last := i == n - 1
		var ra_i := float(ras[i])
		if last and apoapsis_too_low:
			ra_i = ra_t   # the apoapsis is raised with a burn at once
		var period := _period_days(gm, 0.5 * (rp + ra_i))
		legs.append({"parent": plan["target_id"], "segment": _ellipse(gm, rp, ra_i, t, phase, 0.0), "t_start": t,
				"label": "Aerobraking pass %d of %d" % [i + 1, n] if not last else "After aerobraking pass %d of %d" % [n, n],
				"kind": "aero"})
		t += period * (0.5 if last else 1.0)
	var final_anomaly := 180.0   # the ship is at the apoapsis of the target orbit
	if not apoapsis_too_low and absf(ra - ra_t) > 0.005 * ra_t:
		legs.append({"parent": plan["target_id"], "segment": _ellipse(gm, rp_t, ra, t, phase, 180.0), "t_start": t,
				"label": "Raising the periapsis", "kind": "aero"})
		t += _period_days(gm, 0.5 * (rp_t + ra)) * 0.5
		final_anomaly = 0.0
	legs.append({"parent": plan["target_id"], "segment": _ellipse(gm, rp_t, ra_t, t, _axis_deg(plan), final_anomaly),
			"t_start": t, "label": "Orbit around %s" % plan["target_name"], "kind": "orbit"})
	plan["capture_legs"] = legs
	aero["entry_times"] = entry_times
	plan["dv_arrival"] = final_burn
	plan["t_end"] = t
	aero["days"] = t - float(plan["t_arr"])
	_set_target_outcome(plan)
