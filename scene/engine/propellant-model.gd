## Node-backed mutable propellant state for a standalone engine assembly.
##
## This is a `RigidBody3D` so the tank can exist as an authored scene node. The
## resource-only vessel harness uses `MassModel` instead.
@tool
class_name PropellantModel

extends RigidBody3D


@export
## Dry mass of the propellant container, in kilograms.
var dry_mass: float = 0.0:
	set(p_value):
		dry_mass = maxf(p_value, 0.0)
		mass = dry_mass + initial_propellant_mass


@export
## Initial propellant mass, in kilograms. Editing this reloads the tank to its
## initial wet mass; runtime burn state is represented by `mass - dry_mass`.
var initial_propellant_mass: float = 0.0:
	set(p_value):
		initial_propellant_mass = maxf(p_value, 0.0)
		mass = dry_mass + initial_propellant_mass


## Returns the current total tank mass in kilograms.
func get_total_mass() -> float:
	return mass


## Returns the current propellant mass in kilograms.
func get_propellant_mass() -> float:
	return maxf(mass - dry_mass, 0.0)


## Consumes propellant for one simulation step.
## Returns the actual amount burned, which may be lower than requested when
## the tank reaches zero during the step.
func consume_propellant(delta: float, propellant_flow: float) -> float:
	var propellant_mass := get_propellant_mass()
	if delta <= 0.0 or propellant_flow <= 0.0 or propellant_mass <= 0.0:
		return 0.0

	var propellant_consumed := minf(propellant_flow * delta, propellant_mass)
	mass -= propellant_consumed
	return propellant_consumed
