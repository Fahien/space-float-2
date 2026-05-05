shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D plasma_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_noise : repeat_enable, filter_linear_mipmap;

uniform vec4 dark_orange : source_color = vec4(0.65, 0.05, 0.00, 1.0);
uniform vec4 orange      : source_color = vec4(1.00, 0.32, 0.02, 1.0);
uniform vec4 yellow      : source_color = vec4(1.00, 0.85, 0.20, 1.0);
uniform vec4 white_hot   : source_color = vec4(1.00, 0.98, 0.75, 1.0);

uniform float plasma_scale = 2.5;
uniform float detail_scale = 12.0;
uniform float flow_speed = 0.035;

uniform float contrast = 1.8;
uniform float emission_strength = 4.0;
uniform float hot_spot_threshold = 0.68;

uniform float surface_displacement = 0.025;

void vertex() {
	vec2 moving_uv = UV * plasma_scale + vec2(TIME * flow_speed, TIME * flow_speed * 0.4);
	float n = texture(plasma_noise, moving_uv).r;

	VERTEX += NORMAL * (n - 0.5) * surface_displacement;
}

void fragment() {
	vec2 uv1 = UV * plasma_scale;
	vec2 uv2 = UV * detail_scale;

	uv1 += vec2(TIME * flow_speed, TIME * flow_speed * 0.35);
	uv2 += vec2(-TIME * flow_speed * 2.0, TIME * flow_speed * 1.4);

	float plasma = texture(plasma_noise, uv1).r;
	float detail = texture(detail_noise, uv2).r;

	float fire = mix(plasma, detail, 0.35);
	fire = pow(fire, contrast);

	vec3 col = dark_orange.rgb;
	col = mix(col, orange.rgb, smoothstep(0.15, 0.45, fire));
	col = mix(col, yellow.rgb, smoothstep(0.42, 0.75, fire));
	col = mix(col, white_hot.rgb, smoothstep(hot_spot_threshold, 1.0, fire));

	// Slight edge darkening so the sphere reads as a solar body.
	float rim = dot(NORMAL, VIEW);
	float limb = smoothstep(0.0, 0.8, rim);
	col *= mix(0.55, 1.15, limb);

	ALBEDO = col;
	EMISSION = col * emission_strength;
}