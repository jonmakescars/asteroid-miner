extends Control
## Orbit view: the one map screen. It shows a system (the Sun, a planet with its moons) with the bodies
## on rails, the ship and its planned route. The panels below the top bar depend on the context:
##  - the mission planner (destination, Plan, Launch, Skip) appears in a system that contains a ship
##    that can launch (it is in orbit around the body in view or one of its moons), or while a plan waits;
##  - ship operations (refuel, load facility kits at a shipyard, deploy a kit) appear with the planner,
##    each only where it is possible;
##  - the Ship design button in the top bar appears where the ship is at a shipyard.
## "Plan" finds the next launch window and the burns; "Launch" commits the plan; then run time forward
## (or use "Skip to Departure") and watch the ship follow its orbit legs.

const SKIP_LEAD_DAYS := 120.0 / 86400.0  # "skip to departure" stops two minutes before the burn
const LATE_LAUNCH_DAYS := 300.0 / 86400.0  # a plan can still be launched this long after its departure time
const MIN_LAUNCH_DELAY_DAYS := 20.0 / 86400.0  # the first burn (the start of the ship's turn for it) is never earlier than this after "now"
const MIN_BODY_RADIUS_PX := 3.0
const BIG_BODY_PX := 60.0             # a body bigger than this (radius on the screen) does not take taps in the time-control area
const SHIP_FOCUS := "@ship"            # the name of the ship as the target of a tap or a zoom
const SHIP_PLASMA := "effects/plasma_wide"   # the shock front of aerobraking (pointed, blunt or wide, by hull)
const SHIP_SPRITE := "ships/lander_parts/lander_body"   # the lander with its legs retracted (until the ship design chooses the hull)
const SHIP_LENGTH_PX := 22.6           # the ship is a marker: it keeps this length on the screen at every zoom (30% smaller than the extended lander at 36 px)
const SHIP_FULL_BODY_FRACTION := 0.25  # the sprite is shown in full once it covers at most this part of the body's diameter ...
const SHIP_FADE_FROM := 0.667          # ... and is replaced by the triangle below this fraction of that size (smooth transition)
const SHIP_SHADOW_LIGHT := 0.25        # brightness of the ship in the shadow of the body it orbits
const SHIP_VELOCITY_STEP_DAYS := 60.0 / 86400.0
const RING_RADIUS_PX := 10.0
const RING_BELOW_PX := 2.0         # a body whose true radius is smaller than this many pixels gets a ring around it
const ORBIT_SAMPLES := 160
const MOBILE_UI_SCALE := 2.0
const ZOOM_SECONDS := 0.7          # a change of the view is a zoom of this many (real) seconds
const DOUBLE_TAP_MS := 400         # two taps on the same body within this time focus the view on it
const MAX_PX_PER_KM := 2.0         # the most the view can be zoomed in by hand
const MIN_SUN_FIT := 0.25          # the most it can be zoomed out: this fraction of the scale that fits the Sun's system
const PAN_DELAY_MS := 250          # one-finger dragging is blocked this long after a zoom
const DRAG_START_PX := 12.0        # a finger that moves this far is dragging the view, not tapping
const SNAP_OUT := 0.6667           # zooming out until the view is 50% wider than a body's own view switches to the view of the body it orbits
const TAP_REACH_PX := 26.0         # a tap this close to a body (besides its size) counts as a tap on it
const VIEW_HYSTERESIS := 1.15     # the auto view switches outwards at this multiple of the distance it switched in at

# The game state is shared between screens (see GameState); these properties are shortcuts to it.
var bodies: Dictionary:
	get: return GameState.bodies
var children: Dictionary:
	get: return GameState.children
var time_jd: float:
	get: return GameState.time_jd
	set(value): GameState.time_jd = value
var paused: bool:
	get: return GameState.paused
	set(value): GameState.paused = value
var warp_index: int:
	get: return GameState.warp_index
	set(value): GameState.warp_index = value
var legs: Array:
	get: return GameState.legs
	set(value): GameState.legs = value
var plan: Dictionary:
	get: return GameState.plan
	set(value): GameState.plan = value
var message: String:
	get: return GameState.message
	set(value): GameState.message = value

var cam_body := ""              # the camera: the body its position is counted from ...
var cam_offset := Vector2.ZERO  # ... the point at the centre of the screen, relative to that body (km)
var cam_scale := 0.0            # pixels per km
var free_camera := false        # true after the player zoomed by hand: the camera stays where it is
var last_target := ""           # the view that was chosen last (a change of it starts a zoom)
var anim_target := ""           # while zooming to a view: that view, and where the zoom started
var anim_t := 0.0
var anim_free := false
var anim_keep_scale := false    # the zoom only centres the view on the body (the scale stays)
var ship_follow := false        # the view follows the ship (set by a zoom or a tap on the ship, never by a drag)
var follow_body := ""           # the body the ship orbits while the view follows it
var follow_scale := 0.0         # the scale at which the view started to follow the ship
var anim_body0 := ""
var anim_offset0 := Vector2.ZERO
var anim_scale0 := 1.0
var line_alpha := 1.0           # transparency of the orbit lines and of the markers of the scene being drawn
var marker_alpha := 1.0
var touches: Dictionary = {}    # finger index -> position, for the pinch gesture
var gesture_ms := -1000         # when a pinch or a wheel zoom last happened (taps right after it are ignored)
var last_tap_body := ""
var last_tap_ms := 0
var mouse_down := false         # the (first) finger or the left button is down
var dragged := false            # ... and has moved so far that it drags the view
var press_point := Vector2.ZERO
var last_tap_point := Vector2.ZERO
var last_context := ""          # the context of the ship at the last frame (a change of it resets the view, see _update_context_zoom)
var auto_frame := ""            # the body the "auto" view currently shows (see _update_auto_frame)
var destination_ids: Array = []  # what the destination picker currently offers
var picker_origin := ""         # the body the picker was filled for

var sprite_layer: Node2D        # the body sprites; drawn behind this control's own drawing (lines, names, the ship)
var sprite_nodes: Dictionary = {}    # sprite key -> Sprite2D
var current_scene := ""         # the scene being drawn
var marker_owner: Dictionary = {}        # body id -> [scene that draws its marker, rank]
var marker_owner_alpha: Dictionary = {}  # body id -> opacity of its marker
var scene_rank := 0              # 0 while drawing the camera body's own scene (its positions are exact), else 1
var ship_layer: Node2D          # the ship sprite, drawn over this control's own drawing
var ship_node: Sprite2D
var ship_flame: Sprite2D
var ship_plasma: Sprite2D
var ship_pivot_x := 0.0
var ship_length_units := 0.0
var ship_request: Dictionary = {}
var ship_angle := 0.0
var retro_shown := 0.0          # how far round the ship is now (0 nose first, 1 tail first); follows the plan's attitude at the turning rate
var retro_jd := -1.0
var fixed_shown := 0.0         # the same for the turn to the fixed heading of the axis-turning burn (0 along the course, 1 at the burn heading)
var fixed_jd := -1.0
var sprite_requests: Dictionary = {}  # what _draw wants shown this frame: sprite key -> request
var bar: TopBar
var info_label: RichTextLabel
var target_picker: OptionButton
var plan_button: Button
var launch_button: Button
var abort_button: Button
var keep_button: Button
var warning_label: Label
var launch_dialog: ConfirmationDialog
var lost_overlay: ShipLostOverlay
var skip_button: Button
var refuel_button: Button
var deploy_button: Button
var buy_button: Button
var shield_button: Button
var aero_row: HFlowContainer
var aero_check: CheckButton
var passes_slider: HSlider
var passes_label: Label
var altitude_slider: HSlider
var altitude_label: Label
var altitude_spin: SpinBox
var altitude_minus: Button
var altitude_plus: Button
var altitude_dragging := false
var orbit_row: HFlowContainer
var orbit_control: OrbitControl
var orbit_title: Label
var planner_row: HFlowContainer
var ops_row: HFlowContainer
var syncing_aero := false
var kit_buttons: Dictionary = {}   # facility type id -> button


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = MOBILE_UI_SCALE
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	if not GameState.load_data():
		set_process(false)
		return
	_build_ui()
	_fill_destinations(GameState.view_target_id)


func _goto(scene_path: String) -> void:
	GameState.view_target_id = _selected_target_id()
	get_tree().change_scene_to_file(scene_path)


# ---------------------------------------------------------------- user interface

func _build_ui() -> void:
	bar = TopBar.new()
	bar.setup("res://main.tscn", "")
	bar.navigate.connect(_goto)
	add_child(bar)

	planner_row = bar.add_row()
	var row := planner_row
	target_picker = OptionButton.new()
	target_picker.item_selected.connect(func(_i: int) -> void: _on_target_changed())
	row.add_child(target_picker)
	plan_button = _add_button(row, "Plan", _on_plan)
	launch_button = _add_button(row, "Launch", _on_launch)
	skip_button = _add_button(row, "Skip to Departure & Launch", _on_skip)
	abort_button = _add_button(row, "Abort launch", _on_abort)
	keep_button = _add_button(row, "Keep current course", _on_keep_course)
	launch_dialog = ConfirmationDialog.new()
	launch_dialog.title = "Warning"
	launch_dialog.ok_button_text = "Launch anyway"
	launch_dialog.cancel_button_text = "Back to planning"
	launch_dialog.dialog_autowrap = true
	launch_dialog.wrap_controls = true
	add_child(launch_dialog)
	aero_row = bar.add_row()
	aero_check = CheckButton.new()
	aero_check.text = "Aerobrake"
	aero_check.toggled.connect(func(pressed: bool) -> void:
		_apply_aero(pressed, int(passes_slider.value), altitude_slider.value))
	aero_row.add_child(aero_check)
	passes_label = Label.new()
	aero_row.add_child(passes_label)
	passes_slider = HSlider.new()
	passes_slider.min_value = 1
	passes_slider.max_value = AeroBraking.MAX_PASSES
	passes_slider.step = 1
	passes_slider.custom_minimum_size = Vector2(160, 40)
	# Changing the number of passes picks the periapsis altitude that still reaches the target orbit; this is
	# slow enough to wait until the slider is released.
	passes_slider.value_changed.connect(func(value: float) -> void:
		passes_label.text = "Passes: %d" % int(value))
	passes_slider.drag_ended.connect(func(_changed: bool) -> void: _on_passes_changed())
	aero_row.add_child(passes_slider)
	altitude_label = Label.new()
	altitude_label.text = "Periapsis altitude:"
	aero_row.add_child(altitude_label)
	altitude_minus = _add_button(aero_row, "-", func() -> void: _nudge_altitude(-0.1))
	altitude_slider = HSlider.new()
	altitude_slider.step = 0.1
	altitude_slider.custom_minimum_size = Vector2(220, 40)
	# The slider only covers a band around the current setting (see AeroBraking.BAND_KM); the number box
	# takes any altitude. The aerobraking numbers are recalculated when the slider is released.
	altitude_slider.drag_started.connect(func() -> void: altitude_dragging = true)
	altitude_slider.drag_ended.connect(func(_changed: bool) -> void:
		altitude_dragging = false
		_apply_aero(aero_check.button_pressed, int(passes_slider.value), altitude_slider.value))
	altitude_slider.value_changed.connect(func(value: float) -> void:
		if syncing_aero:
			return
		altitude_label.text = "Periapsis altitude:"
		if altitude_dragging:
			altitude_spin.set_value_no_signal(value)
		else:
			_apply_aero(aero_check.button_pressed, int(passes_slider.value), value))
	aero_row.add_child(altitude_slider)
	altitude_plus = _add_button(aero_row, "+", func() -> void: _nudge_altitude(0.1))
	altitude_spin = SpinBox.new()
	altitude_spin.step = 0.1
	altitude_spin.suffix = "km"
	altitude_spin.custom_minimum_size = Vector2(120, 40)
	altitude_spin.value_changed.connect(func(value: float) -> void:
		if not syncing_aero:
			_apply_aero(aero_check.button_pressed, int(passes_slider.value), value, true))
	aero_row.add_child(altitude_spin)
	_add_button(aero_row, "Auto", _on_aero_auto)
	orbit_row = bar.add_row()
	orbit_title = Label.new()
	orbit_title.text = "Target orbit:"
	orbit_row.add_child(orbit_title)
	orbit_control = OrbitControl.new()
	orbit_control.orbit_changed.connect(_on_target_orbit_changed)
	orbit_row.add_child(orbit_control)
	ops_row = bar.add_row()
	refuel_button = _add_button(ops_row, "Refuel", _on_refuel)
	buy_button = _add_button(ops_row, "Buy propellant", _on_buy)
	for type_id in GameState.kit_type_ids():
		var id: String = type_id
		var kit_button := _add_button(ops_row, "Load %s kit" % str(GameState.facility_types[id]["name"]).to_lower(),
				func() -> void: GameState.message = GameState.load_kit(id))
		kit_buttons[id] = kit_button
	shield_button = _add_button(ops_row, "Replace heat shield", func() -> void: GameState.message = GameState.replace_shield())
	deploy_button = _add_button(ops_row, "Deploy", _on_deploy)
	_add_button(ops_row, "Reset game", _on_reset)

	warning_label = Label.new()
	warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	bar.box.add_child(warning_label)
	info_label = RichTextLabel.new()   # rich text so that single lines can be coloured
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.scroll_active = false
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.box.add_child(info_label)


