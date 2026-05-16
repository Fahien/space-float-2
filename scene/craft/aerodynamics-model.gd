## Chapter: The Drag Law Becomes a Vessel Resource
##
## The first launch harness treated drag as a static calculation with all vehicle
## numbers passed by the caller. The active vessel path needs something slightly
## more like a flight article: a small Resource that an authored craft can carry
## in its scene, inspect in the editor, and disable without changing the planet
## or engine components around it.
##
## `AerodynamicsModel` still keeps the boundary narrow. Celestial bodies own the
## atmosphere and return air density. The vessel resolves relative air velocity.
## This resource supplies the vehicle-side coefficients and evaluates the
## quadratic drag law. It does not model lift, wind, heating, Mach effects, or
## shape-dependent attitude changes; those belong to later aerodynamic chapters
## once the single-body vessel path is stable.
class_name AerodynamicsModel

extends Resource

@export
## Enables drag for vessels that reference this resource.
var enabled := true

@export
## Dimensionless drag coefficient used by the quadratic drag equation.
var drag_coefficient := 0.47

@export_custom(PROPERTY_HINT_NONE, "suffix: m²")
## Reference area exposed to the airflow, in square meters.
var reference_area := 1.0

## Returns quadratic drag opposite the relative air velocity.
##
## Callers provide density from the local environment and velocity relative to
## the air mass. Disabled or physically unusable configurations return zero so
## optional vessel resources do not need special handling at every call site.
func get_drag_force(
	relative_air_velocity: Vector3,
	air_density: float,
) -> Vector3:
	if not enabled or air_density <= 0.0 or drag_coefficient <= 0.0 or reference_area <= 0.0:
		return Vector3.ZERO

	var speed := relative_air_velocity.length()
	if speed <= 0.000001:
		return Vector3.ZERO

	var drag_magnitude := 0.5 * drag_coefficient * air_density * speed * speed * reference_area
	return -relative_air_velocity.normalized() * drag_magnitude
