class_name UnitFormat
extends RefCounted
## Metric or imperial units for everything the player reads or types (the Units setting). The game works in metric
## inside (km, km/s, kg, kN); only the numbers shown and typed are converted here.
## Heat (MJ/m2, MW/m2) and the g-load stay as they are in both systems.

const KM_PER_MILE := 1.609344
const FT_PER_M := 3.280839895
const KG_PER_LB := 0.45359237
const KG_PER_TON := 907.18474     # a US short ton
const KN_PER_KLBF := 4.4482216    # a thousand pounds-force
const CM_PER_IN := 2.54
const FT2_PER_M2 := 10.76391042


static func imperial() -> bool:
	return UserSettings.is_imperial()


## Distances and altitudes: km, or miles.
static func length(km: float) -> float:
	return km / KM_PER_MILE if imperial() else km


## The factor that turns km into the shown unit (and its inverse turns typed numbers back into km).
static func length_factor() -> float:
	return 1.0 / KM_PER_MILE if imperial() else 1.0


static func length_unit() -> String:
	return "mi" if imperial() else "km"


## Speeds in km/s, or miles per second.
static func speed_kms(kms: float) -> float:
	return kms / KM_PER_MILE if imperial() else kms


static func speed_kms_unit() -> String:
	return "mi/s" if imperial() else "km/s"


## Small speeds (burns) in m/s, or feet per second.
static func speed_ms(ms: float) -> float:
	return ms * FT_PER_M if imperial() else ms


static func speed_ms_unit() -> String:
	return "ft/s" if imperial() else "m/s"


## Masses in kg, or pounds.
static func mass_kg(kg: float) -> float:
	return kg / KG_PER_LB if imperial() else kg


static func mass_kg_unit() -> String:
	return "lb" if imperial() else "kg"


## Larger masses in tonnes, or US tons.
static func mass_t(tonnes: float) -> float:
	return tonnes * 1000.0 / KG_PER_TON if imperial() else tonnes


static func mass_t_unit() -> String:
	return "tons" if imperial() else "t"


static func accel_ms2(a: float) -> float:
	return a * FT_PER_M if imperial() else a


static func accel_unit() -> String:
	return "ft/s2" if imperial() else "m/s2"


static func area_m2(area: float) -> float:
	return area * FT2_PER_M2 if imperial() else area


static func area_unit() -> String:
	return "ft2" if imperial() else "m2"


## The value of a ship design box (its metric unit is "kg", "cm", "kN" or "") in the shown unit, and back.
static func to_display(unit: String, value: float) -> float:
	if not imperial():
		return value
	match unit:
		"kg":
			return value / KG_PER_LB
		"cm":
			return value / CM_PER_IN
		"kN":
			return value / KN_PER_KLBF
	return value


static func from_display(unit: String, value: float) -> float:
	if not imperial():
		return value
	match unit:
		"kg":
			return value * KG_PER_LB
		"cm":
			return value * CM_PER_IN
		"kN":
			return value * KN_PER_KLBF
	return value


static func display_unit(unit: String) -> String:
	if not imperial():
		return unit
	match unit:
		"kg":
			return "lb"
		"cm":
			return "in"
		"kN":
			return "klbf"
	return unit
