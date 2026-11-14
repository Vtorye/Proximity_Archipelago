shader_type canvas_item;

const float defoult_viewport_side = 50.; // for stuff to not change size when stretched
uniform int viewport_side = 50;

uniform sampler2D world_curr_col : filter_linear, repeat_disable;

uniform float alfa_cutoff = 0.6;
uniform float land_types_cutoff = 0.53;

uniform vec3 dirt_color : source_color;
uniform vec3 grass_color : source_color;
uniform vec3 mountains_color : source_color;

uniform vec3 mountain_pieck_color : source_color;
uniform sampler2D mountains_noise : source_color;
uniform float mountain_size : hint_range(0.000001, 0.1) = 0.03;
uniform float mountain_density : hint_range(0.0, 1.0) = 0.6;
uniform vec2 mountain_peak_x_range = vec2(0.25, 0.75);
uniform vec2 mountain_peak_y_range = vec2(0.0, 0.5);
uniform float mountain_height_variation : hint_range(0.0, 1.0) = 0.5; // random height scale is 1.0 +/- this
uniform bool mountains_do_discard_outside_region;
uniform float mountains_discard_outside_region_margin : hint_range(0.0, 0.5, 0.05) = 0.1;

uniform vec2 grass_blade_size = vec2(0.1, 0.15);

uniform bool draw_coast = true;
uniform vec2 coast_offset = vec2(0.003);
uniform vec3 coast_color : source_color;

//uniform vec2 shadow_offset = vec2(-0.015, -0.02);
//uniform vec3 shadow_color : source_color = vec3(0.0);

uniform vec3 waveline_color : source_color;
uniform float waveline_wave_scale = 33.0;
uniform float waveline_wave_speed = 3.0;
uniform float waveline_wave_amplitude = 2.0;
//uniform float waveline_wave_threshold = 0.5;
uniform float waveline_alpha_power = 2.0;
uniform float waveline_cutoff = 0.00000001;

uniform bool draw_grass_blades = true;
uniform float grass_blades_hight = 0.007;
uniform float grass_blades_ampletude = 70;

varying float scale_change;

vec2 get_aspect_correct_uv(vec2 uv) {
	vec2 size = vec2(textureSize(world_curr_col, 0));
	vec2 max_dim = vec2(max(size.x, size.y));
	return (uv * size - size * 0.5) / max_dim + 0.5;
}

float island_alpha(vec2 uv) {
	return texture(world_curr_col, uv).a;
}

