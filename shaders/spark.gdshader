shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Shot spark: a flattened T_circle42 (brightness is alpha) facing the camera, its long axis along the particle's
// direction of travel (the particle material aligns Y to velocity).

uniform sampler2D disc : filter_linear, repeat_disable;

void vertex() {
	vec3 along = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz;
	vec2 d = normalize(along.xy + vec2(0.0001));
	vec3 at = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	MODELVIEW_MATRIX = mat4(vec4(d.y, -d.x, 0.0, 0.0), vec4(d, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(at, 1.0));
}

void fragment() {
	float f = texture(disc, UV).r;
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(f * 1.6, 0.0, 1.0) * COLOR.a;
}
