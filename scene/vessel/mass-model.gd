## Mutable vessel mass state for the standalone launch harness.
##
## This class owns:
## - dry mass
## - remaining propellant mass
## - the rules for reducing propellant over time
##
## It does not know anything about thrust direction or scene nodes.

class_name MassModel

extends Resource

## Non-consumable vessel mass in kilograms.
##
## Editor role:
## - authored mass baseline shared by the vessel scene
##
## Runtime role:
## - duplicated per vessel instance by `VesselState.configure_models(...)`
## - contributes to the rigid body's total mass every physics step
##
## Safety:
## - changing this in the editor is safe
## - changing it during runtime only affects instances that re-read or rebuild
##   their model state
@export var dry_mass: float = 1000.0

## Initial consumable propellant mass in kilograms.
##
## Editor role:
## - defines how much fuel a newly instantiated vessel starts with
##
## Runtime role:
## - duplicated into per-instance mutable state
## - decremented by propulsion usage until thrust cuts off at zero
##
## Interaction:
## - used together with `PropulsionModel.max_propellant_flow_kg_per_s`
## - total liftoff time depends on both this value and throttle usage
@export var propellant_mass: float = 1000.0


## Returns the current total mass of the vessel in kg.
func get_mass() -> float:
	return dry_mass + propellant_mass


## Returns the current propellant mass in kg.
func get_propellant_mass() -> float:
	return propellant_mass


## Consumes propellant for one simulation step.
## Returns the actual amount burned, which may be lower than requested when
## the tank reaches zero during the step.
func consume_propellant(delta: float, propellant_flow: float) -> float:
	if delta <= 0.0 or propellant_flow <= 0.0:
		return 0.0

	var propellant_consumed = propellant_flow * delta
	propellant_consumed = min(propellant_consumed, propellant_mass)
	propellant_mass -= propellant_consumed
	return propellant_consumed
