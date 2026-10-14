// Full-screen comic pass: ink outlines from depth + normals, halftone dots in the shadows.
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform float line_width = 2.0;
uniform float depth_threshold = 0.05;
uniform float normal_threshold = 0.45;
uniform float dot_size = 6.0;
uniform vec3 ink = vec3(0.05, 0.02, 0.07);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 p = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -p.z / p.w;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = line_width / VIEWPORT_SIZE;
	float d0 = lin_depth(uv, INV_PROJECTION_MATRIX);
	vec3 n0 = texture(normal_tex, uv).xyz * 2.0 - 1.0;
	float dd = 0.0;
	float nd = 0.0;
	vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
	for (int i = 0; i < 4; i++) {
		dd = max(dd, abs(lin_depth(uv + offs[i], INV_PROJECTION_MATRIX) - d0));
		vec3 n1 = texture(normal_tex, uv + offs[i]).xyz * 2.0 - 1.0;
		nd = max(nd, 1.0 - dot(n0, n1));
	}
	float edge = max(step(depth_threshold * d0, dd), step(normal_threshold, nd));
	edge *= 1.0 - smoothstep(55.0, 85.0, d0); // no ink on the distant skyline

	vec3 col = texture(screen_tex, uv).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec2 fc = FRAGCOORD.xy / dot_size;
	vec2 r = vec2(fc.x + fc.y, fc.x - fc.y) * 0.7071;
	float dist = length(fract(r) - 0.5);
	float rad = clamp((0.4 - lum) * 1.3, 0.0, 0.55);
	float dots = 1.0 - smoothstep(rad - 0.06, rad, dist);
	col = mix(col, col * 0.3, dots * 0.85);
	ALBEDO = mix(col, ink, edge);
}
