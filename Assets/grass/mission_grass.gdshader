shader_type spatial;
render_mode blend_mix, depth_draw_opaque, depth_test_default, cull_disabled, diffuse_toon, specular_schlick_ggx;

uniform sampler2D WindNoise;
uniform vec4 BaseColor : source_color = vec4(0.054574, 0.054574, 0.054574, 1.0);
uniform vec4 GrassColor : source_color = vec4(0.396078, 0.650980, 0.211765, 1.0);
uniform float BladeScale : hint_range(0.2, 1.5, 0.05) = 0.6;
uniform float WindStrength : hint_range(0.0, 3.0, 0.05) = 1.8;
uniform float WindSpeed : hint_range(0.0, 3.0, 0.05) = 0.55;
uniform vec2 WindDirection = vec2(1.0, 0.25);


void vertex() {
	vec3 scaled_vertex = VERTEX * BladeScale;
	vec2 wind_uv = (NODE_POSITION_WORLD.xz + vec2(TIME * WindSpeed)) * 0.1 + UV;
	float wind_amount = texture(WindNoise, wind_uv).r;
	vec2 wind_direction = WindDirection / max(length(WindDirection), 0.001);
	float tip_weight = 1.0 - UV.y;

	// Корень травинки остаётся на месте, сильнее всего ветер отклоняет верхушку.
	scaled_vertex.xz += wind_direction * wind_amount * tip_weight * WindStrength;
	VERTEX = scaled_vertex;
}


void fragment() {
	float tip_weight = 1.0 - UV.y;
	ALBEDO = mix(BaseColor.rgb, GrassColor.rgb, tip_weight);
	NORMAL = vec3(0.0, 1.0, 0.0);
}
