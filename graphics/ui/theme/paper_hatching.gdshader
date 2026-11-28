shader_type canvas_item;
render_mode unshaded;

uniform sampler2D stroke_texture : repeat_enable, filter_linear;
uniform float hatch_strength : hint_range(0.0, 0.3, 0.01) = 0.1;
uniform float hatch_spacing : hint_range(4.0, 24.0, 0.5) = 8.0;

varying vec2 panel_position;

void vertex() {
	panel_position = VERTEX;
}

void fragment() {
	vec2 direction = normalize(vec2(1.0, -0.7));
	float along = dot(panel_position, direction);
	float across = dot(panel_position, vec2(-direction.y, direction.x));
	float row = floor(across / hatch_spacing);
	float row_center = (row + 0.5) * hatch_spacing;

	// Sample along each row independently to vary pressure and break up the strokes.
	vec2 stroke_uv = vec2(along / 8.0, row * 3.0) / vec2(textureSize(stroke_texture, 0));
	float pressure = texture(stroke_texture, stroke_uv).r;
	float stroke_offset = (pressure - 0.5) * 1.2;
	float distance_to_stroke = abs(across - row_center - stroke_offset);
	float edge = max(fwidth(across) * 0.5, 0.01);
	float stroke = 1.0 - smoothstep(0.55 - edge, 0.55 + edge, distance_to_stroke);
	stroke *= smoothstep(0.35, 0.64, pressure);

	COLOR.rgb = min(COLOR.rgb + vec3(stroke * hatch_strength), vec3(1.0));
}