## Two fingers zoom (and move) the view; the mouse wheel does the same. Tapping or clicking the bottom third of the
## screen changes the time flow, as in the solar system view: left half = slower, right half = faster. Two quick taps
## on a body zoom to it.
func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			touches[touch.index] = touch.position
			if touches.size() >= 2:
				gesture_ms = Time.get_ticks_msec()
		else:
			touches.erase(touch.index)
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		if touches.size() >= 2 and touches.has(drag.index):
			var before_middle := _touch_middle()
			var before_distance := _touch_distance()
			touches[drag.index] = drag.position
			var after_distance := _touch_distance()
			if before_distance > 8.0 and after_distance > 8.0:
				_zoom_about(before_middle, after_distance / before_distance, _touch_middle())
			gesture_ms = Time.get_ticks_msec()
		elif touches.has(drag.index):
			touches[drag.index] = drag.position
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		# One finger (or the left button) drags the view, but not while two fingers are down or shortly after a zoom
		# (so that lifting one finger a little earlier than the other does not move the view); a drag then starts from
		# where the finger is.
		if mouse_down:
			if touches.size() >= 2 or Time.get_ticks_msec() - gesture_ms < PAN_DELAY_MS:
				press_point = motion.position
				dragged = false
			elif anim_target == "":
				if not dragged and motion.position.distance_to(press_point) > DRAG_START_PX:
					dragged = true
					_pan(motion.position - press_point)
				elif dragged:
					_pan(motion.relative)
		return
	var click := event as InputEventMouseButton
	if click == null:
		return
	if click.pressed and (click.button_index == MOUSE_BUTTON_WHEEL_UP or click.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_zoom_about(click.position, 1.2 if click.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2, click.position)
		gesture_ms = Time.get_ticks_msec()
		return
	if click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.pressed:
		mouse_down = true
		dragged = false
		press_point = click.position
		return
	mouse_down = false
	# A tap counts when the finger is lifted, and not at the end of a pinch or a drag.
	if dragged or Time.get_ticks_msec() - gesture_ms < 350:
		dragged = false
		return
	var hit := _body_at(click.position)
	# A body so big that it fills the bottom of the screen must not swallow the taps for the time controls there.
	if hit != "" and hit != SHIP_FOCUS and click.position.y >= size.y * 0.67 \
			and float(bodies[hit]["radius_km"]) * cam_scale > BIG_BODY_PX:
		hit = ""
	if hit != "":
		# A tap on a body does not change the warp; two quick taps on the same body zoom to it.
		var now := Time.get_ticks_msec()
		if hit == last_tap_body and now - last_tap_ms <= DOUBLE_TAP_MS:
			last_tap_body = ""
			_focus_body(hit)
		else:
			last_tap_body = hit
			last_tap_ms = now
		return
	if click.position.y < size.y * 0.67:
		# Two quick taps on empty space: back to the automatic view.
		var now_empty := Time.get_ticks_msec()
		if last_tap_body == "-" and now_empty - last_tap_ms <= DOUBLE_TAP_MS and click.position.distance_to(last_tap_point) < 60.0:
			last_tap_body = ""
			_start_zoom(_frame_id(), false)
		else:
			last_tap_body = "-"
			last_tap_ms = now_empty
			last_tap_point = click.position
		return
	last_tap_body = ""
	GameState.change_warp(-1 if click.position.x < size.x * 0.5 else 1)


func _touch_middle() -> Vector2:
	var total := Vector2.ZERO
	for index in touches:
		total += touches[index] as Vector2
	return total / float(maxi(touches.size(), 1))


## Distance between the first two fingers.
func _touch_distance() -> float:
	var points: Array = touches.values()
	if points.size() < 2:
		return 0.0
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


func _view_centre() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.58)


## Where a body is on the screen.
func _screen_of(id: String) -> Vector2:
	return _to_screen(GameState.body_rel_to(cam_body, id, time_jd) - cam_offset, _view_centre(), cam_scale)


## The body under a tap, or "" (the nearest one if several are close).
func _body_at(point: Vector2) -> String:
	if cam_body == "" or anim_target != "":
		return ""
	# Only what the view is about can be tapped: the body of the view, the body it orbits and (once the view shows
	# the body in its own size) its moons and the ship; zoomed out, the bodies next to it instead. So a tap on a
	# planet in the solar system view never hits the moon that lies on top of it.
	var pool: Array = [cam_body]
	var parent: Variant = bodies[cam_body]["parent"]
	var close := cam_scale >= 0.7 * _fit_scale(cam_body)
	if parent != null:
		pool.append(str(parent))
		if not close:
			pool.append_array(children[str(parent)])
	if close:
		pool.append_array(children[cam_body])
		if not GameState.ship_lost and not GameState.legs.is_empty() and _ship_orbit_body() == cam_body:
			var ship_point := _to_screen(GameState.ship_rel(cam_body, time_jd) - cam_offset, _view_centre(), cam_scale)
			if ship_point.distance_to(point) <= TAP_REACH_PX:
				return SHIP_FOCUS
	var best := ""
	var best_distance := INF
	for id in pool:
		var radius_px := maxf(float(bodies[id]["radius_km"]) * cam_scale, RING_RADIUS_PX)
		var distance := _screen_of(str(id)).distance_to(point)
		if distance <= radius_px + TAP_REACH_PX and distance < best_distance:
			best = str(id)
			best_distance = distance
	return best


## Double tap on a body: the view zooms to it. A double tap on the body the view is already on zooms out to the
## body it orbits (back to the automatic view when that is the Sun).
func _focus_body(id: String) -> void:
	if id == SHIP_FOCUS:
		# The ship in focus (the view follows it): another double tap zooms out to the body it orbits.
		if _ship_locked() and absf(log(cam_scale / _ship_focus_scale())) < 0.35:
			_start_zoom(follow_body, true)
		else:
			_start_zoom(SHIP_FOCUS, true)
		return
	var on_it := id == cam_body and absf(log(cam_scale / _fit_scale(id))) < 0.35
	if not on_it:
		_start_zoom(id, true)
		return
	var parent: Variant = bodies[id]["parent"]
	if parent == null:
		_start_zoom(_frame_id(), false)
	else:
		_start_zoom(str(parent), true)


## Pixels per km of the view of a body: its widest orbit fits the screen.
func _fit_scale(frame_id: String) -> float:
	var half_extent := minf(size.x * 0.5, size.y * 0.38)
	return half_extent * GameState.VIEW_FILL / GameState.view_extent_km(frame_id, time_jd)


## Zooms to the view of a body. keep_free: the camera then stays on that body (set by the player); otherwise it
## goes back to following the automatic view.
func _start_zoom(target: String, keep_free: bool) -> void:
	anim_target = target
	anim_free = keep_free
	anim_t = 0.0
	anim_body0 = cam_body
	anim_offset0 = cam_offset
	anim_scale0 = cam_scale
	anim_keep_scale = false
	free_camera = false
	ship_follow = false


## Moves the camera: follows the chosen view, or zooms to it when the choice changed, or stays where the
## player put it.
func _update_camera(delta: float) -> void:
	var target := _frame_id()
	if cam_body == "":
		cam_body = target
		cam_offset = Vector2.ZERO
		cam_scale = _fit_scale(target)
		last_target = target
		return
	if target != last_target:
		last_target = target
		_start_zoom(target, false)
	if anim_target != "":
		anim_t += delta / ZOOM_SECONDS
		var w := smoothstep(0.0, 1.0, clampf(anim_t, 0.0, 1.0))
		var from_point := GameState.body_rel_to(cam_body, anim_body0, time_jd) + anim_offset0
		var to_ship := anim_target == SHIP_FOCUS
		var to_point := GameState.ship_rel(cam_body, time_jd) if to_ship else GameState.body_rel_to(cam_body, anim_target, time_jd)
		var scale_end := anim_scale0 if anim_keep_scale else (_ship_focus_scale() if to_ship else _fit_scale(anim_target))
		var scale_now := exp(lerpf(log(anim_scale0), log(scale_end), w))
		var span := 1.0 / anim_scale0 - 1.0 / scale_end
		var k := w if absf(span) < 1.0e-30 else (1.0 / anim_scale0 - 1.0 / scale_now) / span
		cam_offset = from_point + (to_point - from_point) * k
		cam_scale = scale_now
		if anim_t >= 1.0:
			if to_ship:
				var orbited := _ship_orbit_body()
				if orbited != "":
					cam_body = orbited
					cam_offset = GameState.ship_rel(cam_body, time_jd)
					ship_follow = true
					follow_body = orbited
					follow_scale = scale_end
			else:
				cam_body = anim_target
				cam_offset = Vector2.ZERO
			cam_scale = scale_end
			free_camera = anim_free
			anim_target = ""
	elif not free_camera:
		cam_offset = GameState.body_rel_to(cam_body, target, time_jd)
		cam_scale = _fit_scale(target)
	_rebase()
	_lock_to_ship()


