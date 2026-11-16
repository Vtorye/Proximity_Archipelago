class_name PixelCapture
extends RefCounted
## Capture the native window render and add any letterboxing around it.
static func from_viewport(viewport: Viewport, target: Vector2i) -> Image:
	var source: Image = viewport.get_texture().get_image()
	if not viewport is Window:
		# Virtual-resolution fixtures render into a fixed-size SubViewport.
		var factor := minf(float(target.x) / source.get_width(), float(target.y) / source.get_height())
		var fitted := Vector2i((Vector2(source.get_size()) * factor).round())
		source.resize(fitted.x, fitted.y, Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.BLACK)
	canvas.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), (target - source.get_size()) / 2)
	return canvas
