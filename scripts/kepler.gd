class_name Kepler
extends RefCounted
## Two-body Kepler orbit maths for bodies on rails (2D map view).
## Data files use degrees, kilometres and Julian Dates. Everything here works in radians internally.
## The 2D map ignores inclination: the orbit lies in the map plane and is oriented by the
## longitude of periapsis (node + argument of periapsis). Apsides are held fixed over time.


## Solves M = E - e*sin(E) for the eccentric anomaly E (radians), valid for 0 <= e < 1.
static func solve_eccentric_anomaly(mean_anomaly: float, e: float) -> float:
	var m := wrapf(mean_anomaly, -PI, PI)
	var ecc_anomaly: float = m if e < 0.8 else PI * signf(m)
	for _i in 30:
		var delta := (ecc_anomaly - e * sin(ecc_anomaly) - m) / (1.0 - e * cos(ecc_anomaly))
		ecc_anomaly -= delta
		if absf(delta) < 1e-12:
			break
	return ecc_anomaly


## Picks the orbit segment that applies at Julian Date jd: the last one whose epoch is not
## later than jd (or the first one, if jd is earlier than all of them). Later segments are
## added when something changes a body's orbit, for example an impact.
static func segment_at(segments: Array, jd: float) -> Dictionary:
	var chosen: Dictionary = segments[0]
	for segment in segments:
		if float(segment["epoch_jd"]) <= jd:
			chosen = segment
	return chosen


## Mean anomaly (radians) of an orbit segment at Julian Date jd.
static func mean_anomaly_at(segment: Dictionary, jd: float) -> float:
	var m0 := deg_to_rad(float(segment["mean_anomaly_deg"]))
	var n := deg_to_rad(float(segment["mean_motion_deg_per_day"]))
	return m0 + n * (jd - float(segment["epoch_jd"]))


## Position (km) relative to the parent body at Julian Date jd, in the 2D map plane.
## x and y follow the usual maths orientation (counter-clockwise motion); flip y when drawing.
static func position_at(segment: Dictionary, jd: float) -> Vector2:
	var e := float(segment["eccentricity"])
	var a := float(segment["semi_major_axis_km"])
	var ecc_anomaly := solve_eccentric_anomaly(mean_anomaly_at(segment, jd), e)
	var in_plane := Vector2(a * (cos(ecc_anomaly) - e), a * sqrt(1.0 - e * e) * sin(ecc_anomaly))
	return in_plane.rotated(_periapsis_longitude(segment))


## Points (km, relative to the parent) along the whole orbit ellipse, for drawing.
static func orbit_points(segment: Dictionary, count: int = 128) -> PackedVector2Array:
	var e := float(segment["eccentricity"])
	var a := float(segment["semi_major_axis_km"])
	var rotation := _periapsis_longitude(segment)
	var points := PackedVector2Array()
	for i in count + 1:
		var ecc_anomaly := TAU * float(i) / float(count)
		var in_plane := Vector2(a * (cos(ecc_anomaly) - e), a * sqrt(1.0 - e * e) * sin(ecc_anomaly))
		points.append(in_plane.rotated(rotation))
	return points


static func _periapsis_longitude(segment: Dictionary) -> float:
	return deg_to_rad(float(segment["longitude_of_ascending_node_deg"]) + float(segment["argument_of_periapsis_deg"]))