float tringle(float x, float ampletude, float hight) {
    return abs(2.0 * fract(x * ampletude) - 1.0) * hight;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

//vec3 map_turrain_colors(vec3 in_col) {
	//vec3 col = grass_color;
	//if (in_col.r > land_types_cutoff) {
		//col = dirt_color;
	//}
	//if (in_col.b > land_types_cutoff) {
		//col = mountains_color;
	//}
	//if (in_col.g > land_types_cutoff) {
		//col = grass_color;
	//}
	//return col;
//}

vec3 terrain_color(vec3 curr_col, vec2 uv) {
	vec3 col = grass_color;
	//vec3 curr_col_with_grass = curr_col.xyz;
	
	if (draw_grass_blades && curr_col.g > land_types_cutoff) { // grass blades 
		float grass_offset = tringle(uv.x + sin(TIME * 1.3) * 0.002, grass_blades_ampletude, -grass_blades_hight) * scale_change;
		
		vec3 grass_blades = texture(world_curr_col, vec2(uv.x, uv.y + grass_offset)).xyz;
		
		//col = grass_blades;
		curr_col = grass_blades;
	}
	
	if (curr_col.r > land_types_cutoff) { // dirt
		col = dirt_color;
	}

	
	if (curr_col.b > land_types_cutoff) { // mountains
		
		// arbitrary constants that keep the different random rolls independent of each other
		const vec2 peak_x_salt = vec2(13.5, 71.3);
		const vec2 peak_y_salt = vec2(39.1, 5.7);
		const vec2 height_salt = vec2(3.3, 9.9);
		
		col = mountains_color;

		float adjusted_mountain_size = mountain_size * scale_change;
		vec2 grid_pos = uv / adjusted_mountain_size;
		vec2 cell_id = floor(grid_pos);

		// check the 3x3 neighbourhood to let neighbouring mountains overlap
		for (int row = -1; row <= 1; row++) {
			for (int column = -1; column <= 1; column++) {
				vec2 neighbor_cell = cell_id + vec2(float(column), float(row));

				if (hash12(neighbor_cell) > mountain_density) {
					continue; // randomly discard this mountain
				}

				// random peak position within the cell
				vec2 peak_pos = vec2(
					mix(mountain_peak_x_range.x, mountain_peak_x_range.y, hash12(neighbor_cell + peak_x_salt)),
					mix(mountain_peak_y_range.x, mountain_peak_y_range.y, hash12(neighbor_cell + peak_y_salt))
				);

				// discard the mountain if corners fall outside the mountain region
				if (mountains_do_discard_outside_region) {
					float m = mountains_discard_outside_region_margin;
					vec2 down_left_corner_uv = (neighbor_cell + peak_pos + vec2(-0.5 + m, 1.0 - m)) * adjusted_mountain_size;
					vec2 down_right_corner_uv = (neighbor_cell + peak_pos + vec2(0.5 - m, 1.0 - m)) * adjusted_mountain_size;
					vec2 up_left_corner_uv = (neighbor_cell + peak_pos + vec2(-0.5 + m, m)) * adjusted_mountain_size;
					vec2 up_right_corner_uv = (neighbor_cell + peak_pos + vec2(0.5 - m, m)) * adjusted_mountain_size;
					if (
							texture(world_curr_col, down_left_corner_uv).b <= land_types_cutoff || 
							texture(world_curr_col, down_right_corner_uv).b <= land_types_cutoff ||
							texture(world_curr_col, up_left_corner_uv).b <= land_types_cutoff ||
							texture(world_curr_col, up_right_corner_uv).b <= land_types_cutoff
							) {
						continue;
					}
				}

				// fragment position within the cell, relative to the peak
				vec2 peak_local_pos = grid_pos - neighbor_cell - peak_pos;

				float height_scale = 1.0 + (hash12(neighbor_cell + height_salt) * 2.0 - 1.0) * mountain_height_variation;
				float hight = texture(mountains_noise, uv).x * 2. * height_scale;
				float mountain_hight = hight / 2. - pow(peak_local_pos.x, 2.) * 2. * hight;

				float gradient_value = 1. - peak_local_pos.y; // 1 at the cell bottom, 0 at the cell top
				if (gradient_value >= 0. && gradient_value < mountain_hight) {
					col = mix(mountains_color, mountain_pieck_color, gradient_value);
				}
			}
		}
	}
	return col;
	//return map_turrain_colors(curr_col);
}

vec4 waveline(float alpha) {
	float wave = sin(alpha * waveline_wave_scale + sin(TIME * waveline_wave_speed) * waveline_wave_amplitude);
	if (wave < 0.5) {
		wave = 0.;
	} else {
		wave = 1.;
	}
	float edge_alpha = clamp(pow(alpha / alfa_cutoff, waveline_alpha_power), 0.0, 1.0) * wave;

	return vec4(waveline_color * wave, edge_alpha);
}

void fragment() {
	scale_change = defoult_viewport_side / float(viewport_side);
	
	vec2 uv = get_aspect_correct_uv(UV);
	vec4 curr_col = texture(world_curr_col, uv);
	vec4 res_col;

	if (curr_col.a > alfa_cutoff) {
		res_col = vec4(terrain_color(curr_col.xyz, uv), 1.0);

		if (draw_coast && island_alpha(uv + coast_offset) < alfa_cutoff) {
			res_col = vec4(coast_color, 1.0);
		}
	} else {
		res_col.a = 0.0;
		
		vec4 wave_col = vec4(0.);
		if (curr_col.a > waveline_cutoff) {
			wave_col = waveline(curr_col.a); // wave line
		}
		
		//if (island_alpha(uv + shadow_offset) > alfa_cutoff) { // shadow
			//res_col = vec4(shadow_color, 1.);
		//}
		
		res_col = wave_col;
		
	}

	COLOR = res_col;
}