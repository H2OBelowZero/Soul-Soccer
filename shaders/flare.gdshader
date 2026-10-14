shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Pass flare: a camera-facing star (T_flare81, brightness is alpha) riding the ball, tinted to the aura colour.

uniform sampler2D flare : filter_linear, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float fade = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.z += 0.9;
}

void fragment() {
	float f = texture(flare, UV).r;
	ALBEDO = mix(tint, vec3(1.0), f * 0.1);
	ALPHA = clamp(f * 2.6, 0.0, 1.0) * fade;
}
