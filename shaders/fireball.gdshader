shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Shot head: a camera-facing quad. T_flare12 (streaky ring) spins and is wobbled by scrolling noise, around a soft
// flickering core. Tinted to the ball's aura colour.

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D flare : filter_linear, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0, 0.4, 0.1);
uniform float fade = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.z += 0.9; // toward the camera, so the floor doesn't slice the lower half of the quad
}

void fragment() {
	vec2 c = UV - 0.5;
	float n1 = texture(noise, UV * 1.4 + vec2(TIME * 0.9, TIME * 1.3)).r;
	float n2 = texture(noise, UV * 2.2 - vec2(TIME * 1.7, TIME * 0.6)).r;
	float a = TIME * 7.0;
	vec2 spun = vec2(c.x * cos(a) - c.y * sin(a), c.x * sin(a) + c.y * cos(a)) + 0.5 + (n1 - 0.5) * 0.06;
	float ring = texture(flare, spun).r;
	float core = smoothstep(0.3, 0.0, length(c)) * (0.5 + 0.9 * n2);
	ALBEDO = mix(tint, vec3(1.0), clamp(core * 0.15, 0.0, 1.0));
	ALPHA = clamp(ring * 3.0 + core * 0.9, 0.0, 0.85) * fade;   // the core stays see-through so the ball shows inside
}
