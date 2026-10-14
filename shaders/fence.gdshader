// Chain-link steel fence / goal net, patterned in world space so every panel lines up.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 wire = vec3(0.62, 0.65, 0.7);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wp.x + wp.z, wp.y) * 5.0;
	vec2 r = vec2(p.x + p.y, p.x - p.y);
	vec2 f = abs(fract(r) - 0.5);
	ALBEDO = wire;
	ALPHA = smoothstep(0.40, 0.47, max(f.x, f.y)) * 0.85;
}
