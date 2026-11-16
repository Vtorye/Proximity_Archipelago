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
uniform float terrain_edge_variation : hint_range(0.0, 0.35, 0.01) = 0.24;
uniform float terrain_transition_pixels : hint_range(1.0, 8.0, 0.1) = 3.0;

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

vec3 ground_palette(vec3 soils[4], vec2 point, vec2 pixel_span) {
	if (all(equal(soils[0], soils[1])) && all(equal(soils[0], soils[2])) && all(equal(soils[0], soils[3]))) {
		return soils[0];
	}

	// Cubic weights make adjoining contour segments meet tangentially at cell centers.
	vec2 factor = smoothstep(vec2(0.0), vec2(1.0), point);
	vec2 inverse = 1.0 - factor;
	vec2 slope = 6.0 * point * (1.0 - point);
	vec4 votes = vec4(inverse.x * inverse.y, factor.x * inverse.y, inverse.x * factor.y, factor.x * factor.y);
	vec4 vote_dx = vec4(-inverse.y, inverse.y, -factor.y, factor.y) * slope.x;
	vec4 vote_dy = vec4(-inverse.x, -factor.x, inverse.x, factor.x) * slope.y;

	vec4 scores = vec4(-1.0);
	vec2 gradients[4];
	int best = 0;
	for (int i = 0; i < 4; i++) {
		if (all(equal(soils[i], vec3(0.0)))) {
			continue;
		}
		// Cells with the same soil donate their weight to one candidate.
		vec4 matching = vec4(0.0);
		bool counted = false;
		for (int j = 0; j < 4; j++) {
			if (all(equal(soils[i], soils[j]))) {
				matching[j] = 1.0;
				counted = counted || j < i;
			}
		}
		if (counted) {
			continue;
		}
		scores[i] = dot(matching, votes);
		gradients[i] = vec2(dot(matching, vote_dx), dot(matching, vote_dy));
		if (scores[i] > scores[best]) {
			best = i;
		}
	}

	// Mix only at the contour, using the score difference per screen pixel.
	vec3 palette = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		if (scores[i] < 0.0) {
			continue;
		}
		float slope_per_pixel = dot(abs(gradients[best] - gradients[i]), pixel_span);
		float edge = max(0.5 * terrain_transition_pixels * slope_per_pixel, 0.00001);
		float weight = 1.0 - smoothstep(0.0, edge, scores[best] - scores[i]);
		palette += soils[i] * weight;
		total += weight;
	}
	return palette / max(total, 0.00001);
}

void fragment() {
	vec2 pixel = TEXTURE_PIXEL_SIZE;
	vec2 map_sample = UV / pixel;
	vec2 size = 1.0 / pixel;
	vec2 pixel_span = fwidth(map_sample);
	float coverage = texture(TEXTURE, UV).a;
	float wave = sin(coverage * wave_scale + sin(TIME * wave_speed) * wave_amplitude);
	float wave_aa = clamp(0.5 * fwidth(wave), 0.00001, 0.5);
	float waves = smoothstep(0.5 - wave_aa, 0.5 + wave_aa, wave)
		* pow(min(2.0 * coverage, 1.0), wave_falloff) * wave_color.a;
	vec3 water = mix(water_color.rgb, wave_color.rgb, waves);
	float coast_aa = max(0.5 * fwidth(coverage), 0.00001);
	float land = smoothstep(coast_rounding - coast_aa, coast_rounding + coast_aa, coverage);
	// Each patch includes an apron for filtering across its edges.
	if (any(lessThan(map_sample, vec2(1.0))) || any(greaterThanEqual(map_sample, size - 1.0))) {
		discard;
	}

	vec4 cell = texelFetch(TEXTURE, ivec2(map_sample), 0);
	if (cell.a == 0.0) {
		COLOR = cell.r > 0.0 ? vec4(water, 1.0) : vec4(wave_color.rgb, waves);
	} else if (dot(cell.rgb, vec3(1.0)) == 0.0) {
		discard;
	} else {
		vec2 noise_uv = terrain_pos / noise_period;
		float noise_value = texture(terrain_noise, noise_uv).r;
		// Read a second, decorrelated component from the same world-space noise.
		vec2 edge_noise = vec2(noise_value, texture(terrain_noise, noise_uv + vec2(0.37, 0.61)).r);
		vec2 texel = map_sample + (2.0 * edge_noise - 1.0) * terrain_edge_variation - 0.5;
		ivec2 corner = ivec2(floor(texel));
		vec4 upper_left = texelFetch(TEXTURE, corner, 0);
		vec4 upper_right = texelFetch(TEXTURE, corner + ivec2(1, 0), 0);
		vec4 lower_left = texelFetch(TEXTURE, corner + ivec2(0, 1), 0);
		vec4 lower_right = texelFetch(TEXTURE, corner + ivec2(1, 1), 0);
		// Zero-alpha water and black atlas tiles do not supply soil colors.
		vec3 soils[4] = {
			upper_left.rgb * upper_left.a, upper_right.rgb * upper_right.a,
			lower_left.rgb * lower_left.a, lower_right.rgb * lower_right.a
		};
		vec3 blend = ground_palette(soils, fract(texel), pixel_span);
		vec3 stone = stone_color.rgb;
		float relief = smoothstep(0.25, 0.6, blend.b);
		if (relief > 0.0) {
			stone = mix(stone, peak_color.rgb, relief * mountain_relief(terrain_pos, noise_value));
		}

		vec3 grass = grass_color.rgb;
		if (blend.g > 0.0 && blade_height > 0.0) {
			float wind = sin(TIME * blade_speed) * blade_sway;
			float blade = abs(2.0 * fract((terrain_pos.x + wind) * blade_frequency) - 1.0) * blade_height;
			float edge = texture(TEXTURE, UV - vec2(0.0, blade) * pixel).g;
			grass *= 1.0 - blade_contrast * (1.0 - clamp(edge / blend.g, 0.0, 1.0));
		}

		vec3 color = blend.r * dirt_color.rgb + blend.g * grass + blend.b * stone;
		color *= 1.0 + (2.0 * noise_value - 1.0) * texture_strength;
		float shore = texture(TEXTURE, UV + clamp(coast_offset, vec2(-0.5), vec2(0.5)) * pixel).a;
		float coast = 1.0 - smoothstep(coast_rounding, coast_rounding + coast_width, shore);
		color = mix(color, coast_color.rgb, coast * coast_color.a);
		COLOR = vec4(mix(water, color, land), 1.0);
	}
}
