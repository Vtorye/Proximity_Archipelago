class_name BuildCatalog
extends Resource
## Starting availability and palette categories are authored independently.
@export var options: Array[BuildOption] = []
## Categories can also list options unlocked by later tasks or game modes.
@export var categories: Array[BuildCategory] = []
