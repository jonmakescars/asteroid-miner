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
## periapsis at periapsis_altitude_km. Returns {"crash": true} if the ship hits the ground, otherwise
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

## ctx: {gm, radius, atmosphere, rt (target orbit radius), energy (before the first pass), beta, nose}.
## Runs n passes at the periapsis altitude h_km. Returns {"crash", "heat", "peak_g", "peak_flux", "ras" (apoapsis
## after each pass, km), "seconds" (the time spent in the atmosphere), "ra"}.
static func run_passes(ctx: Dictionary, h_km: float, n: int, dt: float) -> Dictionary:
	var gm := float(ctx["gm"])
	var rp := float(ctx["radius"]) + h_km
	var energy := float(ctx["energy"])
	var heat := 0.0
	var peak_g := 0.0
	var peak_flux := 0.0
	var seconds := 0.0
	var ras: Array = []
	for _i in n:
		var pass_result := simulate_pass(gm, float(ctx["radius"]), ctx["atmosphere"], h_km, energy,
				float(ctx["beta"]), float(ctx["nose"]), dt)
		if pass_result.has("crash"):
			return {"crash": true, "heat": 1.0e9, "peak_g": 1.0e9, "peak_flux": 0.0, "ras": ras, "seconds": seconds, "ra": 0.0}
		energy = float(pass_result["energy"])
		heat += float(pass_result["heat_mj_m2"])
		peak_g = maxf(peak_g, float(pass_result["peak_g"]))
		peak_flux = maxf(peak_flux, float(pass_result["peak_flux_mw_m2"]))
		seconds += float(pass_result["seconds"])
		var ra := apoapsis_from_energy(gm, rp, energy)
		ras.append(ra)
		if ra <= 0.0:
			return {"crash": true, "heat": heat, "peak_g": peak_g, "peak_flux": peak_flux, "ras": ras, "seconds": seconds, "ra": 0.0}
	return {"crash": false, "heat": heat, "peak_g": peak_g, "peak_flux": peak_flux, "ras": ras, "seconds": seconds,
			"ra": float(ras[ras.size() - 1])}


## The periapsis altitude (km) at which n passes end with the apoapsis at the target orbit radius, or -1
## if even the lowest allowed periapsis does not brake enough.
static func find_altitude(ctx: Dictionary, n: int, dt: float) -> float:
	var atmosphere: Dictionary = ctx["atmosphere"]
	var low := float(atmosphere["min_periapsis_altitude_km"])
	var high := interface_altitude_km(atmosphere) - 1.0
	var rt := float(ctx["rt"])
	if float(run_passes(ctx, low, n, dt)["ra"]) > rt:
		return -1.0
	for _i in 12:
		var middle := 0.5 * (low + high)
		if float(run_passes(ctx, middle, n, dt)["ra"]) > rt:
			high = middle
		else:
			low = middle
	return low


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
		if float(result["heat"]) > allowed:
			return {}
		if float(result["peak_g"]) <= G_LIMIT:
			return {"n": n, "h_km": h}
	return {}


# ---------------------------------------------------------------- burns after the passes

static func _speed_at_apoapsis(gm: float, r1: float, r2: float) -> float:
	return sqrt(2.0 * gm * r1 / (r2 * (r1 + r2)))


static func _speed_at_periapsis(gm: float, r1: float, r2: float) -> float:
	return sqrt(2.0 * gm * r2 / (r1 * (r1 + r2)))


## Delta-v (km/s) to go from the orbit with periapsis rp and apoapsis ra to the circular orbit of radius rt:
## raise the periapsis at the apoapsis (or the apoapsis at the periapsis), then circularise.
static func final_dv(gm: float, rp: float, ra: float, rt: float) -> float:
	if ra >= rt:
		var burn_one := absf(_speed_at_apoapsis(gm, rt, ra) - _speed_at_apoapsis(gm, rp, ra))
		var burn_two := _speed_at_periapsis(gm, rt, ra) - sqrt(gm / rt)
		return burn_one + maxf(burn_two, 0.0)
	var raise_apoapsis := _speed_at_periapsis(gm, rp, rt) - _speed_at_periapsis(gm, rp, ra)
	var circularise := sqrt(gm / rt) - _speed_at_apoapsis(gm, rp, rt)
	return raise_apoapsis + maxf(circularise, 0.0)


static func _period_days(gm: float, a_km: float) -> float:
	return TAU * sqrt(a_km * a_km * a_km / gm) / 86400.0


static func _ellipse(gm: float, rp: float, ra: float, epoch_jd: float, phase_deg: float, mean_anomaly_deg: float) -> Dictionary:
	var a := 0.5 * (rp + ra)
	return {
		"epoch_jd": epoch_jd,
		"semi_major_axis_km": a,
		"eccentricity": (ra - rp) / (ra + rp),
		"longitude_of_ascending_node_deg": 0.0,
		"argument_of_periapsis_deg": phase_deg,
		"mean_anomaly_deg": mean_anomaly_deg,
		"mean_motion_deg_per_day": TransferPlanner.mean_motion_deg_per_day(gm, a),
	}


# ---------------------------------------------------------------- the plan's aerobraking data

