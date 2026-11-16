shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Storm wall: swirling purple curtain, brighter streaks, soft top fade.

uniform vec4 base_color : source_color = vec4(0.45, 0.18, 0.75, 0.42);
uniform vec4 streak_color : source_color = vec4(0.85, 0.6, 1.0, 0.7);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float ang = atan(local_pos.z, local_pos.x);
	vec2 uv = vec2(ang * 40.0, local_pos.y * 0.03);
	float n = noise(uv + vec2(TIME * 0.6, -TIME * 0.25)) * 0.6 + noise(uv * 2.7 + vec2(-TIME, TIME * 0.4)) * 0.4;
	float streak = smoothstep(0.62, 0.9, noise(vec2(ang * 120.0, local_pos.y * 0.01 - TIME * 0.8)));
	vec4 c = mix(base_color, streak_color, streak * 0.6 + n * 0.25);
	float fade = 1.0 - smoothstep(0.75, 1.0, local_pos.y / 1.0);
	ALBEDO = c.rgb;
	ALPHA = c.a * (0.7 + n * 0.5) * fade;
}
