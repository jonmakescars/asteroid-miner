// Lighting for the ship, asteroid and body sprites.
// NOT YET TESTED IN GODOT: written for Godot 4.x, Compatibility renderer.
// Put it in a ShaderMaterial on a Sprite2D (or any CanvasItem that draws one texture).
//
// All directions are in the sprite's own local space: x to the right, y down.
// For a sprite that rotates, turn the world direction into local space first:
//   var to_sun := (sun_position - global_position).rotated(-global_rotation)
//   material.set_shader_parameter("sun_dir", to_sun)
shader_type canvas_item;

// The matching *_n.png file. Leave empty for flat lighting.
uniform sampler2D normal_map : hint_normal, filter_linear;

// Direction from the sprite towards the sun.
uniform vec2 sun_dir = vec2(1.0, 0.0);
// How far the sun is raised out of the screen, in radians.
// About 0.56 for ships and asteroids. Use 0.0 for planets and moons,
// which gives a half-lit disc with the dark side away from the sun.
uniform float sun_elevation = 0.56;
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.9);
uniform float sun_strength = 1.15;

// Second, weak light: sunlight reflected off a nearby body (for example the Moon).
uniform vec2 fill_dir = vec2(0.0, 1.0);
uniform float fill_elevation = 0.44;
uniform vec3 fill_color : source_color = vec3(0.66, 0.73, 0.84);
uniform float fill_strength = 0.0;

uniform float ambient = 0.05;

// Atmospheric heating glow, 0 to 1 (the log-scaled heat rate from the design document).
uniform float heat = 0.0;
// Direction of travel through the atmosphere.
uniform vec2 heat_dir = vec2(1.0, 0.0);
uniform vec3 heat_color : source_color = vec3(1.0, 0.54, 0.16);

varying vec4 modulate;

vec3 dir3(vec2 d, float elevation) {
	vec2 n = vec2(1.0, 0.0);
	if (length(d) > 0.0001) {
		n = normalize(d);
	}
	return vec3(n * cos(elevation), sin(elevation));
}

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Normal maps are stored with green = up (the usual convention); local space has y down.
	vec3 n = texture(normal_map, UV).rgb * 2.0 - 1.0;
	n.y = -n.y;
	n = normalize(n);

	float sun = max(dot(n, dir3(sun_dir, sun_elevation)), 0.0);
	float fill = max(dot(n, dir3(fill_dir, fill_elevation)), 0.0);
	vec3 light = sun_color * sun_strength * sun + fill_color * fill_strength * fill + vec3(ambient);
	vec3 col = tex.rgb * min(light, vec3(1.3));

	float facing = max(dot(n, dir3(heat_dir, 0.28)), 0.0);
	col += heat_color * heat * 2.4 * facing;

	COLOR = vec4(col, tex.a) * modulate;
}