## The body the ship is really in orbit around now ("" on a transfer or when the ship is lost).
func _ship_orbit_body() -> String:
	if GameState.ship_lost or GameState.legs.is_empty():
		return ""
	var leg: Dictionary = GameState.legs[GameState.leg_index_at(time_jd)]
	return str(leg["parent"]) if str(leg["kind"]) in ["orbit", "aero"] else ""


## True while the view follows the ship instead of the body it orbits.
func _ship_locked() -> bool:
	return ship_follow


## Called after a zoom by hand: the view starts to follow the ship when it is zoomed in beyond the normal view of
## the body the ship orbits (the camera is on that body), the ship is on the screen and the centre of the body is
## farther from the middle of the screen than half the smaller screen dimension. A drag never starts it.
func _try_follow() -> void:
	if ship_follow or cam_body == "" or anim_target != "":
		return
	var orbited := _ship_orbit_body()
	if orbited == "" or orbited != cam_body or cam_scale < _fit_scale(orbited):
		return
	var ship_from_centre := GameState.ship_rel(cam_body, time_jd) - cam_offset
	if ship_from_centre.length() * cam_scale > maxf(size.x, size.y) * 0.6:
		return
	var body_from_centre := GameState.body_rel_to(cam_body, orbited, time_jd) - cam_offset
	if body_from_centre.length() * cam_scale > minf(size.x, size.y) * 0.5:
		ship_follow = true
		follow_body = orbited
		follow_scale = cam_scale


const FOLLOW_RELEASE_FACTOR := 1.25   # the view lets go of the ship when it is zoomed out by this much from where it began to follow

## Follows the ship, also on a burn or a transfer far from the body it left, until the view is zoomed out by more than
## FOLLOW_RELEASE_FACTOR from the scale at which the following began, the player taps out (any zoom to a body), or
## the ship goes into orbit around another body. Then the view lets go and centres on the body.
func _lock_to_ship() -> void:
	if not ship_follow:
		return
	var orbited := _ship_orbit_body()
	var other_orbit := orbited != "" and orbited != follow_body
	if other_orbit or GameState.ship_lost or cam_scale < follow_scale / FOLLOW_RELEASE_FACTOR:
		_start_zoom(orbited if other_orbit else follow_body, true)
		anim_keep_scale = true
		return
	cam_offset = GameState.ship_rel(cam_body, time_jd)
	free_camera = true


## Pixels per km at which the ship is in focus: the body it orbits is large and the ship is on its orbit well
## outside the middle of the screen, so the view follows the ship.
func _ship_focus_scale() -> float:
	var orbited := _ship_orbit_body()
	if orbited == "":
		return cam_scale
	var distance := maxf(GameState.ship_rel(orbited, time_jd).length(), 1.0)
	var wanted := 0.75 * minf(size.x, size.y) / distance
	return clampf(maxf(wanted, _fit_scale(orbited) * 1.01), 0.0, MAX_PX_PER_KM)


## Pinch, wheel: zooms by a factor so that the point under the fingers (point) ends up under the new
## position of the fingers (new_point).
func _zoom_about(point: Vector2, factor: float, new_point: Vector2) -> void:
	if cam_body == "" or anim_target != "":
		return   # a zoom to a view is running
	var centre := _view_centre()
	var lowest := MIN_SUN_FIT * _fit_scale("sun")
	var new_scale := clampf(cam_scale * factor, lowest, MAX_PX_PER_KM)
	# Zooming out past the normal view of a body: the view of the body it orbits takes over (Moon -> Earth -> Sun).
	var parent: Variant = bodies[cam_body]["parent"]
	if factor < 1.0 and parent != null and new_scale < SNAP_OUT * _fit_scale(cam_body):
		_start_zoom(str(parent), true)
		return
	var before := Vector2(point.x - centre.x, -(point.y - centre.y)) / cam_scale
	var after := Vector2(new_point.x - centre.x, -(new_point.y - centre.y)) / new_scale
	cam_offset = cam_offset + before - after
	cam_scale = new_scale
	free_camera = true
	_rebase()
	_try_follow()


## One finger drags the view: the picture moves with the finger.
func _pan(screen_delta: Vector2) -> void:
	if cam_body == "" or anim_target != "" or _ship_locked():
		return   # (a view that follows the ship cannot be dragged: zoom out first)
	cam_offset -= Vector2(screen_delta.x, -screen_delta.y) / cam_scale
	free_camera = true
	_rebase()


## The camera is counted from the body whose own view has about the scale it has now (its parent, itself or a
## child it is near), so that the numbers stay small. Nothing changes on the screen.
func _rebase() -> void:
	var best := cam_body
	var best_score := absf(log(cam_scale / _fit_scale(cam_body)))
	var candidates: Array = (children[cam_body] as Array).duplicate()
	var parent: Variant = bodies[cam_body]["parent"]
	if parent != null:
		candidates.append(str(parent))
	for id in candidates:
		var rel := GameState.body_rel_to(cam_body, str(id), time_jd)
		if str(id) != str(parent) and (cam_offset - rel).length() > 1.5 * GameState.view_radius_km(str(id), time_jd):
			continue   # a child the camera is not near
		var score := absf(log(cam_scale / _fit_scale(str(id))))
		if score < best_score - 0.5:
			best = str(id)
			best_score = score
	if best != cam_body:
		cam_offset += GameState.body_rel_to(best, cam_body, time_jd)
		cam_body = best


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			_goto("res://menu.tscn")
		KEY_SPACE:
			GameState.toggle_pause()
		KEY_EQUAL, KEY_KP_ADD, KEY_PERIOD:
			GameState.change_warp(1)
		KEY_MINUS, KEY_KP_SUBTRACT, KEY_COMMA:
			GameState.change_warp(-1)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _selected_target_id() -> String:
	if target_picker.selected < 0 or target_picker.selected >= destination_ids.size():
		return ""
	return destination_ids[target_picker.selected]


## What the destination picker was filled for: the body the ship is orbiting, or the body it is flying around.
func _picker_key() -> String:
	var body := GameState.ship_body()
	return body if body != "" else "flight:" + GameState.ship_frame()


## Fills the destination picker (the bodies near the ship's orbit, or the bodies it can be redirected to in
## flight); keeps the previous choice if still offered.
func _fill_destinations(keep_id: String) -> void:
	picker_origin = _picker_key()
	target_picker.clear()
	destination_ids = []
	if GameState.ship_body() != "":
		destination_ids = MissionPlanner.destinations(GameState.ship_body())
	else:
		destination_ids = CourseChange.destinations()
	var here := GameState.ship_body() if GameState.ship_body() != "" else GameState.ship_frame()
	for id in destination_ids:
		target_picker.add_item(("Orbit around " if id == here else "To ") + str(bodies[id]["name"]))
	var index := destination_ids.find(keep_id)
	target_picker.select(maxi(index, 0))


func _on_target_changed() -> void:
	if GameState.ship_in_transit():
		_drop_draft(false)   # another destination was picked: the draft of the old one is no longer meant
		return
	if not plan.is_empty() and not bool(plan["committed"]) and not GameState.parked_leg().is_empty():
		# The planner is open: it stays open for the new destination. The orbit that was chosen stays, as far as it is
		# possible around the new body; the limits of the sliders and the aerobraking start again for the new body.
		var new_id := _selected_target_id()
		if new_id != "":
			GameState.target_orbits[new_id] = _orbit_for_body(new_id, plan["target_orbit"])
			_make_plan(false)
			if not plan.is_empty():
				last_target = _frame_id()
				_start_zoom(last_target, false)
			return
	legs = [GameState.parked_leg()]
	plan = {}
	message = ""


## The orbit (rp_alt_km, ra_alt_km, offset_deg) kept for another body: the same numbers, except that the periapsis
## is raised above the atmosphere limit of the body and nothing goes above the highest possible altitude.
func _orbit_for_body(body_id: String, orbit: Dictionary) -> Dictionary:
	var body: Dictionary = bodies[body_id]
	var highest := GameState.max_orbit_altitude_km(body_id)
	var rp := float(orbit["rp_alt_km"])
	var ra := float(orbit["ra_alt_km"])
	if body.get("atmosphere") is Dictionary:
		rp = maxf(rp, float((body["atmosphere"] as Dictionary)["min_periapsis_altitude_km"]))
	rp = minf(rp, highest)
	ra = minf(maxf(ra, rp + OrbitControl.EPS), highest + OrbitControl.EPS)
	rp = minf(rp, ra - OrbitControl.EPS)
	return {"rp_alt_km": rp, "ra_alt_km": ra, "offset_deg": float(orbit["offset_deg"])}


## "Keep current course": drops the draft and shows the course the ship is following again, with its
## destination and target orbit.
func _on_keep_course() -> void:
	_drop_draft(true)


func _drop_draft(show_followed_course: bool) -> void:
	if GameState.saved_plan.is_empty():
		return
	plan = GameState.saved_plan
	GameState.saved_plan = {}
	if show_followed_course:
		var index := destination_ids.find(str(plan["target_id"]))
		if index >= 0:
			target_picker.select(index)
		GameState.target_orbits[str(plan["target_id"])] = plan["target_orbit"]
		_sync_aero()
		_sync_orbit_control()
		message = "Keeping the current course."


## Makes a plan whose first burn starts at least MIN_LAUNCH_DELAY_DAYS after now, counted from the moment the ship
## starts turning for it (the burn is centred on the departure time: half of its duration before it, and the turn
## before that). make_plan(start_jd) is the planner to call.
func _plan_with_delay(make_plan: Callable) -> Dictionary:
	var turn := GameState.half_turn_days()
	var delay := MIN_LAUNCH_DELAY_DAYS + turn
	var result: Dictionary = make_plan.call(time_jd + delay, -1.0, false)
	for _attempt in 2:
		if result.has("error"):
			break
		var burn := GameState.burn_days(float(result.get("dv_departure", 0.0)))
		var needed := MIN_LAUNCH_DELAY_DAYS + turn + 0.5 * burn
		if float(result["t_dep"]) >= time_jd + needed:
			break
		delay = needed
		result = make_plan.call(time_jd + delay, -1.0, false)
	return _postpone_for_route(make_plan, result)


const ROUTE_SHIFT_STEP_DAYS := 1.0    # a launch that leaves the best window is tried this many days earlier or later ...
const ROUTE_SHIFT_MAX_DAYS := 30.0    # ... up to this far, before the launch is postponed to a later window
const ROUTE_SHIFT_DV_MARGIN := 1.05   # a shifted launch may cost this much more than the planned one (if the tanks hold it)


