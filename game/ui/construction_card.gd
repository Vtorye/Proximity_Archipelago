class_name ConstructionCard
extends Button

@onready var _image: TextureRect = %Image
@onready var _caption: Label = %Caption

func configure(option: BuildOption, art: ArtCatalog) -> void:
	_caption.text = option.display_name
	_image.texture = art.build_icon(option)
	tooltip_text = option.display_name
