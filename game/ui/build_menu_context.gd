class_name BuildMenuContext
extends RefCounted
## Typed presentation context. Coordinates are in the overlay viewport, never map cells.
var controller: BuildController
var population: ColonyPopulation
var art: ArtCatalog
var cell: Vector2i
var anchor: Rect2
