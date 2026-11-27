class_name Screen
extends Control

## Data handed in by Router.goto(). Subclasses read this in _ready()
var payload: Variant = null

## Whether the pause key does anything while this screen is active
@export var pausable: bool = false

## Called after the screen is added and the fade-in begins
func on_focus() -> void:
	pass

## Called before the screen is destroyed (on navigation away)
func on_blur() -> void:
	pass

## Veto navigation. Return false to block leaving (e.g. unsaved changes)
func can_leave() -> bool:
	return true
