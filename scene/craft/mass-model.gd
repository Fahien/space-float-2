## Chapter: The Mass Ledger
##
## A vessel assembled from tanks, engines, and later payloads needs more than a
## visual hierarchy. Each component must tell the craft how much inertia it
## brings, when that number changes, and which parent body should recompute the
## total. Earlier prototypes let every part improvise that contract. `MassModel`
## makes it explicit.
##
## The class is deliberately small. It does not move through space, integrate
## forces, or decide whether a scene root is also a `CollisionShape3D`. Instead,
## it defines the common ledger used by `VesselRigidBody3D`: direct child
## components report mass through `get_total_mass()`, emit `mass_changed` when
## their contribution changes, and ask the immediate parent vessel to refresh
## aggregate mass and center of mass.
##
## This base type is the frontier between authored hardware and flight
## authority. Engine and tank scenes may still carry meshes, selection nodes,
## collision shapes, and tuning resources, but they join the simulation as mass
## components under one vessel body rather than as separate physics owners.
class_name MassModel

extends CollisionShape3D

## Emitted after this component changes dry mass, propellant, or another mass
## contribution that affects the parent vessel's aggregate properties.
signal mass_changed


## Notifies listeners and asks the immediate parent vessel to refresh its mass
## ledger when this component is installed directly under a vessel body.
func notify_mass_changed() -> void:
	mass_changed.emit()
	var vessel := get_vessel_body()
	if vessel != null:
		vessel.sync_mass_properties()


## Returns the immediate parent vessel, or null when the component is being
## edited, previewed, or tested outside a complete craft scene.
func get_vessel_body() -> VesselRigidBody3D:
	var parent = get_parent()
	if parent is VesselRigidBody3D:
		return parent
	return null


## Returns the component's current mass in kilograms.
##
## Subclasses override this with hardware, propellant, cargo, or staging mass.
## The zero default keeps placeholder components from changing vessel physics.
func get_total_mass() -> float:
	return 0.0
