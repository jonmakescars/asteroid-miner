extends Node2D
## Prototype build step 4: bodies on rails, with time warp.
## Shows one system at a time: the focus body in the centre and its direct children orbiting it,
## scaled automatically so the widest orbit fits the screen. Bodies are drawn as plain circles.
##
## Controls: Tab or tap the top half = next system, Space = pause,
## "+" / "-" or tap the bottom right / bottom left = faster / slower.

const DATA_PATH := "res://data/bodies.json"
const WARP_STEPS := [0.1, 1.0, 10.0, 100.0, 1000.0, 10000.0]  # game days per real second
const MIN_BODY_RADIUS_PX := 3.0
const ORBIT_SAMPLES := 160
const RING_RADIUS_PX := 10.0  # marker ring around bodies that are too small to see

var bodies: Dictionary = {}    # id -> body dictionary from the data file
var children: Dictionary = {}  # id -> array of child ids
var focus_ids: Array = []      # bodies that have children, in file order (Sun first)
var focus_index: int = 0
var warp_index: int = 1
var paused: bool = false
var time_jd: float = 0.0


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = 2.0
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	_add_menu_button()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Cannot read %s (on Android, add *.json to the export filter)." % DATA_PATH)
		set_process(false)
		return
	time_jd = float(parsed["game_start"]["jd"])
	for body in parsed["bodies"]:
		bodies[body["id"]] = body
		children[body["id"]] = []
	for id in bodies:
		var parent_id: Variant = bodies[id]["parent"]
		if parent_id != null:
			children[parent_id].append(id)
	for id in bodies:
		if not children[id].is_empty():
			focus_ids.append(id)


## A small "Menu" button in the top right corner (Escape also works).
func _add_menu_button() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var button := Button.new()
	button.text = "Menu"
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.pressed.connect(_open_menu)
	layer.add_child(button)


func _open_menu() -> void:
	get_tree().change_scene_to_file("res://menu.tscn")


func _process(delta: float) -> void:
	if not paused:
		time_jd += delta * float(WARP_STEPS[warp_index])
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if key and key.pressed and not key.echo:
		match key.keycode:
			KEY_TAB:
				_next_focus()
			KEY_ESCAPE:
				_open_menu()
			KEY_SPACE:
				paused = not paused
			KEY_EQUAL, KEY_KP_ADD, KEY_PERIOD:
				_change_warp(1)
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_COMMA:
				_change_warp(-1)
	elif click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var size := get_viewport_rect().size
		if click.position.y < size.y * 0.5:
			_next_focus()
		elif click.position.x < size.x * 0.5:
			_change_warp(-1)
		else:
			_change_warp(1)


func _next_focus() -> void:
	if not focus_ids.is_empty():
		focus_index = (focus_index + 1) % focus_ids.size()


func _change_warp(step: int) -> void:
	warp_index = clampi(warp_index + step, 0, WARP_STEPS.size() - 1)


func _draw() -> void:
	if focus_ids.is_empty():
		return
	var focus_id: String = focus_ids[focus_index]
	var kid_ids: Array = children[focus_id]
	var centre := get_viewport_rect().size * 0.5

	# Scale so that the widest orbit (at its furthest point) fills 90 % of the shorter half-screen.
	var max_extent := 1.0
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		max_extent = maxf(max_extent, float(segment["semi_major_axis_km"]) * (1.0 + float(segment["eccentricity"])))
	var px_per_km := minf(centre.x, centre.y) * 0.9 / max_extent

	# Orbit lines first, then the bodies on top of them.
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		var line := PackedVector2Array()
		for point in Kepler.orbit_points(segment, ORBIT_SAMPLES):
			line.append(_to_screen(point, centre, px_per_km))
		draw_polyline(line, Color(1, 1, 1, 0.25), 1.0, true)

	_draw_body(focus_id, centre, px_per_km)
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		var position_km := Kepler.position_at(segment, time_jd)
		_draw_body(kid_id, _to_screen(position_km, centre, px_per_km), px_per_km)

	_draw_hud(focus_id)


func _to_screen(position_km: Vector2, centre: Vector2, px_per_km: float) -> Vector2:
	return centre + Vector2(position_km.x, -position_km.y) * px_per_km


func _draw_body(id: String, screen_position: Vector2, px_per_km: float) -> void:
	var body: Dictionary = bodies[id]
	var radius_px := maxf(MIN_BODY_RADIUS_PX, float(body["radius_km"]) * px_per_km)
	var colour := Color.html(body["draw_color"])
	draw_circle(screen_position, radius_px, colour)
	# While the body is too small to see, a ring in its colour marks it. The ring disappears
	# once the true size passes the ring size (later: when zoomed into the planet's sphere of influence).
	if radius_px < RING_RADIUS_PX:
		draw_arc(screen_position, RING_RADIUS_PX, 0.0, TAU, 32, colour, 1.5, true)
		radius_px = RING_RADIUS_PX
	draw_string(ThemeDB.fallback_font, screen_position + Vector2(radius_px + 4.0, 5.0), body["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))


func _draw_hud(focus_id: String) -> void:
	var date_text := Time.get_datetime_string_from_unix_time(int((time_jd - 2440587.5) * 86400.0)).replace("T", " ")
	var warp_text := "paused" if paused else "%s days/s" % str(WARP_STEPS[warp_index])
	var lines := [
		"System: %s" % bodies[focus_id]["name"],
		"Date: %s" % date_text,
		"Time warp: %s" % warp_text,
		"Tap top: next system | bottom left/right: slower/faster",
	]
	for i in lines.size():
		draw_string(ThemeDB.fallback_font, Vector2(12.0, 24.0 + 22.0 * i), lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))
