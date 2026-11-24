// Night-side lights of a body (city lights): the *_glow.png layer of the body, drawn on top of it and added to
// the picture, but only on the side that the Sun does not light.
// NOT YET TESTED IN GODOT: written for Godot 4.x, Compatibility renderer.
//
// The side that is lit is worked out the same way as in sprite_lit.gdshader for a planet (sun_elevation 0), from the
// body's own normal map and the direction of the Sun on the screen, so the lights fade out exactly where the
// daylight fades in. All directions are in the sprite's own space: x to the right, y down.
shader_type canvas_item;
render_mode blend_add;

// The normal map of the body (for example earth_n.png).
uniform sampler2D normal_map : hint_normal, filter_linear;
// Direction from the body towards the Sun.
uniform vec2 sun_dir = vec2(1.0, 0.0);
// Brightness of the lights.
uniform float strength = 1.0;
// How far past the terminator the lights have faded in completely (the lit() value: -1 is the middle of the night side).
uniform float fade_from = 0.04;
uniform float fade_to = -0.30;

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec3 n = texture(normal_map, UV).rgb * 2.0 - 1.0;
	n.y = -n.y;
	n = normalize(n);
	vec2 d = vec2(1.0, 0.0);
	if (length(sun_dir) > 0.0001) {
		d = normalize(sun_dir);
	}
	float lit = dot(n, vec3(d, 0.0));
	// (smoothstep needs its first edge below the second one; with the edges the other way round the result is undefined)
	float night = 1.0 - smoothstep(fade_to, fade_from, lit);
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb * night * strength, tex.a) * modulate;
}
