extends Node2D
## Solar system view: one system at a time (Sun, Earth or Mars), with the bodies on rails, the ship
## and its planned route. Time controls and navigation are in the bar along the top edge.
##
## Controls: the "System" button or Tab = next system, Space = pause, "+" / "-" or a tap on the
## bottom third (right / left half) = faster / slower, Escape = menu.

const MIN_BODY_RADIUS_PX := 3.0
const RING_RADIUS_PX := 10.0
const ORBIT_SAMPLES := 160

var focus_ids: Array = []      # bodies that have children, in file order (Sun first)
var focus_index := 0
var bar: TopBar


func _ready() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = 2.0
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	if not GameState.load_data():
		set_process(false)
		return
	for id in GameState.bodies:
		if not GameState.children[id].is_empty():
			focus_ids.append(id)

	var layer := CanvasLayer.new()
	add_child(layer)
	bar = TopBar.new()
	bar.setup("res://main.tscn", "System")
	bar.view_pressed.connect(_next_focus)
	bar.navigate.connect(func(path: String) -> void: get_tree().change_scene_to_file(path))
	layer.add_child(bar)


func _process(delta: float) -> void:
	GameState.advance(delta)
	bar.set_view_text("System: " + str(GameState.bodies[focus_ids[focus_index]]["name"]))
	bar.refresh()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if key and key.pressed and not key.echo:
		match key.keycode:
			KEY_TAB:
				_next_focus()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://menu.tscn")
			KEY_SPACE:
				GameState.toggle_pause()
			KEY_EQUAL, KEY_KP_ADD, KEY_PERIOD:
				GameState.change_warp(1)
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_COMMA:
				GameState.change_warp(-1)
	elif click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var size := get_viewport_rect().size
		if click.position.y > size.y * 0.67:
			GameState.change_warp(-1 if click.position.x < size.x * 0.5 else 1)


func _next_focus() -> void:
	if not focus_ids.is_empty():
		focus_index = (focus_index + 1) % focus_ids.size()


func _draw() -> void:
	if focus_ids.is_empty():
		return
	var bodies := GameState.bodies
	var time_jd := GameState.time_jd
	var focus_id: String = focus_ids[focus_index]
	var kid_ids: Array = GameState.children[focus_id]
	var view_size := get_viewport_rect().size
	var centre := Vector2(view_size.x * 0.5, view_size.y * 0.58)
	var half_extent := minf(view_size.x * 0.5, view_size.y * 0.38)

	# Scale so that the widest orbit (at its furthest point) fills 90 % of the available half-size.
	var max_extent := 1.0
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		max_extent = maxf(max_extent, float(segment["semi_major_axis_km"]) * (1.0 + float(segment["eccentricity"])))
	var px_per_km := half_extent * 0.9 / max_extent

	# Orbit lines first, then the route, then the bodies and the ship on top.
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		var line := PackedVector2Array()
		for point in Kepler.orbit_points(segment, ORBIT_SAMPLES):
			line.append(_to_screen(point, centre, px_per_km))
		draw_polyline(line, Color(1, 1, 1, 0.25), 1.0, true)

	var plan := GameState.plan
	if not plan.is_empty() and plan["frame"] == focus_id:
		var path := PackedVector2Array()
		for i in 81:
			var t := float(plan["t_dep"]) + float(plan["flight_days"]) * float(i) / 80.0
			path.append(_to_screen(Kepler.position_at(plan["transfer_segment"], t), centre, px_per_km))
		draw_polyline(path, Color(0.4, 0.9, 1.0, 0.9), 1.5, true)

	_draw_body(focus_id, centre, px_per_km)
	for kid_id in kid_ids:
		var segment := Kepler.segment_at(bodies[kid_id]["orbit_segments"], time_jd)
		_draw_body(kid_id, _to_screen(Kepler.position_at(segment, time_jd), centre, px_per_km), px_per_km)

	var ship_local := GameState.ship_rel(focus_id, time_jd)
	var p := _to_screen(ship_local, centre, px_per_km)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 5), p + Vector2(-6, 5)]), Color.WHITE)
	draw_string(ThemeDB.fallback_font, p + Vector2(10, 22), GameState.ship_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _to_screen(position_km: Vector2, centre: Vector2, px_per_km: float) -> Vector2:
	return centre + Vector2(position_km.x, -position_km.y) * px_per_km


func _draw_body(id: String, screen_position: Vector2, px_per_km: float) -> void:
	var body: Dictionary = GameState.bodies[id]
	var radius_px := maxf(MIN_BODY_RADIUS_PX, float(body["radius_km"]) * px_per_km)
	var colour := Color.html(body["draw_color"])
	draw_circle(screen_position, radius_px, colour)
	# While the body is too small to see, a ring in its colour marks it.
	if radius_px < RING_RADIUS_PX:
		draw_arc(screen_position, RING_RADIUS_PX, 0.0, TAU, 32, colour, 1.5, true)
		radius_px = RING_RADIUS_PX
	if not GameState.facility_at(id).is_empty():
		draw_rect(Rect2(screen_position + Vector2(-radius_px - 9.0, -radius_px - 9.0), Vector2(7, 7)), Color(1.0, 0.6, 0.2))
	draw_string(ThemeDB.fallback_font, screen_position + Vector2(radius_px + 4.0, 5.0), body["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
