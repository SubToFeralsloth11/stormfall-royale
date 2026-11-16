shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Vertex-coloured terrain with world-space breakup so large fields read as
// stylised grass/dirt instead of flat colour.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 srgb = COLOR.rgb;
	vec3 base = pow(srgb, vec3(2.2)); // vertex colours are authored in sRGB
	float big = texture(noise_tex, world_pos.xz * 0.0045).r;
	float mid = texture(noise_tex, world_pos.xz * 0.03 + 0.37).r;
	float fine = texture(detail_tex, world_pos.xz * 0.35).r;
	float grassiness = smoothstep(0.25, 0.6, srgb.g - max(srgb.r, srgb.b) * 0.6);
	vec3 c = base * mix(0.82, 1.12, big);
	c = mix(c, c * vec3(1.1, 1.05, 0.7), grassiness * smoothstep(0.55, 0.8, mid) * 0.6); // sun-dried patches
	c = mix(c, c * vec3(0.75, 0.9, 0.7), grassiness * smoothstep(0.45, 0.2, mid) * 0.5); // lush dark patches
	c *= mix(0.9, 1.06, fine);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
