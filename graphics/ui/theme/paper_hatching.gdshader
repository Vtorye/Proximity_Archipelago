shader_type canvas_item;
render_mode unshaded;

uniform sampler2D stroke_texture : repeat_enable, filter_linear;
uniform float hatch_strength : hint_range(0.0, 0.3, 0.01) = 0.1;
uniform float hatch_spacing : hint_range(4.0, 24.0, 0.5) = 8.0;
uniform float hatch_edge_softness : hint_range(0.1, 0.5, 0.05) = 0.5;

group_uniforms Pencil_Outline;
uniform vec4 outline_color : source_color = vec4(0.94, 0.80, 0.58, 0.95);
uniform float outline_width : hint_range(0.5, 4.0, 0.1) = 2.3;
uniform float outline_roughness : hint_range(0.0, 2.5, 0.1) = 1.1;
uniform float outline_corner_radius : hint_range(0.0, 12.0, 0.5) = 6.0;
uniform float outline_wobble : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform float outline_wobble_rate : hint_range(2.0, 12.0, 1.0) = 6.0;
uniform bool outline_pixel_snap = false;
group_uniforms;

instance uniform vec2 panel_size;
varying vec2 panel_position;

void vertex() {
	panel_position = VERTEX;
}

vec2 pencil_edge(vec2 position, vec2 texture_size) {
	vec2 from_edge = min(position, panel_size - position);
	float antialias = max(max(fwidth(position.x), fwidth(position.y)) * 0.45, 0.01);
	float short_side = min(panel_size.x, panel_size.y);
	float inset = outline_width * 0.55 + outline_roughness + outline_wobble;
	float radius = clamp(short_side * 0.5 - inset, 0.0, outline_corner_radius);
	float rim = inset + radius + outline_width + outline_roughness + outline_wobble;
	if (short_side <= 0.0 || min(from_edge.x, from_edge.y) > rim + antialias) {
		return vec2(0.0, 1.0);
	}

	// Each side samples a different row, so its contour has its own uneven line.
	float vertical_row = mix(13.0, 47.0, step(panel_size.x * 0.5, position.x));
	float horizontal_row = mix(89.0, 137.0, step(panel_size.y * 0.5, position.y));
	vec2 along_edge = position.yx / 12.0;
	vec2 pressure = vec2(
		textureLod(stroke_texture, vec2(along_edge.x, vertical_row) / texture_size, 0.0).r,
		textureLod(stroke_texture, vec2(along_edge.y, horizontal_row) / texture_size, 0.0).r
	);

	vec2 displacement = (pressure * 2.0 - 1.0) * outline_roughness;
	if (outline_wobble > 0.0) {
		// Step through discrete drawings, with no motion in the fill texture.
		float frame = mod(floor(TIME * outline_wobble_rate), 32.0);
		vec2 drift = vec2(
			textureLod(stroke_texture, vec2(along_edge.x, vertical_row + frame * 7.0) / texture_size, 0.0).r,
			textureLod(stroke_texture, vec2(along_edge.y, horizontal_row + frame * 7.0) / texture_size, 0.0).r
		);
		displacement += (drift * 2.0 - 1.0) * outline_wobble;
	}
	// Keep a baked line centered on the same texel row across nine-patch repeats.
	if (outline_pixel_snap) {
		displacement = vec2(floor(inset) + 0.5 - inset);
	}

	vec2 corner = vec2(radius + inset) - from_edge + displacement;
	float distance_to_edge = length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - radius;
	float nib_pressure = mix(pressure.x, pressure.y, step(corner.x, corner.y));
	float half_width = outline_width * mix(0.43, 0.57, nib_pressure);
	float line = 1.0 - smoothstep(half_width - antialias, half_width + antialias, abs(distance_to_edge));
	float fill = 1.0 - smoothstep(-antialias, antialias, distance_to_edge);
	return vec2(line, fill);
}

void fragment() {
	vec2 direction = normalize(vec2(1.0, -0.7));
	float along = dot(panel_position, direction);
	float across = dot(panel_position, vec2(-direction.y, direction.x));
	float row = floor(across / hatch_spacing);
	float row_center = (row + 0.5) * hatch_spacing;

	// Sample along each row independently to vary pressure and break up the strokes.
	vec2 texture_size = vec2(textureSize(stroke_texture, 0));
	vec2 stroke_uv = vec2(along / 8.0, row * 3.0) / texture_size;
	float pressure = texture(stroke_texture, stroke_uv).r;
	float stroke_offset = (pressure - 0.5) * 1.2;
	float distance_to_stroke = abs(across - row_center - stroke_offset);
	float edge = max(fwidth(across) * hatch_edge_softness, 0.01);
	float stroke = 1.0 - smoothstep(0.55 - edge, 0.55 + edge, distance_to_stroke);
	stroke *= smoothstep(0.35, 0.64, pressure);

	COLOR.rgb = min(COLOR.rgb + vec3(stroke * hatch_strength), vec3(1.0));
	vec2 paper_edge = pencil_edge(panel_position, texture_size);
	float pencil = paper_edge.x * outline_color.a;
	float visible_fill = COLOR.a * paper_edge.y * (1.0 - pencil);
	COLOR.a = pencil + visible_fill;
	COLOR.rgb = (outline_color.rgb * pencil + COLOR.rgb * visible_fill) / max(COLOR.a, 0.0001);
}
