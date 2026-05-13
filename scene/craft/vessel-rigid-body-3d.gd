## Chapter: The Vessel as One Body and One Ledger
##
## The LAMAE assembly once described a small spacecraft as a collection of
## dynamic parts joined together. That was useful while the pieces were being
## proven, but a flown craft needs one physical authority: one body that gravity
## accelerates, one ledger that changes as propellant burns, and one center of
## mass that shifts as components report their contribution.
##
## `VesselRigidBody3D` is that authority. Direct children that inherit
## `MassModel` form the mass ledger; scene instances may still use
## `CollisionShape3D` roots so Godot contributes their shapes to the compound
## rigid body. Engines are the active subset of those components. Each physics
## step, the vessel asks installed `EngineModel` children for their resolved
## force and application offset, then sends those forces into the same Jolt body
## that handles contacts and impulses.
##
## The design keeps authored scenes readable. Engine and tank scenes still carry
## their visuals, collision shapes, and resource tuning, but they no longer form
## independent rigid bodies or advertise mass through loose method checks. Drag
## enters as an optional vessel resource that uses planet-owned air density;
## staging and payload logic should follow the same `MassModel` contract instead
## of reintroducing joints for ordinary vessel structure.
class_name VesselRigidBody3D

extends GravityRigidBody3D

## Emitted after the vessel has recomputed aggregate mass and center of mass.
signal mass_properties_changed

@export_custom(PROPERTY_HINT_NONE, "suffix: kg")
## Lower bound that keeps the physics body valid if components report zero mass.
var minimum_mass: float = 0.000001

@export
## Optional aerodynamic tuning for this vessel.
##
## A null resource means the vessel flies without drag. When present and enabled,
## the vessel asks its current primary celestial body for air density and applies
## the resulting drag as a central force.
var aerodynamics_model: AerodynamicsModel = null


func _ready() -> void:
	_connect_component_signals()
	sync_mass_properties()


func _integrate_forces(p_state: PhysicsDirectBodyState3D) -> void:
	sync_mass_properties()
	CelestialBodySystem.apply_gravity(self, p_state)
	_apply_component_forces(p_state)
	_apply_aerodynamics_forces(p_state)
	sync_mass_properties()


## Returns the current aggregate mass from direct child components.
func get_total_mass() -> float:
	var total_mass := 0.0
	for component in get_mass_components():
		total_mass += _get_component_mass(component)
	return total_mass


## Returns direct child `MassModel` components that participate in the vessel
## mass ledger.
func get_mass_components() -> Array[MassModel]:
	var components: Array[MassModel] = []
	for child in get_children():
		var component := child as MassModel
		if component != null:
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
		if not component.mass_changed.is_connected(_on_component_mass_changed):
			component.mass_changed.connect(_on_component_mass_changed)


func _on_component_mass_changed() -> void:
	sync_mass_properties()


## Applies force contributions from installed engine components.
##
## Non-engine mass components still affect collision and aggregate mass, but
## they do not create thrust or torque.
func _apply_component_forces(state: PhysicsDirectBodyState3D) -> void:
	for child in get_children():
		var component := child as EngineModel
		if component == null:
			continue

		var force: Vector3 = component.resolve_vessel_force(state.step, state.transform)
		if force.length_squared() <= 0.0:
			continue

		var offset := component.get_vessel_force_offset(state.transform)

		state.apply_force(force, offset)


func _apply_aerodynamics_forces(p_state: PhysicsDirectBodyState3D) -> void:
	if (
		aerodynamics_model == null
		or not aerodynamics_model.enabled
		or current_primary == null
		or not is_instance_valid(current_primary)
	):
		return

	var air_density := current_primary.get_air_density_at(p_state.transform.origin)
	if air_density <= 0.0:
		return

	var wind_velocity := Vector3.ZERO
	var relative_air_velocity := p_state.linear_velocity - wind_velocity
	var drag: Vector3 = aerodynamics_model.get_drag_force(relative_air_velocity, air_density)
	if drag.length_squared() <= 0.0:
		return

	p_state.apply_central_force(drag)


func _get_component_mass(component: MassModel) -> float:
	var component_mass: float = component.get_total_mass()
	return maxf(component_mass, 0.0)
