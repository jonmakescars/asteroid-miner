class_name OrbitControl
extends HFlowContainer
## A general control for an orbit around a body: periapsis altitude, apoapsis altitude, the angle of its axis of
## eccentricity (offset, in degrees; only if the orbit is not circular) and the direction it runs in (a switch:
## counter-clockwise, direction 1, or clockwise, direction -1).
##
## The two altitudes never conflict: lowering the apoapsis below the periapsis pulls the periapsis down
## with it, raising the periapsis to the apoapsis or beyond pushes the apoapsis up. In both cases they keep
## a tiny gap (EPS), so the orbit is "circular" for all practical purposes without any special case.
## Nothing is forbidden: orbits below the surface are allowed (the mission planner only warns).
##
## Altitudes are in km above the surface. The signal is sent when the player finishes a change: a slider is
## released, or a number is entered.

signal orbit_changed(rp_alt_km: float, ra_alt_km: float, offset_deg: float, direction: int)

const EPS := 0.001            # km, the invisible gap between periapsis and apoapsis
const CIRCULAR_BELOW := 0.0105  # a gap smaller than this (km) counts as circular
const MIN_FRACTION := -0.9    # the lowest altitude, as a fraction of the body radius

var radius_km := 6371.0
var max_alt_km := 100000.0
var rp_alt := 400.0
var ra_alt := 400.0 + EPS
var offset_deg := 0.0
var direction := 1   # 1 counter-clockwise, -1 clockwise

var _syncing := false
var _direction_switch: CheckButton
var _rp_slider: HSlider
var _rp_spin: SpinBox
var _ra_slider: HSlider
var _ra_spin: SpinBox
var _offset_slider: HSlider
var _offset_spin: SpinBox
var _offset_label: Label
var _unit := 1.0   # the shown unit of the altitude boxes per km (1 for km, 1/1.609 for miles)


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
	_syncing = true   # changing the limits of a spin box can change (and announce) its value: ignore that
	_unit = UnitFormat.length_factor()
	add_theme_constant_override("h_separation", 8)
	_rp_spin = _add_row("Periapsis (%s)" % UnitFormat.length_unit(), true)
	_rp_slider = get_child(get_child_count() - 1) as HSlider
	_ra_spin = _add_row("Apoapsis (%s)" % UnitFormat.length_unit(), true)
	_ra_slider = get_child(get_child_count() - 1) as HSlider
	_offset_spin = _add_row("Axis offset (deg)", false)
	_offset_slider = get_child(get_child_count() - 1) as HSlider
	_offset_label = get_child(get_child_count() - 3) as Label
	_rp_spin.value_changed.connect(func(value: float) -> void: _commit("rp", value / _unit))
	_ra_spin.value_changed.connect(func(value: float) -> void: _commit("ra", value / _unit))
	_offset_spin.value_changed.connect(func(value: float) -> void: _commit("offset", value))
	_rp_slider.drag_ended.connect(func(_c: bool) -> void: _commit("rp", _from_slider(_rp_slider.value)))
	_ra_slider.drag_ended.connect(func(_c: bool) -> void: _commit("ra", _from_slider(_ra_slider.value)))
	_offset_slider.drag_ended.connect(func(_c: bool) -> void: _commit("offset", _offset_slider.value))
	var direction_label := Label.new()
	direction_label.text = "Direction"
	add_child(direction_label)
	_direction_switch = CheckButton.new()
	_direction_switch.custom_minimum_size = Vector2(150, 40)
	_direction_switch.text = "counter-clockwise"
	_direction_switch.toggled.connect(func(on: bool) -> void: _commit("dir", -1.0 if on else 1.0))
	add_child(_direction_switch)
	_offset_slider.min_value = -180.0
	_offset_slider.max_value = 180.0
	_offset_slider.step = 1.0
	_offset_spin.min_value = -180.0
	_offset_spin.max_value = 180.0
	_offset_spin.step = 1.0
	for slider in [_rp_slider, _ra_slider]:
		(slider as HSlider).step = 0.001
	_syncing = false


## Adds a label, a spin box and a slider; the slider is the last child, the spin box is returned.
func _add_row(title: String, altitude: bool) -> SpinBox:
	var label := Label.new()
	label.text = title
	add_child(label)
	var spin := SpinBox.new()
	spin.allow_greater = not altitude   # (an altitude cannot be higher than the sphere of influence of the body)
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
	_syncing = true   # setting the limits and the step re-snaps the spin boxes and may emit value_changed
	for slider in [_rp_slider, _ra_slider]:
		(slider as HSlider).min_value = 0.0
		(slider as HSlider).max_value = _to_slider(max_alt_km)
	for spin in [_rp_spin, _ra_spin]:
		(spin as SpinBox).min_value = MIN_FRACTION * radius_km * _unit
		(spin as SpinBox).max_value = max_alt_km * _unit
		(spin as SpinBox).step = 0.1
	_syncing = false


## Shows an orbit without sending the signal.
func set_orbit(rp_alt_km: float, ra_alt_km: float, offset: float, way := 1) -> void:
	rp_alt = rp_alt_km
	ra_alt = ra_alt_km
	offset_deg = offset
	direction = -1 if way < 0 else 1
	_syncing = true
	_direction_switch.set_pressed_no_signal(direction < 0)
	_direction_switch.text = "clockwise" if direction < 0 else "counter-clockwise"
	_rp_spin.set_value_no_signal(rp_alt * _unit)
	_ra_spin.set_value_no_signal(ra_alt * _unit)
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
	var way := direction
	match which:
		"rp":
			rp = minf(value, max_alt_km)
			var pair := normalise(rp, ra, "rp")
			rp = pair.x
			ra = pair.y
		"ra":
			ra = minf(value, max_alt_km)
			var pair := normalise(rp, ra, "ra")
			rp = pair.x
			ra = pair.y
		"offset":
			offset = value
		"dir":
			way = -1 if value < 0.0 else 1
	set_orbit(rp, ra, offset, way)
	orbit_changed.emit(rp, ra, offset, way)
