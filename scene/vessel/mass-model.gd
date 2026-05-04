## Mutable vessel mass state for the standalone launch harness.
##
## `VesselState` duplicates this resource per vessel instance, then consumes
## propellant from that private copy during physics integration. Node-based
## propellant tanks use `PropellantModel` instead.
class_name MassModel

extends Resource

## Non-consumable vessel mass in kilograms.
@export var dry_mass: float = 1000.0

## Initial consumable propellant mass in kilograms.
@export var propellant_mass: float = 1000.0


## Returns the current total mass of the vessel in kilograms.
func get_mass() -> float:
	return dry_mass + propellant_mass


## Returns the current propellant mass in kilograms.
func get_propellant_mass() -> float:
	return propellant_mass


## Consumes propellant for one simulation step.
## Returns the actual amount burned, which may be lower than requested when the
## tank reaches zero during the step.
func consume_propellant(delta: float, propellant_flow: float) -> float:
	if delta <= 0.0 or propellant_flow <= 0.0:
		return 0.0

	var propellant_consumed := minf(propellant_flow * delta, propellant_mass)
	propellant_mass -= propellant_consumed
	return propellant_consumed
