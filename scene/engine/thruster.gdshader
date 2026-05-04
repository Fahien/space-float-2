shader_type spatial;
render_mode unshaded;

uniform float fade_power : hint_range(0.1, 10.0) = 1.0;
uniform float uv_middle_point = 0.5;

uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 noise_direction = vec2(0.0, -0.5);
uniform vec2 noise_scale = vec2(1.0, 2.0);
uniform float noise_strength : hint_range(0.0, 2.0) = 0.5;

uniform vec4 primary_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float neon_intensity : hint_range(1.0, 16.0) = 4.0;

void fragment() {
	// Distort the UV based on the noise and move based on time
	vec2 noise_uv = (UV * noise_scale) + (noise_direction * TIME);
	float noise_val = texture(noise_texture, noise_uv).r;
	float gradient = (uv_middle_point - UV.y);
	gradient += (noise_val - 0.5) * noise_strength;
	float base_alpha = pow(clamp(gradient, 0.0, 1.0), fade_power);
	ALPHA = base_alpha;
	
	vec3 current_color = primary_color.rgb;
	current_color = mix(primary_color.rgb, vec3(1.0), base_alpha);
	ALBEDO = current_color * neon_intensity;
}
