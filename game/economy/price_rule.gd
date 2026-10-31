class_name PriceRule
extends Resource
@export var event: GameEvents.Kind = GameEvents.Kind.BUILDING_BUILT
@export var subject: StringName
## Empty applies to every resource in the price.
@export var resource: ResourceType
@export_enum("Multiply", "Add") var operation := 0
@export var value := 1.2
