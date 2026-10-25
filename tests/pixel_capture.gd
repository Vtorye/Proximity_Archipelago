class_name PixelCapture
extends RefCounted
## Match the project's integer viewport stretch, including physical window letterboxing.
static func from_viewport(viewport: Viewport, target: Vector2i) -> Image:
	var source: Image = viewport.get_texture().get_image()
	var factor: int = maxi(1, mini(target.x / source.get_width(), target.y / source.get_height()))
	source.resize(source.get_width() * factor, source.get_height() * factor, Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.BLACK)
	canvas.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), (target - source.get_size()) / 2)
	return canvas
