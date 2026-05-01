## Pure aerodynamic helper for the launch harness.
##
## This class deliberately owns only the drag equation. Callers must provide
## the already-resolved environment and vehicle inputs so the force contract
## stays explicit and testable.

class_name AerodynamicsModel

extends RefCounted


## Returns quadratic drag opposite the relative air velocity.
static func get_drag_force(
	relative_air_velocity: Vector3,
	air_density: float,
	drag_coefficient: float,
	reference_area_m2: float
) -> Vector3:
	var speed := relative_air_velocity.length()
	if speed <= 0.000001:
		return Vector3.ZERO
	var drag_magnitude = 0.5 * drag_coefficient * air_density * speed * speed * reference_area_m2
	return -relative_air_velocity.normalized() * drag_magnitude
