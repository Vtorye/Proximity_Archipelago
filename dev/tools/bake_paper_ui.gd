extends SceneTree
## Regenerate the nine-patch textures with a rendering-enabled Godot session.
## godot --path . --audio-driver Dummy --script res://dev/tools/bake_paper_ui.gd
## Pass -- --fine to bake the muted red buttons with narrower outlines.

const PAPER := preload("res://graphics/ui/theme/dialogue_paper.tres")
const OUTPUT := "res://graphics/ui/theme/textures/"


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var fine_style := "--fine" in OS.get_cmdline_user_args()
	var surface := SubViewport.new()
	surface.transparent_bg = true
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(surface)

	var paper := ColorRect.new()
	var material := PAPER.duplicate() as ShaderMaterial
	var shader := Shader.new()
	# Save straight alpha so the theme can composite the texture over any backdrop.
	shader.code = PAPER.shader.code.replace("render_mode unshaded;", "render_mode unshaded, blend_disabled;")
	material.shader = shader
	paper.material = material
	surface.add_child(paper)

	var strokes := PAPER.get_shader_parameter("stroke_texture") as NoiseTexture2D
	if strokes.get_image() == null:
		await strokes.changed
	material.set_shader_parameter("stroke_texture", strokes)
	material.set_shader_parameter("outline_wobble", 0.0)
	var panel_profiles: Dictionary[String, Color] = {
		"panel": Color(0.125, 0.125, 0.125, 0.72),
		"opaque_panel": Color(0.125, 0.125, 0.125, 1.0),
		"dialog": Color(0.125, 0.125, 0.125, 0.95),
		"menu": Color(0.055, 0.09, 0.078, 0.88),
		"hud": Color(0.20, 0.21, 0.22, 0.87),
	}
	var control_profiles: Dictionary[String, Color] = {
		"button": Color(0.224, 0.224, 0.224, 0.90),
		"disabled": Color(0.141, 0.141, 0.141, 0.72),
		"focus": Color.TRANSPARENT,
		"hover": Color(0.32, 0.32, 0.32, 0.93),
		"pressed": Color(0.145, 0.145, 0.145, 0.93),
		"selected": Color(0.26, 0.23, 0.17),
	}
	if fine_style:
		control_profiles = {
			"button": Color(0.36, 0.19, 0.21, 0.96),
			"disabled": Color(0.22, 0.16, 0.17, 0.85),
			"focus": Color.TRANSPARENT,
			"hover": Color(0.45, 0.25, 0.26, 0.96),
			"pressed": Color(0.28, 0.13, 0.16, 0.98),
			"selected": Color(0.43, 0.20, 0.22),
		}
	var track_profiles: Dictionary[String, Color] = {
		"track": Color(0.10, 0.125, 0.125),
		"thumb": Color(0.55, 0.545, 0.50),
		"thumb_hover": Color(0.725, 0.70, 0.61),
		"fill": Color(0.875, 0.776, 0.545),
	}

	for profiles: Dictionary[String, Color] in [panel_profiles, control_profiles, track_profiles]:
		var is_panel := profiles == panel_profiles
		var is_track := profiles == track_profiles
		if fine_style and (is_panel or is_track):
			continue
		var extent := 82 if is_panel else 38
		surface.size = Vector2i(extent, extent)
		paper.size = Vector2(extent, extent)
		paper.set_instance_shader_parameter(&"panel_size", paper.size)
		var control_width := 1.0 if fine_style else 1.2
		var width := 2.0 if is_panel else (1.0 if is_track else control_width)
		var radius := 3.0 if is_panel else (1.0 if is_track else 2.0)
		material.set_shader_parameter("outline_width", width)
		material.set_shader_parameter("outline_pixel_snap", fine_style and not is_panel)
		material.set_shader_parameter("outline_corner_radius", radius)
		material.set_shader_parameter("outline_roughness", 0.95 if is_panel else 0.45)
		material.set_shader_parameter("hatch_spacing", 8.0 if is_panel else 5.0)
		material.set_shader_parameter("hatch_strength", 0.10 if is_panel else 0.075)
		material.set_shader_parameter("hatch_edge_softness", 0.25 if fine_style else 0.5)

		for variant in profiles:
			paper.color = profiles[variant]
			var ink := Color(0.90, 0.76, 0.55, 0.92 if is_panel else 0.76)
			if fine_style and variant != "focus":
				ink = Color(0.73, 0.64, 0.48, 1.0)
			elif variant == "focus" or variant == "hover" or variant == "selected":
				ink = Color(0.98, 0.85, 0.59, 1.0)
			elif variant == "disabled" or is_track:
				ink = Color(0.57, 0.49, 0.36, 0.60)
			material.set_shader_parameter("outline_color", ink)
			await process_frame
			await RenderingServer.frame_post_draw
			var image := surface.get_texture().get_image()
			image.fix_alpha_edges()
			var prefix := "paper_fine_" if fine_style else "paper_"
			var output_path := OUTPUT + prefix + variant + ".png"
			var result := image.save_png(output_path)
			if result != OK:
				push_error("Could not save %s (%s)" % [output_path, result])
				quit(1)
				return
			print("Saved ", output_path)
	quit()