## If the route would pass through the sphere of influence of a body on the way (not the origin, the target or what
## they orbit): first the departure moves a few days earlier or later (the nearest time that clears the body), as long
## as the ship can still get there with the propellant it has. If that does not work, the launch is postponed to a
## later window until the way is clear. (Slingshots will be done on purpose later.)
func _postpone_for_route(make_plan: Callable, result: Dictionary) -> Dictionary:
	if result.has("error") or GameState.ship_in_transit():
		return result
	var parked := GameState.parked_leg()
	var conflict := GameState.route_conflict(result, parked)
	if conflict.is_empty():
		return result
	var body_name := str(GameState.bodies[str(conflict["body"])]["name"])
	var original_departure := float(result["t_dep"])
	var turn := GameState.half_turn_days()
	var limit := maxf(GameState.dv_left_kms(), (float(result["dv_departure"]) + float(result["dv_arrival"])) * ROUTE_SHIFT_DV_MARGIN)
	var steps := int(ROUTE_SHIFT_MAX_DAYS / ROUTE_SHIFT_STEP_DAYS)
	# Test line: why the tries failed (remove when the shift is confirmed to work).
	var tried := 0
	var no_plan := 0
	var other_time := 0
	var too_soon := 0
	var too_costly := 0
	var blocked := 0
	var full_failed := 0
	var first_error := ""
	var cheapest := 1.0e9
	for k in range(1, steps + 1):
		for direction in [1.0, -1.0]:
			var t := original_departure + float(direction) * float(k) * ROUTE_SHIFT_STEP_DAYS
			tried += 1
			var quick: Dictionary = make_plan.call(t, t, true)
			if quick.has("error"):
				no_plan += 1
				first_error = str(quick["error"]) if first_error == "" else first_error
				continue
			if absf(float(quick["t_dep"]) - t) > 1.0e-6:
				other_time += 1
				continue
			if t < time_jd + MIN_LAUNCH_DELAY_DAYS + turn + 0.5 * GameState.burn_days(float(quick["dv_departure"])):
				too_soon += 1
				continue   # too soon: the ship needs time to turn and for the burn
			var cost := float(quick["dv_departure"]) + float(quick["dv_arrival"])
			cheapest = minf(cheapest, cost)
			if cost > limit:
				too_costly += 1
				continue
			if not GameState.route_conflict(quick, parked).is_empty():
				blocked += 1
				continue
			var shifted: Dictionary = make_plan.call(t, t, false)
			if shifted.has("error") or not GameState.route_conflict(shifted, parked).is_empty():
				full_failed += 1
				continue
			shifted["route_note"] = "Optimal launch window not possible. Launch moved %+.1f days until %s is out of the way." % [
					t - original_departure, body_name]
			return shifted
	var step := 1.0
	for _attempt in 25:
		var later: Dictionary = make_plan.call(float(result["t_dep"]) + step, -1.0, false)
		if later.has("error"):
			break
		result = later
		conflict = GameState.route_conflict(result, parked)
		if conflict.is_empty():
			break
		step *= 1.4
	var shift_report := " [Route shift test: tried %d, no plan %d (%s), other time %d, too soon %d, too costly %d (cheapest %.2f km/s, limit %.2f), still blocked %d, full plan failed %d]" % [
			tried, no_plan, first_error, other_time, too_soon, too_costly, cheapest, limit, blocked, full_failed]
	if conflict.is_empty():
		result["route_note"] = "Launch postponed by %.1f days: the route would pass through the sphere of influence of %s.%s" % [
				float(result["t_dep"]) - original_departure, body_name, shift_report]
	else:
		result["route_note"] = "Warning: the route passes through the sphere of influence of %s." % str(GameState.bodies[str(conflict["body"])]["name"])
	return result


func _on_plan() -> void:
	if not plan.is_empty() and not plan["committed"]:
		_cancel_plan()
		return
	# A new orbit around the body the ship is at starts from the current orbit, not from an earlier choice.
	var here := GameState.ship_body() if GameState.ship_body() != "" else GameState.ship_frame()
	if _selected_target_id() == here and not GameState.ship_in_transit():
		GameState.target_orbits.erase(here)
	_make_plan(false)
	if not plan.is_empty():
		last_target = _frame_id()
		_start_zoom(last_target, false)   # the planner always starts from the automatic view


## Cancel: forgets the orbit chosen for this destination and closes the planner. A course change in flight
## goes back to showing the course the ship is following.
func _cancel_plan() -> void:
	GameState.target_orbits.erase(str(plan["target_id"]))
	if not GameState.saved_plan.is_empty():
		_drop_draft(true)
		return
	plan = {}
	var parked := GameState.parked_leg()
	if not parked.is_empty():
		legs = [parked]
	message = ""


## Plans the next departure with the player's target orbit for the chosen destination. With keep_aero_off an
## earlier decision to switch aerobraking off is kept.
func _make_plan(keep_aero_off: bool) -> void:
	var target_id := _selected_target_id()
	var aero_was_off: bool = keep_aero_off and not plan.is_empty() and not bool(plan.get("aero", {}).get("enabled", false))
	var result: Dictionary
	if GameState.ship_in_transit():
		# A course change: the plan the ship is following stays saved until the new one is launched.
		if GameState.saved_plan.is_empty() and not plan.is_empty() and plan["committed"]:
			GameState.saved_plan = plan
		result = _plan_with_delay(func(start: float, _fixed: float, _quick: bool) -> Dictionary:
			return CourseChange.make_plan(target_id, start, GameState.target_orbits.get(target_id, {})))
	else:
		var parked := GameState.parked_leg()
		if parked.is_empty():
			return
		legs = [parked]
		result = _plan_with_delay(func(start: float, fixed: float, quick: bool) -> Dictionary:
			return MissionPlanner.make_plan(str(parked["parent"]), parked["segment"], target_id,
					start, GameState.target_orbits.get(target_id, {}), fixed, quick))
	paused = true
	if result.has("error"):
		plan = GameState.saved_plan if not GameState.saved_plan.is_empty() else {}
		GameState.saved_plan = {}
		message = str(result["error"])
	else:
		plan = result
		message = str(result.get("route_note", ""))
		if aero_was_off and plan["aero"]["available"]:
			AeroBraking.apply(plan, false, int(plan["aero"]["n"]), float(plan["aero"]["h_km"]))
		_sync_aero()
		_sync_orbit_control()


## The player changed the target orbit: remember it for this destination and plan again.
func _on_target_orbit_changed(rp_alt_km: float, ra_alt_km: float, offset_deg: float) -> void:
	if plan.is_empty() or plan["committed"]:
		return
	GameState.target_orbits[_selected_target_id()] = {"rp_alt_km": rp_alt_km, "ra_alt_km": ra_alt_km, "offset_deg": offset_deg}
	_make_plan(true)


func _sync_orbit_control() -> void:
	if plan.is_empty():
		return
	var target: Dictionary = bodies[plan["target_id"]]
	var orbit: Dictionary = plan["target_orbit"]
	orbit_control.setup(float(target["radius_km"]), GameState.max_orbit_altitude_km(str(plan["target_id"])))
	orbit_control.set_orbit(float(orbit["rp_alt_km"]), float(orbit["ra_alt_km"]), float(orbit["offset_deg"]))


## Launches; if the plan will end badly (crash, burn-up, too slow, escape) the player must confirm first.
func _on_launch() -> void:
	_confirm_then(_do_launch)


func _confirm_then(action: Callable) -> void:
	if plan.is_empty():
		return
	if plan["committed"] or str(plan.get("outcome", "ok")) == "ok":
		action.call()
		return
	for connection in launch_dialog.confirmed.get_connections():
		launch_dialog.confirmed.disconnect(connection["callable"])
	launch_dialog.dialog_text = "%s\n\nLaunch anyway?" % str(plan["outcome_text"])
	launch_dialog.confirmed.connect(action)
	# Size the popup to the window: wrapped text, never wider than the screen.
	var window_size := get_viewport().get_visible_rect().size
	var width := int(minf(520.0, window_size.x - 40.0))
	launch_dialog.min_size = Vector2i(width, 0)
	launch_dialog.size = Vector2i(width, 0)
	launch_dialog.popup_centered(Vector2i(width, 0))


## Stops a launch before the departure burn. The plan stays as it is, the launch cost is refunded, and the
## planner controls come back, so the player can change what they want and launch again. For a course change
## the ship goes back to the plan it was following.
func _on_abort() -> void:
	if plan.is_empty() or not plan["committed"] or plan["departure_done"]:
		return
	plan["committed"] = false
	paused = true
	warp_index = 0
	if plan.get("midflight", false):
		legs = plan["legs_before"]
		GameState.saved_plan = plan["replaces"]
	else:
		GameState.budget_eur += GameState.mission_cost_eur
		legs = [legs[0]]
	_sync_aero()
	_sync_orbit_control()
	message = "Launch aborted. The plan is unchanged: change what you like and press Launch again."


func _do_launch() -> void:
	if plan.is_empty():
		return
	var transfer_leg := GameState.transfer_leg_for_plan(plan, GameState.parked_leg())
	GameState.set_morph_times(plan, transfer_leg)
	plan["committed"] = true
	if plan.get("midflight", false):
		# A course change: the flight so far stays, the old plan's later legs are replaced. No launch cost.
		plan["legs_before"] = legs.duplicate()
		plan["replaces"] = GameState.saved_plan
		GameState.saved_plan = {}
		var kept: Array = []
		for leg in legs:
			if float(leg["t_start"]) < float(plan["t_dep"]):
				kept.append(leg)
		legs = kept
		legs.append(transfer_leg)
	else:
		GameState.budget_eur -= GameState.mission_cost_eur
		legs = [legs[0], transfer_leg]
	legs.append_array(plan["capture_legs"])


## Launches (commits the plan) if that has not happened yet, jumps to just before the departure burn
## and resumes time in real time.
func _on_skip() -> void:
	if plan.is_empty():
		return
	if not plan["committed"]:
		_confirm_then(func() -> void:
			_do_launch()
			_skip_to_departure())
		return
	_skip_to_departure()


func _skip_to_departure() -> void:
	var target_jd := float(plan["t_dep"]) - SKIP_LEAD_DAYS
	# Never skip past the start of the ship's turn for the first burn: stop a few seconds before it.
	for window: Dictionary in GameState.manoeuvre_windows():
		if float(window["t1"]) > time_jd:
			target_jd = minf(target_jd, float(window["t0"]) - float(window["lead"]) - 5.0 / 86400.0)
			break
	time_jd = maxf(time_jd, target_jd)
	paused = false
	warp_index = 0


func _on_refuel() -> void:
	var amount := GameState.refuel()
	message = "Refuelled %s kg." % GameState.thousands(amount) if amount > 0.0 else "Nothing to refuel."


