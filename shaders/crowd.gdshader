// Township crowd: per-instance colour, bouncing harder as `excite` rises.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform float excite = 0.1;
varying vec3 tint;

void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float spd = 3.0 + INSTANCE_CUSTOM.y * 3.0 + excite * 6.0;
	VERTEX.y += abs(sin(TIME * spd + ph)) * (0.05 + excite * 0.5);
	tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.9;
}
