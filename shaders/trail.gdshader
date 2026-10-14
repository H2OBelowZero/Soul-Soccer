shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// World-space ribbon behind a kicked ball. Vertex colour carries tint (rgb) and age fade (a);
// UV.x runs along the ribbon, UV.y across it. The noise scrolls so it reads as streaking flame.

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float boost = 1.0;

void fragment() {
	float n = texture(noise, vec2(UV.x * 0.5 - TIME * 0.8, UV.y * 0.6)).r;
	float body = smoothstep(0.0, 0.6, 1.0 - abs(UV.y * 2.0 - 1.0));
	ALBEDO = COLOR.rgb * boost * (0.7 + 0.4 * n);
	ALPHA = clamp(COLOR.a * body * (0.75 + 0.8 * n), 0.0, 1.0);
}