## Copies the plan's aerobraking settings to the controls.
func _sync_aero() -> void:
	syncing_aero = true
	var aero: Dictionary = plan.get("aero", {})
	if aero.get("available", false):
		var enabled: bool = aero["enabled"]
		aero_check.set_pressed_no_signal(enabled)
		passes_slider.set_value_no_signal(float(aero["n"]))
		altitude_slider.min_value = float(aero["band_lo"])
		altitude_slider.max_value = maxf(float(aero["band_hi"]), float(aero["band_lo"]) + 0.1)
		altitude_slider.set_value_no_signal(float(aero["h_km"]))
		altitude_spin.min_value = float(aero["h_min_km"])
		altitude_spin.max_value = float(aero["h_max_km"])
		altitude_spin.set_value_no_signal(float(aero["h_km"]))
		passes_label.text = "Passes: %d" % int(aero["n"])
		# Without aerobraking the passes and the altitude do not apply: grey them out.
		passes_slider.editable = enabled
		altitude_slider.editable = enabled
		altitude_spin.editable = enabled
		altitude_minus.disabled = not enabled
		altitude_plus.disabled = not enabled
		passes_label.modulate = Color(1, 1, 1, 1.0 if enabled else 0.4)
		altitude_label.modulate = passes_label.modulate
	syncing_aero = false


func _nudge_altitude(delta_km: float) -> void:
	_apply_aero(aero_check.button_pressed, int(passes_slider.value), altitude_spin.value + delta_km, true)


func _apply_aero(enabled: bool, passes: int, altitude_km: float, recenter := false) -> void:
	if plan.is_empty() or plan["committed"]:
		return
	AeroBraking.apply(plan, enabled, passes, clampf(altitude_km, float(plan["aero"]["h_min_km"]), float(plan["aero"]["h_max_km"])), recenter)
	_sync_aero()


## A new number of passes: find the periapsis altitude that gives the target orbit with that many passes.
func _on_passes_changed() -> void:
	if plan.is_empty() or plan["committed"] or not plan["aero"]["available"]:
		return
	var n := int(passes_slider.value)
	var h := AeroBraking.find_altitude(plan["aero"]["ctx"], n, AeroBraking.SEARCH_DT)
	if h < 0.0:
		message = "%d passes cannot slow the ship enough, even at the lowest periapsis." % n
		h = float(plan["aero"]["h_min_km"])
	_apply_aero(true, n, h, true)


## Back to the planner's suggestion.
func _on_aero_auto() -> void:
	if plan.is_empty() or plan["committed"] or not plan["aero"]["available"]:
		return
	var suggestion := AeroBraking.suggest(plan["aero"]["ctx"])
	if suggestion.is_empty():
		message = "The planner has no safe aerobraking suggestion for this shield."
		_apply_aero(false, int(passes_slider.value), altitude_slider.value)
	else:
		_apply_aero(true, int(suggestion["n"]), float(suggestion["h_km"]), true)


func _on_buy() -> void:
	var amount := GameState.buy_propellant()
	message = "Bought %s kg of propellant for %s EUR." % [GameState.thousands(amount),
			GameState.thousands(amount * GameState.propellant_price_eur_per_kg)] if amount > 0.0 else "Nothing to buy."


func _on_deploy() -> void:
	message = GameState.deploy_kit()


func _on_reset() -> void:
	GameState.reset_mission()
	_fill_destinations("moon")


# ---------------------------------------------------------------- state helpers

## True from the departure burn until the arrival burn.
func _in_transit() -> bool:
	return GameState.ship_in_transit()


func _plan_dv_total() -> float:
	return float(plan["dv_departure"]) + float(plan["dv_arrival"])


func _body_rel(id: String, jd: float) -> Vector2:
	return GameState.body_rel(id, jd)


func _body_abs(id: String, jd: float) -> Vector2:
	return GameState.body_abs(id, jd)


func _leg_index_at(jd: float) -> int:
	return GameState.leg_index_at(jd)


func _ship_abs(jd: float) -> Vector2:
	return GameState.ship_abs(jd)


func _frame_id() -> String:
	var index := _leg_index_at(time_jd)
	var parent_id := str(legs[index]["parent"])
	# Before departure show the system the transfer happens in (for example the Sun for a planet transfer).
	if index == 0 and not plan.is_empty() and plan["frame"] != parent_id:
		return str(plan["frame"])
	return auto_frame if auto_frame != "" else parent_id


## Chooses the body whose view the "auto" setting shows: the smallest view that still contains the ship. A view
## is entered when the ship is inside the distance it shows at the edge of a portrait screen, and left only
## when the ship is VIEW_HYSTERESIS times further out (so it does not flicker at the border).
func _update_auto_frame() -> void:
	var best := GameState.smallest_view(time_jd)
	var best_radius := GameState.view_radius_km(best, time_jd)
	if auto_frame != "" and bodies.has(auto_frame) and best != auto_frame:
		var current_radius := GameState.view_radius_km(auto_frame, time_jd)
		var still_inside := GameState.ship_rel(auto_frame, time_jd).length() <= current_radius * VIEW_HYSTERESIS
		# Outside the context (the highest altitude) of the body the view goes to the next larger body at once.
		if GameState.ship_rel(auto_frame, time_jd).length() > GameState.context_radius_km(auto_frame) * GameState.CONTEXT_HYSTERESIS:
			still_inside = false
		if still_inside and best_radius >= current_radius:
			return   # keep the view: the ship has just left it, but not far enough to switch out
	auto_frame = best


# ---------------------------------------------------------------- time and text

func _process(delta: float) -> void:
	GameState.advance(delta)
	if not GameState.lost_event.is_empty() and not is_instance_valid(lost_overlay):
		var event: Dictionary = GameState.lost_event
		GameState.lost_event = {}
		lost_overlay = ShipLostOverlay.new()
		add_child(lost_overlay)
		lost_overlay.play(str(event["text"]), bool(event["burn"]))
	_update_auto_frame()
	_update_context_zoom()
	_update_camera(delta)
	if picker_origin != _picker_key():
		_fill_destinations(_selected_target_id())
	_update_ui()
	queue_redraw()


## When the ship gets into another context (it leaves the highest altitude of a body, or enters the space of a
## smaller one) the view goes to the view the ship needs now, also if the camera was moved by hand (B-032).
func _update_context_zoom() -> void:
	var context := GameState.ship_context_id
	if context == last_context:
		return
	var first := last_context == ""
	last_context = context
	if first or cam_body == "":
		return
	last_target = _frame_id()
	_start_zoom(last_target, false)


func _update_ui() -> void:
	var in_transit := _in_transit()
	var burn_pending: bool = not plan.is_empty() and plan["committed"] and not plan["departure_done"]
	plan_button.disabled = destination_ids.is_empty() or burn_pending
	plan_button.text = "Cancel" if not plan.is_empty() and not plan["committed"] else "Plan"
	target_picker.disabled = destination_ids.is_empty() or burn_pending
	keep_button.visible = not GameState.saved_plan.is_empty()
	var draft_bad: bool = not plan.is_empty() and not plan["committed"] and str(plan.get("outcome", "ok")) != "ok"
	var warnings: PackedStringArray = []
	if draft_bad:
		warnings.append(str(plan["outcome_text"]))
	if not plan.is_empty() and not plan["committed"] and str(plan.get("warning", "")) != "":
		warnings.append(str(plan["warning"]))
	warning_label.text = "Warning: " + "\nWarning: ".join(warnings) if not warnings.is_empty() else ""
	warning_label.visible = not warnings.is_empty()
	var affordable := not plan.is_empty() and _plan_dv_total() <= GameState.dv_left_kms() + 0.00001
	var window_open := not plan.is_empty() and time_jd < float(plan["t_dep"]) + LATE_LAUNCH_DAYS
	var funded: bool = GameState.budget_eur >= GameState.mission_cost_eur or (not plan.is_empty() and plan.get("midflight", false))
	launch_button.disabled = plan.is_empty() or plan["committed"] or not affordable or not window_open or not funded
	skip_button.disabled = plan.is_empty() or not window_open or not affordable or (not funded and not plan["committed"])
	abort_button.visible = not plan.is_empty() and plan["committed"] and not plan["departure_done"]
	skip_button.text = "Skip to Departure" if not plan.is_empty() and plan["committed"] else "Skip to Departure & Launch"
	var ship_body := GameState.ship_body()
	var plant: Dictionary = GameState.facility_of_kind(ship_body, "propellant_plant") if ship_body != "" else {}
	refuel_button.visible = not plant.is_empty()
	refuel_button.disabled = float(plant.get("stock_kg", 0.0)) <= 0.0 \
			or GameState.ship_fuel_kg >= GameState.ship_fuel_capacity_kg - 0.001
	var at_yard := ship_body != "" and not GameState.facility_of_kind(ship_body, "shipyard").is_empty()
	buy_button.visible = at_yard
	buy_button.disabled = GameState.ship_fuel_kg >= GameState.ship_fuel_capacity_kg - 0.001 or GameState.budget_eur <= 0.0
	for type_id in kit_buttons:
		kit_buttons[type_id].visible = at_yard
		kit_buttons[type_id].disabled = GameState.kit_load_problem(type_id) != ""
	deploy_button.visible = GameState.deployable_type() != ""
	var frame_id := _frame_id()
	planner_row.visible = GameState.planner_available(frame_id)
	ops_row.visible = true
	aero_row.visible = planner_row.visible and not plan.is_empty() and not plan["committed"] \
			and bool(plan.get("aero", {}).get("available", false))
	orbit_row.visible = planner_row.visible and not plan.is_empty() and not plan["committed"]
	shield_button.visible = at_yard and GameState.shield_used_mj_m2 > 0.0
	shield_button.disabled = GameState.shield_replace_problem() != ""
	bar.set_design_visible(GameState.design_available(frame_id))
	bar.refresh()
	info_label.text = _info_bbcode(_info_text())


func _span_text(days: float) -> String:
	if absf(days) < 2.0:
		return "%.1f h" % (days * 24.0)
	return "%.1f days" % days


func _fuel_text() -> String:
	return "%s kg (%.2f km/s) of %s kg (%.2f km/s)" % [
			GameState.thousands(GameState.ship_fuel_kg), GameState.dv_left_kms(),
			GameState.thousands(GameState.ship_fuel_capacity_kg),
			GameState.dv_for_fuel(GameState.ship_fuel_capacity_kg)]


## A heat load (MJ/m2) as a share of the full capacity of the heat shield.
func _heat_share_text(heat: float) -> String:
	var capacity := AeroBraking.shield_capacity_mj_m2(GameState.ship_shield_cm)
	if capacity <= 0.0:
		return "%.0f MJ/m2 (no heat shield)" % heat
	return "%.0f%% of the shield capacity" % (100.0 * heat / capacity)


