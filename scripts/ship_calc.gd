class_name ShipCalc
extends RefCounted
## Rocket-equation maths for a ship made of chemical stages (build step 5).
## Stages are listed in firing order: index 0 fires first and is dropped first.
## A stage is a Dictionary: engine_id (String), propellant_kg, thrust_kn, durability (0..1).
## Engine data and design rules come from data/engines.json.

const G0 := 9.80665  # m/s^2, standard gravity


## Mass of the stage without propellant: tank structure (grows with durability) plus engine.
static func stage_dry_mass_kg(stage: Dictionary, engine: Dictionary, rules: Dictionary) -> float:
	var propellant := float(stage["propellant_kg"])
	var structure_fraction := float(rules["tank_structure_fraction_base"]) \
			+ float(rules["tank_structure_fraction_per_durability"]) * float(stage["durability"])
	var engine_mass := float(stage["thrust_kn"]) * 1000.0 / (float(engine["thrust_to_weight"]) * G0)
	return propellant * structure_fraction + engine_mass


## Full analysis of a ship. engines is a Dictionary id -> engine Dictionary.
## Returns {"stages": [per-stage Dictionaries], "total_dv_ms": float, "total_mass_kg": float}.
## Per stage: dv_ms, mass_start_kg, mass_end_kg, dry_kg, accel_start_ms2, burn_time_s.
static func analyse(stages: Array, engines: Dictionary, rules: Dictionary, payload_kg: float) -> Dictionary:
	var results: Array = []
	results.resize(stages.size())
	var mass_above := payload_kg
	# Work from the top stage down, since each stage has to lift everything above it.
	for i in range(stages.size() - 1, -1, -1):
		var stage: Dictionary = stages[i]
		var engine: Dictionary = engines[stage["engine_id"]]
		var propellant := float(stage["propellant_kg"])
		var dry := stage_dry_mass_kg(stage, engine, rules)
		var mass_start := mass_above + dry + propellant
		var mass_end := mass_start - propellant
		var exhaust_velocity := float(engine["isp_vac_s"]) * G0
		var thrust_n := float(stage["thrust_kn"]) * 1000.0
		results[i] = {
			"dv_ms": exhaust_velocity * log(mass_start / mass_end),
			"mass_start_kg": mass_start,
			"mass_end_kg": mass_end,
			"dry_kg": dry,
			"accel_start_ms2": thrust_n / mass_start,
			"burn_time_s": propellant * exhaust_velocity / thrust_n,
		}
		mass_above = mass_start
	var total_dv := 0.0
	for result in results:
		total_dv += float(result["dv_ms"])
	return {"stages": results, "total_dv_ms": total_dv, "total_mass_kg": mass_above}
