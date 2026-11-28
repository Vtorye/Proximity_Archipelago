@tool
extends AspectRatioContainer

## The container uses this texture's proportions when fitting the image.
@export var texture: Texture2D:
	set(value):
		if texture != null:
			texture.changed.disconnect(_update_image)
		texture = value
		if texture != null:
			texture.changed.connect(_update_image)
		_update_image()

@onready var _image: TextureRect = %Image

func _ready() -> void:
	_update_image()

func _update_image() -> void:
	if _image == null:
		return
	_image.texture = texture
	if texture != null and texture.get_height() > 0:
		ratio = float(texture.get_width()) / texture.get_height()