func _aero_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	var aero: Dictionary = plan.get("aero", {})
	if not aero.get("available", false):
		if aero.get("message", "") != "":
			lines.append(str(aero["message"]))
	elif not aero["enabled"]:
		lines.append("Aerobraking off: propulsive capture. %s" % aero.get("message", ""))
	elif aero["outcome"] != "ok":
		lines.append("Aerobraking: %d passes at %.1f km. Heat %s" % [int(aero["n"]), float(aero["h_km"]), _heat_share_text(float(aero["heat"]))])
	else:
		lines.append("Aerobraking: %d passes at %.1f km, %s in total, final burns %.0f m/s" % [
				int(aero["n"]), float(aero["h_km"]), _span_text(float(aero["days"])), float(aero["final_dv"]) * 1000.0])
		lines.append("Heat %s | peak %.1f g | peak heating %.1f MW/m2" % [
				_heat_share_text(float(aero["heat"])), float(aero["peak_g"]), float(aero["peak_flux"])])
	if aero.get("enabled", false) and aero.has("shield_after"):
		# Below the reserve the planner keeps (20%), the line has the colour of the warnings.
		var low_shield: bool = float(aero["shield_after"]) < 1.0 - AeroBraking.HEAT_MARGIN
		lines.append((WARNING_MARK if low_shield else "") + "Heat shield capacity: %.0f%% now, %.0f%% after the passes" % [
				float(aero["shield_before"]) * 100.0, float(aero["shield_after"]) * 100.0])
		if aero["outcome"] == "ok" and str(plan.get("outcome", "ok")) == "ok":
			var damage := GameState.aerobraking_damage(float(aero["heat"]), float(aero["peak_g"]))
			var damage_text := " Expected damage: health %.0f%% -> %.0f%%." % [GameState.ship_health * 100.0,
					maxf(GameState.ship_health - damage, 0.0) * 100.0]
			if float(aero["shield_after"]) <= 0.0 or float(aero["heat"]) > float(aero["shield_before"]) * AeroBraking.shield_capacity_mj_m2(GameState.ship_shield_cm):
				lines.append("Warning: the heat shield will be used up and the ship will be damaged." + damage_text)
			elif float(aero["peak_g"]) > AeroBraking.G_LIMIT:
				lines.append("Warning: the deceleration is above the limit and the ship will be damaged." + damage_text)
			elif float(aero["heat"]) > AeroBraking.HEAT_MARGIN * float(aero["shield_before"]) * AeroBraking.shield_capacity_mj_m2(GameState.ship_shield_cm):
				lines.append("Warning: the heat shield will have only %.0f%% of its capacity left, less than the %.0f%% reserve the planner keeps." % [
						float(aero["shield_after"]) * 100.0, (1.0 - AeroBraking.HEAT_MARGIN) * 100.0])
	if aero.get("burn_assist", false) and aero["outcome"] == "ok":
		lines.append("The passes alone leave the ship too fast to be captured: a burn right after the last pass finishes the capture.")
	if str(plan.get("outcome", "ok")) != "ok":
		lines.append("Warning: " + str(plan["outcome_text"]))
	if str(plan.get("warning", "")) != "":
		lines.append("Warning: " + str(plan["warning"]))
	return lines


const WARNING_MARK := "\u0001"   # at the start of an info line: draw the line in the colour of the warnings

## The info text as bbcode: brackets of the text are escaped, lines that start with WARNING_MARK are coloured.
func _info_bbcode(text: String) -> String:
	var out: PackedStringArray = []
	for line in text.split("\n"):
		var colored: bool = line.begins_with(WARNING_MARK)
		var shown: String = line.trim_prefix(WARNING_MARK).replace("[", "[lb]")
		out.append("[color=#ff8c4d]%s[/color]" % shown if colored else shown)
	return "\n".join(out)


func _info_text() -> String:
	var lines: PackedStringArray = []
	lines.append("%s: %s" % [GameState.ship_name, legs[_leg_index_at(time_jd)]["label"]])
	lines.append("Fuel: %s" % _fuel_text())
	if AeroBraking.shield_capacity_mj_m2(GameState.ship_shield_cm) <= 0.0:
		lines.append("No heat shield | Health: %.0f%%" % (GameState.ship_health * 100.0))
	else:
		lines.append("Heat shield: %.0f%% used, %.0f%% left | Health: %.0f%%" % [GameState.shield_used_share() * 100.0,
				(1.0 - GameState.shield_used_share()) * 100.0, GameState.ship_health * 100.0])
	lines.append("Budget: %s EUR" % GameState.thousands(GameState.budget_eur))
	if GameState.stop_reason != "" and Time.get_ticks_msec() - GameState.stop_ms < 20000:   # (a test line: why the warp dropped)
		lines.append("Warp stopped: %s" % GameState.stop_reason)
	var turn_shown := retro_shown if (retro_shown > 0.001 and retro_shown < 0.999) else fixed_shown
	if turn_shown > 0.001 and turn_shown < 0.999:   # (a test line: shown while the ship turns)
		lines.append("Turning: %.0f%% of a half turn | rate %.1f deg/s, a half turn takes %.1f s" % [
				100.0 * turn_shown, GameState.rotation_rate_deg_s(), GameState.half_turn_days() * 86400.0])
	if not GameState.cargo.is_empty():
		var names: PackedStringArray = []
		for type_id in GameState.cargo:
			names.append(str(GameState.facility_types[type_id]["name"]))
		lines.append("Cargo (%s of %s kg): %s" % [GameState.thousands(GameState.cargo_mass_kg()),
				GameState.thousands(GameState.ship_payload_kg), ", ".join(names)])
	for id in GameState.facilities:
		var facility: Dictionary = GameState.facilities[id]
		if facility["kind"] != "propellant_plant":
			lines.append(str(facility["name"]))
			continue
		lines.append("%s: %s kg of %s kg (+%s kg/day)" % [facility["name"], GameState.thousands(float(facility["stock_kg"])),
				GameState.thousands(float(facility["storage_capacity_kg"])), GameState.thousands(GameState.facility_output_per_day(facility))])
	if plan.is_empty():
		if message != "":
			lines.append(message)
		elif _in_transit():
			lines.append("In transit.")
		elif planner_row.visible:
			lines.append("Choose a destination and press Plan to find the next launch window.")
		return "\n".join(lines)
	if plan.get("orbit_change", false):
		lines.append("Plan: new orbit around %s" % plan["target_name"])
	elif plan.get("midflight", false):
		lines.append("Plan: course change to %s" % plan["target_name"])
	else:
		lines.append("Plan: %s to %s" % [bodies[plan["origin_id"]]["name"], plan["target_name"]])
	lines.append("Departure: %s (in %s)" % [GameState.date_text(float(plan["t_dep"])), _span_text(float(plan["t_dep"]) - time_jd)])
	lines.append("Arrival: %s (flight %s)" % [GameState.date_text(float(plan["t_arr"])), _span_text(float(plan["flight_days"]))])
	if not plan["committed"] and not plan.get("midflight", false):
		lines.append("Launch cost: %s EUR" % GameState.thousands(GameState.mission_cost_eur))
	lines.append("Burns: departure %.2f + capture %.2f = %.2f km/s" % [
			float(plan["dv_departure"]), float(plan["dv_arrival"]), _plan_dv_total()])
	if not plan.get("orbit_change", false) and not OrbitControl.is_circular(float(plan["rp_t"]), float(plan["ra_t"])):
		var turn_deg := AeroBraking.axis_turn_deg(plan)
		var axis_line := "Orbit axis: %.0f deg (solar system frame), arrival aimed at %.0f deg" % [
				fposmod(AeroBraking._axis_deg(plan), 360.0), fposmod(AeroBraking._arrival_axis(plan), 360.0)]
		if turn_deg > 0.5:
			axis_line += "; turning the axis by %.0f deg costs %.0f m/s (included in the capture burn)." % [turn_deg, AeroBraking.axis_turn_dv(plan) * 1000.0]
		else:
			axis_line += "; no turn needed."
		lines.append(axis_line)
	if float(plan.get("dv_circularize", 0.0)) > 0.0:
		lines.append("The periapsis of the parking orbit points the wrong way for this departure: circularising first (%.0f m/s, included in the departure burn)." % (float(plan["dv_circularize"]) * 1000.0))
	lines.append_array(_aero_lines())
	if message != "":
		lines.append(message)
	if not plan["committed"] and _plan_dv_total() > GameState.dv_left_kms():
		lines.append("Not enough fuel for this mission. Refuel, or build a stronger ship on the ship design screen.")
	elif plan["committed"]:
		lines.append(("Mission launched (the departure burn can still be aborted)." if not plan["departure_done"] else "Mission launched.") if time_jd < float(plan["t_arr"]) else "Arrived at %s." % plan["target_name"])
	elif time_jd >= float(plan["t_dep"]) + LATE_LAUNCH_DAYS:
		lines.append("The launch window has passed. Press Plan again.")
	else:
		lines.append("Ready: press Launch and resume time, or press Skip to Departure & Launch.")
	return "\n".join(lines)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	sprite_requests.clear()
	ship_request = {}
	_draw_map()
	_apply_sprites()
	_apply_ship()


