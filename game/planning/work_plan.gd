class_name WorkPlan
extends RefCounted
## A complete feasible sortie, including its return and reserved next meal.
var workplace: Workplace
var outward: Route
var job_cell: Vector2i
var home_cell: Vector2i
var estimated_energy: float
var navigation_revision: int
var waiting_for_slot := false
