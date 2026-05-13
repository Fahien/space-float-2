## Chapter: The Tank Becomes a Component
##
## A propellant tank used to be able to masquerade as its own rigid body. In the
## single-body vessel model, that would create a second physics authority and a
## joint where the ship only needs a mass ledger. `PropellantModel` is now the
## tank-shaped component that preserves the fuel story without splitting the
## craft into separate dynamic bodies.
##
## The component contributes an authored collision shape, dry container mass,
## and remaining propellant mass to `VesselRigidBody3D`. Engines draw fuel
## through `consume_propellant(...)`; the tank reports the actual amount burned,
## emits `mass_changed`, and asks the parent vessel to refresh total mass and
## center of mass.
##
## The class deliberately does not apply gravity, thrust, or drag. Those forces
## belong to the vessel root, which keeps the tank, engine, and future payloads
## moving as one compound body.
class_name PropellantModel

extends CollisionShape3D

## Emitted whenever dry or propellant mass changes and the vessel should refresh
## aggregate mass properties.
signal mass_changed

@export
## Dry mass of the propellant container, in kilograms.
var dry_mass: float = 0.0:
	set(p_value):
		dry_mass = maxf(p_value, 0.0)
		_notify_mass_changed()


@export
## Remaining propellant mass, in kilograms. Editing this reloads the tank to the
## chosen fuel load; runtime burn state is stored directly in this property.
var propellant_mass: float = 0.0:
	set(p_value):
		propellant_mass = maxf(p_value, 0.0)
		_notify_mass_changed()


## Returns the current total tank mass in kilograms.
func get_total_mass() -> float:
	return dry_mass + propellant_mass


## Returns the current propellant mass in kilograms.
func get_propellant_mass() -> float:
	return maxf(propellant_mass, 0.0)


## Consumes propellant for one simulation step.
## Returns the actual amount burned, which may be lower than requested when
## the tank reaches zero during the step.
func consume_propellant(delta: float, propellant_flow: float) -> float:
	if delta <= 0.0 or propellant_flow <= 0.0 or propellant_mass <= 0.0:
		return 0.0

	var propellant_consumed := minf(propellant_flow * delta, propellant_mass)
	propellant_mass -= propellant_consumed

	_notify_mass_changed()

	return propellant_consumed


## Notifies direct listeners and the parent vessel that the mass ledger changed.
func _notify_mass_changed() -> void:
	mass_changed.emit()
	var vessel = get_parent()
	if vessel != null and vessel.has_method("sync_mass_properties"):
		vessel.sync_mass_properties()