func _draw_map() -> void:
	if cam_body == "":
		return
	var centre := _view_centre()
	var half_extent := minf(size.x * 0.5, size.y * 0.38)
	# The scenes of the camera's body, of the body it orbits and of its children are drawn together; each fades
	# in when its view gets big enough to see and its orbit lines fade out when it is far bigger than the screen.
	var scene_ids: Array = []
	var parent: Variant = bodies[cam_body]["parent"]
	if parent != null:
		scene_ids.append(str(parent))
	scene_ids.append(cam_body)
	scene_ids.append_array(children[cam_body])
	# A body can appear in two scenes (as a child of one and as the centre of the other). Its marker (disc, name, sprite)
	# is drawn only once, by the scene closest to the camera that is visible, with the larger of the opacities.
	var scene_alphas: Array = []
	marker_owner.clear()
	marker_owner_alpha.clear()
	for n in scene_ids.size():
		var id := str(scene_ids[n])
		var radius_px := GameState.view_radius_km(id, time_jd) * cam_scale
		var visible_enough := smoothstep(16.0, 60.0, radius_px)
		var too_big := 1.0 - smoothstep(1.6 * half_extent, 5.0 * half_extent, radius_px)
		scene_alphas.append([visible_enough * too_big, visible_enough])
		if visible_enough > 0.01:
			var rank := 0 if id == cam_body else 1
			for body_id: String in [id] + (children[id] as Array):
				marker_owner_alpha[body_id] = maxf(float(marker_owner_alpha.get(body_id, 0.0)), visible_enough)
				if not marker_owner.has(body_id) or rank < int(marker_owner[body_id][1]):
					marker_owner[body_id] = [id, rank]
	for n in scene_ids.size():
		var id := str(scene_ids[n])
		line_alpha = float(scene_alphas[n][0])
		marker_alpha = float(scene_alphas[n][1])
		scene_rank = 0 if id == cam_body else 1
		if line_alpha > 0.01 or marker_alpha > 0.01:
			current_scene = id
			_draw_scene(id, _screen_of(id), cam_scale)
	line_alpha = 1.0
	marker_alpha = 1.0
	if GameState.ship_lost:
		return   # the ship and its course are gone
	_draw_ship_orbit(half_extent)
	var ship_km := GameState.ship_rel(cam_body, time_jd)
	var p := _to_screen(ship_km - cam_offset, centre, cam_scale)
	# The ship points the way it flies (on the screen).
	# (measured along the one leg the ship is on, so that the direction does not jump where the leg changes)
	var leg_now: Dictionary = GameState.legs[GameState.leg_index_at(time_jd)]
	var ahead := GameState.leg_rel_with_offsets(leg_now, cam_body, time_jd + SHIP_VELOCITY_STEP_DAYS) \
			- GameState.leg_rel_with_offsets(leg_now, cam_body, time_jd - SHIP_VELOCITY_STEP_DAYS)
	if ahead.length_squared() > 0.0:
		ship_angle = Vector2(ahead.x, -ahead.y).angle()
	var to_sun := GameState.body_rel_to(cam_body, "sun", time_jd) - ship_km if cam_body != "sun" else -ship_km
	# The sprite replaces the triangle once it would cover at most a quarter of the body's diameter (smoothly).
	var orbited := str(GameState.legs[GameState.leg_index_at(time_jd)]["parent"])
	var body_px := float(bodies[orbited]["radius_km"]) * cam_scale
	var full_px := SHIP_LENGTH_PX / (2.0 * SHIP_FULL_BODY_FRACTION)   # body radius at which the sprite covers the fraction
	# Zooming in: the sprite fades in completely over the first half of the range, and only then the triangle fades
	# out over the second half (zooming out is the reverse), so the ship is never see-through.
	var fade_lo := full_px * SHIP_FADE_FROM
	var fade_mid := 0.5 * (fade_lo + full_px)
	var sprite_a := smoothstep(fade_lo, fade_mid, body_px)
	var triangle_a := 1.0 - smoothstep(fade_mid, full_px, body_px)
	if SpriteLibrary.entry(SHIP_SPRITE).is_empty():
		sprite_a = 0.0
		triangle_a = 1.0
	var attitude := GameState.attitude_at(time_jd)
	var retro := _turn_towards(float(attitude["retro"]))
	var heading := ship_angle + PI * retro   # nose first, turning to tail first for retrograde burns and aerobraking
	var fixed_weight := _turn_towards(float(attitude["fixed"]), true)   # (the same turning rate as for every other turn)
	var burn_now := int(attitude["burn"])
	if fixed_weight > 0.0:
		# The axis-turning burn: the ship turns from its course to a heading fixed in space and back again.
		heading = lerp_angle(heading, float(attitude["fixed_angle"]), fixed_weight)
		if burn_now == 2 and fixed_weight < 0.999:
			burn_now = 0   # (the engine only burns once the ship points the right way)
	ship_request = {"pos": p, "angle": heading, "sun": Vector2(to_sun.x, -to_sun.y).rotated(-heading),
			"burn": burn_now, "retro": retro, "heat": GameState.heat_at(time_jd), "alpha": sprite_a, "light": _ship_light(orbited)}
	if triangle_a > 0.0:
		var triangle := Color.WHITE.lerp(Color(1.0, 0.5, 0.15), float(ship_request["heat"]))   # glows orange while it heats up
		triangle.a = triangle_a
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 5), p + Vector2(-6, 5)]), triangle)
	draw_string(ThemeDB.fallback_font, p + Vector2(10, 22), GameState.ship_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


## The orbit the ship is in (green); while a burn or an aerobraking pass changes it, the orbit morphs. It is always
## drawn, whatever the scene it belongs to shows, unless it is so small that it cannot be told from the body, or so
## much bigger than the screen that a line through its points would be wrong.
func _draw_ship_orbit(half_extent: float) -> void:
	var leg: Dictionary = legs[_leg_index_at(time_jd)]
	var parent_id := str(leg["parent"])
	var segment: Dictionary = leg["segment"]
	var morph := GameState.morph_at(time_jd)
	if not morph.is_empty():
		parent_id = str(morph["parent"])
		segment = morph["segment"]
	var apoapsis := float(segment["semi_major_axis_km"]) * (1.0 + float(segment["eccentricity"]))
	var above_body_px := (apoapsis - float(bodies[parent_id]["radius_km"])) * cam_scale
	if above_body_px * 1.0 < 2.0 or apoapsis * cam_scale > 8.0 * half_extent:
		return
	var origin := _screen_of(parent_id)
	var ring := PackedVector2Array()
	for point in Kepler.orbit_points(segment, 128):
		ring.append(_to_screen(point, origin, cam_scale))
	draw_polyline(ring, Color(0.3, 1.0, 0.4, 0.85 * smoothstep(2.0, 6.0, above_body_px)), 1.5, true)


## The faded colour of an orbit line, and of a marker (a body, its name).
func _fade(colour: Color) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * line_alpha)


func _mfade(colour: Color) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * marker_alpha)


## Draws the view of one body (its children's orbits, the routes and the ship's orbit around it, the bodies):
## centre is where the body is on the screen, px_per_km the scale.
func _draw_scene(frame_id: String, centre: Vector2, px_per_km: float) -> void:
	var kid_ids: Array = children[frame_id]
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		var line := PackedVector2Array()
		for point in Kepler.orbit_points(segment, ORBIT_SAMPLES):
			line.append(_to_screen(point, centre, px_per_km))
		draw_polyline(line, _fade(Color(1, 1, 1, 0.25)), 1.0, true)

	# Planned transfer path, drawn when the transfer happens around the body at the centre of the view.
	if not plan.is_empty() and plan["frame"] == frame_id:
		var path := PackedVector2Array()
		for i in 81:
			var t := float(plan["t_dep"]) + float(plan["flight_days"]) * float(i) / 80.0
			path.append(_to_screen(Kepler.position_at(plan["transfer_segment"], t), centre, px_per_km))
		draw_polyline(path, _fade(Color(0.4, 0.9, 1.0, 0.9)), 1.5, true)
	_draw_local_route(frame_id, centre, px_per_km)
	_draw_body(frame_id, centre, px_per_km)
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		_draw_body(kid_id, _to_screen(Kepler.position_at(segment, time_jd), centre, px_per_km), px_per_km)


## The parts of the planned route that lie inside the local view of a body: the escape from the body the ship
## leaves, the approach to the body it goes to, and the orbits it will have there (aerobraking passes and the
## final orbit). The path is the same one the ship follows (GameState.leg_rel_with_offsets).
func _draw_local_route(frame_id: String, centre: Vector2, px_per_km: float) -> void:
	if plan.is_empty():
		return
	var route_colour := _fade(Color(0.4, 0.9, 1.0, 0.9))
	if str(plan["frame"]) != frame_id:
		var transfer_leg := GameState.plan_transfer_leg(plan)
		if not transfer_leg.is_empty():
			var radius_km := GameState.view_radius_km(frame_id, time_jd)
			if str(transfer_leg.get("from_body", "")) == frame_id:
				draw_polyline(_route_points(transfer_leg, frame_id, float(plan["t_dep"]), 1.0, radius_km, centre, px_per_km), route_colour, 1.5, true)
			if str(transfer_leg.get("to_body", "")) == frame_id:
				draw_polyline(_route_points(transfer_leg, frame_id, float(plan["t_arr"]), -1.0, radius_km, centre, px_per_km), route_colour, 1.5, true)
				if (transfer_leg.get("to_hyp", {}) as Dictionary).has("delta_out"):   # a fly-by: the way out round the body
					draw_polyline(_route_points(transfer_leg, frame_id, float(plan["t_arr"]), 1.0, radius_km, centre, px_per_km, float(plan["t_arr"]) + 60.0), route_colour, 1.5, true)
	var captures: Array = plan.get("capture_legs", [])
	for capture_leg in captures:
		if str(capture_leg["parent"]) != frame_id:
			continue
		var ring := PackedVector2Array()
		for point in Kepler.orbit_points(capture_leg["segment"], 64):
			ring.append(_to_screen(point, centre, px_per_km))
		draw_polyline(ring, _fade(Color(0.4, 0.9, 1.0, 0.7 if capture_leg["kind"] == "orbit" else 0.3)), 1.0, true)


