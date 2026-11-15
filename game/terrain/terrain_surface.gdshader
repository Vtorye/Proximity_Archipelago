shader_type canvas_item;
render_mode unshaded;

group_uniforms Palette;
uniform vec4 dirt_color : source_color;
uniform vec4 grass_color : source_color;
uniform vec4 stone_color : source_color;
uniform vec4 peak_color : source_color;
uniform sampler2D terrain_noise : filter_linear, repeat_enable;
uniform float noise_period : hint_range(1.0, 256.0) = 50.0;
uniform float texture_strength : hint_range(0.0, 0.3) = 0.05;

group_uniforms Grass;
uniform float blade_frequency : hint_range(0.0, 12.0) = 2.5;
uniform float blade_height : hint_range(0.0, 0.5) = 0.15;
uniform float blade_sway : hint_range(0.0, 0.5) = 0.1;
uniform float blade_speed : hint_range(0.0, 8.0) = 1.3;
uniform float blade_contrast : hint_range(0.0, 0.5) = 0.24;

group_uniforms Relief;
uniform float mountain_size : hint_range(0.25, 8.0) = 1.95;
uniform float mountain_density : hint_range(0.0, 1.0) = 1.0;
uniform float mountain_height_variation : hint_range(0.0, 1.0) = 0.622;

group_uniforms Shore;
uniform vec4 water_color : source_color;
uniform vec4 coast_color : source_color;
uniform vec2 coast_offset = vec2(0.15);
uniform float coast_width : hint_range(0.01, 0.5) = 0.25;
uniform float coast_rounding : hint_range(0.25, 0.5) = 0.4;
uniform vec4 wave_color : source_color;
uniform float wave_scale : hint_range(0.0, 64.0) = 33.0;
uniform float wave_speed : hint_range(0.0, 8.0) = 1.0;
uniform float wave_amplitude : hint_range(0.0, 4.0) = 2.0;
uniform float wave_falloff : hint_range(0.5, 4.0) = 2.0;
group_uniforms;

varying vec2 terrain_pos;

void vertex() {
	terrain_pos = VERTEX;
}

float hash_cell(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float mountain_relief(vec2 point, float noise_value) {
	vec2 grid = point / mountain_size;
	vec2 tile = floor(grid);
	float relief = 0.0;
	// Neighboring mountains can overlap. Independent hash offsets vary their peaks and heights.
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = tile + vec2(float(x), float(y));
			if (hash_cell(neighbor) > mountain_density) {
				continue;
			}
			vec2 peak = vec2(
				mix(0.25, 0.75, hash_cell(neighbor + vec2(13.5, 71.3))),
				mix(0.0, 0.5, hash_cell(neighbor + vec2(39.1, 5.7)))
			);
			vec2 local = grid - neighbor - peak;
			float height = noise_value * (1.0 + (2.0 * hash_cell(neighbor + vec2(3.3, 9.9)) - 1.0) * mountain_height_variation);
			float profile = (1.0 - 4.0 * local.x * local.x) * height;
			float elevation = 1.0 - local.y;
			if (elevation >= 0.0 && elevation < profile) {
				relief = max(relief, elevation);
			}
		}
	}
	return clamp(relief, 0.0, 1.0);
}

float wave_opacity(float coverage) {
	float wave = sin(coverage * wave_scale + sin(TIME * wave_speed) * wave_amplitude);
	return step(0.5, wave) * pow(min(2.0 * coverage, 1.0), wave_falloff) * wave_color.a;
}

void fragment() {
	vec2 pixel = TEXTURE_PIXEL_SIZE;
	vec2 map_sample = UV / pixel;
	vec2 size = 1.0 / pixel;
	// Each patch includes an apron for linear filtering across its edges.
	if (any(lessThan(map_sample, vec2(1.0))) || any(greaterThanEqual(map_sample, size - 1.0))) {
		discard;
	}

	vec4 cell = texelFetch(TEXTURE, ivec2(map_sample), 0);
	float coverage = texture(TEXTURE, UV).a;
	if (cell.a == 0.0) {
		float waves = wave_opacity(coverage);
		COLOR = cell.r > 0.0 ? vec4(mix(water_color.rgb, wave_color.rgb, waves), 1.0) : vec4(wave_color.rgb, waves);
	} else if (dot(cell.rgb, vec3(1.0)) == 0.0) {
		discard;
	} else if (coverage < coast_rounding) {
		COLOR = vec4(mix(water_color.rgb, wave_color.rgb, wave_opacity(coverage)), 1.0);
	} else {
		float noise_value = texture(terrain_noise, terrain_pos / noise_period).r;
		vec3 stone = stone_color.rgb;
		if (cell.b > max(cell.r, cell.g)) {
			stone = mix(stone, peak_color.rgb, mountain_relief(terrain_pos, noise_value));
		}

		vec3 grass = grass_color.rgb;
		if (cell.g > 0.0 && blade_height > 0.0) {
			float wind = sin(TIME * blade_speed) * blade_sway;
			float blade = abs(2.0 * fract((terrain_pos.x + wind) * blade_frequency) - 1.0) * blade_height;
			float edge = texture(TEXTURE, UV - vec2(0.0, blade) * pixel).g;
			grass *= 1.0 - blade_contrast * (1.0 - clamp(edge / cell.g, 0.0, 1.0));
		}

		vec3 color = cell.r * dirt_color.rgb + cell.g * grass + cell.b * stone;
		color *= 1.0 + (2.0 * noise_value - 1.0) * texture_strength;
		float shore = texture(TEXTURE, UV + clamp(coast_offset, vec2(-0.5), vec2(0.5)) * pixel).a;
		float coast = 1.0 - smoothstep(coast_rounding, coast_rounding + coast_width, shore);
		COLOR = vec4(mix(color, coast_color.rgb, coast * coast_color.a), 1.0);
	}
}
