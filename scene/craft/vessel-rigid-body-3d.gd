## Chapter: The Vessel as One Body
##
## The LAMAE assembly once described a small spacecraft as a collection of
## dynamic parts joined together. That was useful for proving the pieces, but a
## flown craft needs one physical authority: one body that gravity accelerates,
## one mass that changes as propellant burns, and one center of mass that shifts
## as components report their contribution.
##
## `VesselRigidBody3D` is that authority. Direct child components provide
## `CollisionShape3D` shapes to the compound body and expose small contracts such
## as `get_total_mass()`, `resolve_vessel_force(...)`, and
## `get_vessel_force_offset(...)`. The vessel root owns integration, applies
## celestial gravity once, gathers engine forces, and sends those forces into the
## same Jolt body that handles contacts and impulses.
##
## The design keeps authored scenes readable. Engine and tank scenes still carry
## their visuals, collision shapes, and resource tuning, but they no longer form
## independent rigid bodies. Future atmosphere, drag, staging, and payload logic
## should extend this root-and-component contract instead of reintroducing joints
## for ordinary vessel structure.
class_name VesselRigidBody3D

extends GravityRigidBody3D

## Emitted after the vessel has recomputed aggregate mass and center of mass.
signal mass_properties_changed

@export_custom(PROPERTY_HINT_NONE, "suffix: kg")
## Lower bound that keeps the physics body valid if components report zero mass.
var minimum_mass: float = 0.000001


func _ready() -> void:
	_connect_component_signals()
	sync_mass_properties()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	sync_mass_properties()
	CelestialBodySystem.apply_gravity(self , state)
	_apply_component_forces(state)
	sync_mass_properties()


## Returns the current aggregate mass from direct child components.
func get_total_mass() -> float:
	var total_mass := 0.0
	for component in get_mass_components():
		total_mass += _get_component_mass(component)
	return total_mass


## Returns direct child components that participate in the vessel mass ledger.
func get_mass_components() -> Array[Node3D]:
	var components: Array[Node3D] = []
	for child in get_children():
		var component := child as Node3D
		if component == null:
			continue
		if component.has_method("get_total_mass"):
			components.append(component)
	return components


## Computes the component-weighted center of mass in vessel-local coordinates.
func get_center_of_mass_from_components() -> Vector3:
	var weighted_position := Vector3.ZERO
	var total_mass := 0.0

	for component in get_mass_components():
		var component_mass := _get_component_mass(component)
		if component_mass <= 0.0:
			continue

		weighted_position += component.transform.origin * component_mass
		total_mass += component_mass

	if total_mass <= 0.0:
		return Vector3.ZERO
	return weighted_position / total_mass


## Pushes aggregate mass and local center of mass into Godot's rigid body state.
func sync_mass_properties() -> void:
	mass = maxf(get_total_mass(), minimum_mass)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = get_center_of_mass_from_components()
	mass_properties_changed.emit()


func _connect_component_signals() -> void:
	for component in get_mass_components():
		if (
			component.has_signal("mass_changed")
			and not component.is_connected("mass_changed", _on_component_mass_changed)
		):
			component.connect("mass_changed", _on_component_mass_changed)


func _on_component_mass_changed() -> void:
	sync_mass_properties()


func _apply_component_forces(state: PhysicsDirectBodyState3D) -> void:
	for child in get_children():
		var component := child as Node3D
		if component == null or not component.has_method("resolve_vessel_force"):
			continue

		var force: Vector3 = component.resolve_vessel_force(state.step, state.transform)
		if force.length_squared() <= 0.0:
			continue

		var offset := Vector3.ZERO
		if component.has_method("get_vessel_force_offset"):
			offset = component.get_vessel_force_offset(state.transform)

		state.apply_force(force, offset)


func _get_component_mass(component: Node3D) -> float:
	var component_mass: float = component.get_total_mass()
	return maxf(component_mass, 0.0)