## Points of the route near one end of a transfer: sampled at growing time steps from t_origin (forwards for
## direction 1, backwards for -1) until the path leaves the view.
func _route_points(leg: Dictionary, frame_id: String, t_origin: float, direction: float, radius_km: float,
		centre: Vector2, px_per_km: float, t_last_override := -1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var t_first := float(plan["t_dep"])
	var t_last := float(plan["t_arr"]) if t_last_override < 0.0 else t_last_override
	points.append(_to_screen(GameState.leg_rel_with_offsets(leg, frame_id, t_origin), centre, px_per_km))
	var step_seconds := 60.0
	for _k in 200:
		var t := t_origin + direction * step_seconds / 86400.0
		if t < t_first or t > t_last:
			break
		var rel := GameState.leg_rel_with_offsets(leg, frame_id, t)
		points.append(_to_screen(rel, centre, px_per_km))
		if rel.length() > radius_km * 1.05:
			break
		step_seconds *= 1.12
	return points


func _to_screen(position_km: Vector2, centre: Vector2, px_per_km: float) -> Vector2:
	return centre + Vector2(position_km.x, -position_km.y) * px_per_km


func _draw_body(id: String, screen_position: Vector2, px_per_km: float) -> void:
	if marker_owner.has(id) and str(marker_owner[id][0]) != current_scene:
		return   # another scene draws this body's marker
	if marker_owner_alpha.has(id):
		marker_alpha = float(marker_owner_alpha[id])
	var body: Dictionary = bodies[id]
	var true_radius_px := float(body["radius_km"]) * px_per_km
	var radius_px := maxf(MIN_BODY_RADIUS_PX, true_radius_px)
	var colour := _mfade(Color.html(body["draw_color"]))
	# Big enough to see: the sprite fades in over the coloured disc.
	var sprite_a := _place_body_sprites(id, screen_position, true_radius_px)
	if sprite_a < 1.0:
		draw_circle(screen_position, radius_px, Color(colour.r, colour.g, colour.b, colour.a * (1.0 - sprite_a)))
	if true_radius_px < RING_BELOW_PX:
		draw_arc(screen_position, RING_RADIUS_PX, 0.0, TAU, 32, colour, 1.5, true)
		radius_px = RING_RADIUS_PX
	var facility_count := GameState.facilities_at(id).size()
	for n in facility_count:
		draw_rect(Rect2(screen_position + Vector2(-radius_px - 9.0 - 9.0 * n, -radius_px - 9.0), Vector2(7, 7)), _mfade(Color(1.0, 0.6, 0.2)))
	draw_string(ThemeDB.fallback_font, screen_position + Vector2(radius_px + 4.0, 5.0), body["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _mfade(Color(1, 1, 1, 0.8)))


## Asks for the sprites of a body (and its rings, snow, ...) and returns how opaque they are (0 when it is too small).
func _place_body_sprites(id: String, screen_position: Vector2, true_radius_px: float) -> float:
	var alpha := smoothstep(2.5, 7.0, true_radius_px) * marker_alpha
	if alpha <= 0.0:
		return 0.0
	var key := SpriteLibrary.body_key(id)
	if key == "":
		return 0.0
	var sprite_scale := true_radius_px / SpriteLibrary.DISC_RADIUS_PX
	# Bodies keep their orientation on the screen (tilted planets must not turn with their orbit), so the light
	# comes from the direction of the Sun on the screen.
	var sun_dir := Vector2.RIGHT
	if id != "sun":
		var to_sun := GameState.body_rel_to(id, "sun", time_jd)
		sun_dir = Vector2(to_sun.x, -to_sun.y).normalized()
	var lit := id != "sun"
	_request_sprite(key, key, screen_position, sprite_scale, sun_dir, alpha, lit)
	if id == "earth":
		# Northern winter: snow fades in when the north pole (the top of the sprite) leans away from the Sun.
		var snow := clampf(0.5 - 0.5 * sun_dir.dot(Vector2.UP), 0.0, 1.0)
		_request_sprite("bodies/earth_snow", "bodies/earth_snow", screen_position, sprite_scale, sun_dir, alpha * snow, true)
	for ring_key in ["bodies/%s_rings" % id]:
		if not SpriteLibrary.entry(ring_key).is_empty():
			_request_sprite(ring_key, ring_key, screen_position, sprite_scale, sun_dir, alpha, false)
	return alpha / maxf(marker_alpha, 0.0001)


func _request_sprite(node_key: String, sprite_key: String, screen_position: Vector2, sprite_scale: float, sun_dir: Vector2, alpha: float, lit: bool) -> void:
	if sprite_requests.has(node_key):
		# The same body drawn by two scenes at once: the camera body's own scene has exact positions (the others are
		# millions of pixels away and jitter in 32-bit floats), so its position wins; the opacity is the larger one.
		var earlier: Dictionary = sprite_requests[node_key]
		alpha = maxf(alpha, float(earlier["alpha"]))
		if int(earlier["rank"]) < scene_rank:
			earlier["alpha"] = alpha
			return
	sprite_requests[node_key] = {"sprite": sprite_key, "pos": screen_position, "scale": sprite_scale, "sun": sun_dir, "alpha": alpha, "lit": lit, "rank": scene_rank}


## Shows the requested sprites (creating the nodes the first time) and hides the rest.
func _apply_sprites() -> void:
	if sprite_layer == null:
		sprite_layer = Node2D.new()
		sprite_layer.show_behind_parent = true
		add_child(sprite_layer)
	for node_key: String in sprite_requests:
		var request: Dictionary = sprite_requests[node_key]
		var info := SpriteLibrary.entry(str(request["sprite"]))
		if info.is_empty():
			continue
		var node: Sprite2D = sprite_nodes.get(node_key)
		if node == null:
			node = Sprite2D.new()
			node.centered = false
			node.texture = info["texture"]
			node.offset = -(info["pivot"] as Vector2)
			node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var material := SpriteLibrary.lit_material(info["normal"] as Texture2D)
			if material != null:
				node.set_meta("lit_material", material)
			sprite_layer.add_child(node)
			sprite_nodes[node_key] = node
		node.visible = true
		node.position = request["pos"]
		node.scale = Vector2.ONE * float(request["scale"])
		node.modulate = Color(1, 1, 1, float(request["alpha"]))
		var lit_material: ShaderMaterial = node.get_meta("lit_material", null)
		if bool(request["lit"]) and lit_material != null:
			node.material = lit_material
			lit_material.set_shader_parameter("sun_dir", request["sun"])
		else:
			node.material = null
	for node_key: String in sprite_nodes:
		if not sprite_requests.has(node_key):
			(sprite_nodes[node_key] as Sprite2D).visible = false


## The attitude the ship shows: it moves towards the attitude the plan wants, but never faster than the ship can turn
## (in game time). So when a plan is aborted, or the attitude changes for any other reason, the ship turns round
## in the time a turn takes instead of jumping.
## (fixed_heading: the same rule for the turn to the fixed heading of the axis-turning burn, 0 = pointing along the
## course, 1 = at the burn heading; it has its own state.)
func _turn_towards(wanted: float, fixed_heading := false) -> float:
	var shown := fixed_shown if fixed_heading else retro_shown
	var last_jd := fixed_jd if fixed_heading else retro_jd
	var elapsed_s := (time_jd - last_jd) * 86400.0
	if last_jd < 0.0 or elapsed_s < 0.0:
		shown = wanted   # first frame, or time went backwards
	else:
		shown = move_toward(shown, wanted, GameState.rotation_rate_deg_s() / 180.0 * elapsed_s)
	if fixed_heading:
		fixed_shown = shown
		fixed_jd = time_jd
	else:
		retro_shown = shown
		retro_jd = time_jd
	return shown


## Shows the ship sprite (hull lit by the Sun, glow layer, engine flame while a burn is going on).
func _apply_ship() -> void:
	if ship_layer == null:
		ship_layer = Node2D.new()
		add_child(ship_layer)
	var info := SpriteLibrary.entry(SHIP_SPRITE)
	if info.is_empty() or ship_request.is_empty() or float(ship_request["alpha"]) <= 0.0:
		ship_layer.visible = false
		return
	if ship_node == null:
		var pivot: Vector2 = info["pivot"]
		ship_pivot_x = pivot.x
		ship_length_units = (info["texture"] as Texture2D).get_size().x
		ship_node = Sprite2D.new()
		ship_node.centered = false
		ship_node.texture = info["texture"]
		ship_node.offset = -pivot
		ship_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ship_node.scale = Vector2.ONE * SHIP_LENGTH_PX / (info["texture"] as Texture2D).get_size().x
		var material := SpriteLibrary.lit_material(info["normal"] as Texture2D)
		if material != null:
			material.set_shader_parameter("sun_elevation", 0.56)
			ship_node.material = material
		ship_layer.add_child(ship_node)
		if info["glow"] != null:
			var glow := Sprite2D.new()
			glow.centered = false
			glow.texture = info["glow"]
			glow.offset = -pivot
			glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var add := CanvasItemMaterial.new()
			add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			glow.material = add
			ship_node.add_child(glow)
		var flame_info := SpriteLibrary.entry("effects/flame_vacuum")
		if not flame_info.is_empty():
			ship_flame = Sprite2D.new()
			ship_flame.centered = false
			ship_flame.texture = flame_info["texture"]
			ship_flame.offset = -(flame_info["pivot"] as Vector2)
			ship_flame.position = Vector2(-pivot.x + 12.0, 0.0)   # at the tail of the hull (the flame points left)
			ship_flame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			ship_node.add_child(ship_flame)
		var plasma_info := SpriteLibrary.entry(SHIP_PLASMA)
		if not plasma_info.is_empty():
			ship_plasma = Sprite2D.new()
			ship_plasma.centered = false
			ship_plasma.texture = plasma_info["texture"]
			ship_plasma.offset = -(plasma_info["pivot"] as Vector2)
			ship_plasma.position = Vector2((info["texture"] as Texture2D).get_size().x - pivot.x - 24.0, 0.0)   # the tip of the shock at the nose
			ship_plasma.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var plasma_add := CanvasItemMaterial.new()
			plasma_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			ship_plasma.material = plasma_add
			ship_node.add_child(ship_plasma)
	ship_layer.visible = true
	ship_node.position = ship_request["pos"]
	ship_node.rotation = float(ship_request["angle"])
	ship_node.modulate = Color(1, 1, 1, float(ship_request["alpha"]))
	var light := float(ship_request["light"])
	var lit: ShaderMaterial = ship_node.material as ShaderMaterial
	if lit != null:
		lit.set_shader_parameter("sun_dir", ship_request["sun"])
		lit.set_shader_parameter("sun_strength", 1.15 * light)   # the glow layer stays as bright as it is
		lit.set_shader_parameter("ambient", 0.05 * light)
		lit.set_shader_parameter("heat", float(ship_request["heat"]))
		lit.set_shader_parameter("heat_dir", Vector2.RIGHT.rotated(-PI * float(ship_request["retro"])))   # the way the flow comes, in the hull's own space
	else:
		ship_node.self_modulate = Color(light, light, light, 1.0)
	if ship_plasma != null:
		var heat := float(ship_request["heat"])
		var tail_first := float(ship_request["retro"]) > 0.5
		ship_plasma.rotation = PI if tail_first else 0.0   # the shock is in front: at the tail (the heat shield) when flying tail first
		ship_plasma.position = Vector2(-ship_pivot_x + 24.0, 0.0) if tail_first else Vector2(ship_length_units - ship_pivot_x - 24.0, 0.0)
		ship_plasma.visible = heat > 0.01
		ship_plasma.modulate = Color(1, 1, 1, heat)
		ship_plasma.scale = Vector2.ONE * (1.0 + 0.5 * heat) * Vector2(1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.04), 1.0)
	if ship_flame != null:
		var burn := int(ship_request["burn"])
		var retro_now := float(ship_request["retro"])
		# The flame only burns once the ship has turned the right way round (prograde: nose first, retrograde: tail first).
		ship_flame.visible = (burn == 1 and retro_now < 0.05) or (burn < 0 and retro_now > 0.95) or burn == 2   # (2: the axis-turning burn, at its fixed heading)
		ship_flame.scale = Vector2(1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.03), 1.0)


## How brightly the Sun lights the ship: 1 in daylight, SHIP_SHADOW_LIGHT in the shadow of the body it orbits
## (a cylinder shadow with a soft edge).
func _ship_light(orbited: String) -> float:
	if orbited == "sun":
		return 1.0
	var radius := float(bodies[orbited]["radius_km"])
	var rel := GameState.ship_rel(orbited, time_jd)
	var to_sun := GameState.body_rel_to(orbited, "sun", time_jd).normalized()
	var along := rel.dot(to_sun)
	if along >= 0.0:
		return 1.0
	var off_axis := (rel - to_sun * along).length()
	# The edge gets softer the farther the ship is from the body (not exact, but more comfortable to look at):
	# sharp (2% of the radius) close to the surface, up to 62% of the radius three radii above it.
	var altitude := maxf(rel.length() - radius, 0.0)
	var softness := radius * (0.02 + 0.6 * clampf(altitude / (3.0 * radius), 0.0, 1.0))
	var shadow := smoothstep(-softness, softness, radius - off_axis)
	return lerpf(1.0, SHIP_SHADOW_LIGHT, shadow)