## Prepares plan["aero"] for a plan made by MissionPlanner (which provides capture_radius, capture_phase_deg,
## gm_target and dv_capture) and switches the suggestion on if there is one.
static func setup_plan(plan: Dictionary) -> void:
	var target: Dictionary = GameState.bodies[plan["target_id"]]
	var aero := {"available": false, "enabled": false, "valid": true, "message": ""}
	plan["aero"] = aero
	_use_propulsive_capture(plan)
	if not target.has("atmosphere"):
		return
	if GameState.ship_shield_cm <= 0.0:
		aero["message"] = "No heat shield: aerobraking is not possible."
		return
	var atmosphere: Dictionary = target["atmosphere"]
	var gm := float(plan["gm_target"])
	var rt := float(plan["capture_radius"])
	var circular := sqrt(gm / rt)
	var speed := circular + float(plan["dv_capture"])
	var area := GameState.ship_shield_area_m2
	var mass := GameState.ship_mass_after_departure(float(plan["dv_departure"]))
	var ctx := {
		"gm": gm, "radius": float(target["radius_km"]), "atmosphere": atmosphere, "rt": rt,
		"energy": 0.5 * speed * speed - gm / rt,
		"beta": mass / (DRAG_COEFFICIENT * area), "nose": sqrt(area / PI),
		"shield_left_mj_m2": GameState.shield_left_mj_m2(),
	}
	aero["available"] = true
	aero["ctx"] = ctx
	aero["h_min_km"] = float(atmosphere["min_periapsis_altitude_km"])
	aero["h_max_km"] = interface_altitude_km(atmosphere) - 1.0
	var suggestion := suggest(ctx)
	if suggestion.is_empty():
		aero["n"] = 1
		aero["h_km"] = maxf(find_altitude(ctx, 1, SEARCH_DT), float(aero["h_min_km"]))
		aero["message"] = "The shield cannot take the heat of a safe aerobraking pass; the capture is propulsive."
		return
	apply(plan, true, int(suggestion["n"]), float(suggestion["h_km"]))


## Falls back to the propulsive capture burn at the target orbit.
static func _use_propulsive_capture(plan: Dictionary) -> void:
	plan["dv_arrival"] = float(plan["dv_capture"])
	plan["t_end"] = float(plan["t_arr"])
	plan["capture_legs"] = [{
		"parent": plan["target_id"],
		"segment": TransferPlanner.circular_segment(float(plan["capture_radius"]), float(plan["gm_target"]),
				float(plan["t_arr"]), float(plan["capture_phase_deg"])),
		"t_start": float(plan["t_arr"]),
		"label": "Orbit around %s" % plan["target_name"],
		"kind": "orbit",
	}]


## Switches aerobraking on or off, or changes its passes and periapsis altitude, and recomputes the results,
## the orbit legs after arrival, the final burn and the end time of the capture.
static func apply(plan: Dictionary, enabled: bool, n: int, h_km: float) -> void:
	var aero: Dictionary = plan["aero"]
	aero["n"] = n
	aero["h_km"] = h_km
	if not enabled or not aero["available"]:
		aero["enabled"] = false
		aero["valid"] = true
		_use_propulsive_capture(plan)
		return
	aero["enabled"] = true
	var ctx: Dictionary = aero["ctx"]
	var gm := float(ctx["gm"])
	var rt := float(ctx["rt"])
	var radius := float(ctx["radius"])
	var result := run_passes(ctx, h_km, n, FINAL_DT)
	aero["heat"] = float(result["heat"])
	aero["peak_g"] = float(result["peak_g"])
	aero["peak_flux"] = float(result["peak_flux"])
	var ras: Array = result["ras"]
	var ra := float(result["ra"])
	var valid := not bool(result["crash"]) and ra < 1.0e9 and ra > 0.0
	aero["valid"] = valid
	aero["ra"] = ra
	aero["shield_share"] = float(result["heat"]) / maxf(float(ctx["shield_left_mj_m2"]), 0.000001)
	if not valid:
		aero["message"] = "This pass would crash into the surface." if bool(result["crash"]) \
				else "The ship still has escape speed after the passes: lower the periapsis or add passes."
		aero["days"] = 0.0
		aero["final_dv"] = float(plan["dv_capture"])
		_use_propulsive_capture(plan)
		return
	aero["message"] = ""
	var rp := radius + h_km
	var final_burn := final_dv(gm, rp, ra, rt)
	aero["final_dv"] = final_burn
	# Orbit legs: one ellipse after each pass (a full period each, the last only to its apoapsis), possibly an
	# ellipse for raising the periapsis, and finally the circular orbit.
	var phase := float(plan["capture_phase_deg"])
	var t := float(plan["t_arr"])
	var legs: Array = []
	var entry_times: Array = []   # when the ship reaches the upper atmosphere before each pass
	var lead_days := (float(result["seconds"]) / float(n) * 0.5 + 60.0) / 86400.0
	for i in n:
		entry_times.append(t - lead_days)
		var ra_i := float(ras[i])
		var period := _period_days(gm, 0.5 * (rp + ra_i))
		var last := i == n - 1
		legs.append({"parent": plan["target_id"], "segment": _ellipse(gm, rp, ra_i, t, phase, 0.0), "t_start": t,
				"label": "Aerobraking pass %d of %d" % [i + 1, n] if not last else "After aerobraking pass %d of %d" % [n, n],
				"kind": "aero"})
		t += period * (0.5 if last else 1.0)
	var circular_phase := phase + 180.0
	if ra > rt * 1.02:
		legs.append({"parent": plan["target_id"], "segment": _ellipse(gm, rt, ra, t, phase, 180.0), "t_start": t,
				"label": "Raising the periapsis", "kind": "aero"})
		t += _period_days(gm, 0.5 * (rt + ra)) * 0.5
		circular_phase = phase
	legs.append({"parent": plan["target_id"], "segment": TransferPlanner.circular_segment(rt, gm, t, circular_phase),
			"t_start": t, "label": "Orbit around %s" % plan["target_name"], "kind": "orbit"})
	plan["capture_legs"] = legs
	aero["entry_times"] = entry_times
	plan["dv_arrival"] = final_burn
	plan["t_end"] = t
	aero["days"] = t - float(plan["t_arr"])
