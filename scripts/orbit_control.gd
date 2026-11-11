class_name OrbitControl
extends HFlowContainer
## A general control for an orbit around a body: periapsis altitude, apoapsis altitude and, if the orbit is
## not circular, the angle of its axis of eccentricity (offset, in degrees).
##
## The two altitudes never conflict: lowering the apoapsis below the periapsis pulls the periapsis down
## with it, raising the periapsis to the apoapsis or beyond pushes the apoapsis up. In both cases they keep
## a tiny gap (EPS), so the orbit is "circular" for all practical purposes without any special case.
## Nothing is forbidden: orbits below the surface are allowed (the mission planner only warns).
##
## Altitudes are in km above the surface. The signal is sent when the player finishes a change: a slider is
## released, or a number is entered.

signal orbit_changed(rp_alt_km: float, ra_alt_km: float, offset_deg: float)

const EPS := 0.001            # km, the invisible gap between periapsis and apoapsis
const CIRCULAR_BELOW := 0.0105  # a gap smaller than this (km) counts as circular
const MIN_FRACTION := -0.9    # the lowest altitude, as a fraction of the body radius

var radius_km := 6371.0
var max_alt_km := 100000.0
var rp_alt := 400.0
var ra_alt := 400.0 + EPS
var offset_deg := 0.0

var _syncing := false
var _rp_slider: HSlider
var _rp_spin: SpinBox
var _ra_slider: HSlider
var _ra_spin: SpinBox
var _offset_slider: HSlider
var _offset_spin: SpinBox
var _offset_label: Label


## Both altitudes after a change. changed is "rp" or "ra": the one the player changed stays as it is.
static func normalise(rp: float, ra: float, changed: String) -> Vector2:
	if changed == "ra":
		if ra < rp + EPS:
			rp = ra - EPS
	else:
		if rp > ra - EPS:
			ra = rp + EPS
	return Vector2(rp, ra)


static func is_circular(rp: float, ra: float) -> bool:
	return ra - rp < CIRCULAR_BELOW


func _init() -> void:
	add_theme_constant_override("h_separation", 8)
	_rp_spin = _add_row("Periapsis (km)", true)
	_rp_slider = get_child(get_child_count() - 1) as HSlider
	_ra_spin = _add_row("Apoapsis (km)", true)
	_ra_slider = get_child(get_child_count() - 1) as HSlider
	_offset_spin = _add_row("Axis offset (deg)", false)
	_offset_slider = get_child(get_child_count() - 1) as HSlider
	_offset_label = get_child(get_child_count() - 3) as Label
	_rp_spin.value_changed.connect(func(value: float) -> void: _commit("rp", value))
	_ra_spin.value_changed.connect(func(value: float) -> void: _commit("ra", value))
	_offset_spin.value_changed.connect(func(value: float) -> void: _commit("offset", value))
	_rp_slider.drag_ended.connect(func(_c: bool) -> void: _commit("rp", _from_slider(_rp_slider.value)))
	_ra_slider.drag_ended.connect(func(_c: bool) -> void: _commit("ra", _from_slider(_ra_slider.value)))
	_offset_slider.drag_ended.connect(func(_c: bool) -> void: _commit("offset", _offset_slider.value))
	_offset_slider.min_value = -180.0
	_offset_slider.max_value = 180.0
	_offset_slider.step = 1.0
	_offset_spin.min_value = -180.0
	_offset_spin.max_value = 180.0
	_offset_spin.step = 1.0
	for slider in [_rp_slider, _ra_slider]:
		(slider as HSlider).step = 0.001


## Adds a label, a spin box and a slider; the slider is the last child, the spin box is returned.
func _add_row(title: String, _altitude: bool) -> SpinBox:
	var label := Label.new()
	label.text = title
	add_child(label)
	var spin := SpinBox.new()
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.custom_minimum_size = Vector2(110, 40)
	add_child(spin)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(150, 40)
	add_child(slider)
	return spin


## Sets the body and the limits for the sliders.
func setup(body_radius_km: float, max_altitude_km: float) -> void:
	radius_km = body_radius_km
	max_alt_km = max_altitude_km
	for slider in [_rp_slider, _ra_slider]:
		(slider as HSlider).min_value = 0.0
		(slider as HSlider).max_value = _to_slider(max_alt_km)
	for spin in [_rp_spin, _ra_spin]:
		(spin as SpinBox).min_value = MIN_FRACTION * radius_km
		(spin as SpinBox).max_value = max_alt_km * 10.0
		(spin as SpinBox).step = 0.1


## Shows an orbit without sending the signal.
func set_orbit(rp_alt_km: float, ra_alt_km: float, offset: float) -> void:
	rp_alt = rp_alt_km
	ra_alt = ra_alt_km
	offset_deg = offset
	_syncing = true
	_rp_spin.set_value_no_signal(rp_alt)
	_ra_spin.set_value_no_signal(ra_alt)
	_rp_slider.set_value_no_signal(_to_slider(rp_alt))
	_ra_slider.set_value_no_signal(_to_slider(ra_alt))
	_offset_spin.set_value_no_signal(offset_deg)
	_offset_slider.set_value_no_signal(offset_deg)
	var circular := is_circular(rp_alt, ra_alt)
	_offset_spin.editable = not circular
	_offset_slider.editable = not circular
	_offset_label.modulate = Color(1, 1, 1, 0.4 if circular else 1.0)
	_syncing = false


## Slider position (0 .. log10 range) for an altitude: logarithmic, so that both low orbits and far
## orbits are easy to set.
func _to_slider(altitude_km: float) -> float:
	return log(maxf(altitude_km, 0.0) + 10.0) / log(10.0) - 1.0


func _from_slider(value: float) -> float:
	return snappedf(pow(10.0, value + 1.0) - 10.0, 0.1)


func _commit(which: String, value: float) -> void:
	if _syncing:
		return
	var rp := rp_alt
	var ra := ra_alt
	var offset := offset_deg
	match which:
		"rp":
			rp = value
			var pair := normalise(rp, ra, "rp")
			rp = pair.x
			ra = pair.y
		"ra":
			ra = value
			var pair := normalise(rp, ra, "ra")
			rp = pair.x
			ra = pair.y
		"offset":
			offset = value
	set_orbit(rp, ra, offset)
	orbit_changed.emit(rp, ra, offset)
