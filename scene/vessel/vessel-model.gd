## Godot rigid-body adapter for the standalone launch harness.
##
## Responsibilities:
## - sample authored force-anchor geometry from the rigid-body subtree
## - translate scalar vessel state into scene-space force application
## - apply gravity, drag, and thrust in `_integrate_forces(...)`
## - expose debug-facing cached forces for the harness HUD
##
## `VesselState` owns throttle and mutable propulsion state. `VesselModel`
## remains the engine-facing bridge that turns that state into force calls.
class_name VesselModel

extends RigidBody3D

## Mutable propulsion-related state for this vessel instance.
var _state := VesselState.new()

## Authored mass/propellant setup for this vessel body.
##
## Editor role:
## - lets the vessel scene choose the mass model that should be duplicated into
##   per-instance mutable simulation state
##
## Runtime role:
## - read during `_ready()` and copied into `_state`
## - affects simulation mass only; it does not own any render behavior
@export var mass_model: MassModel = MassModel.new()

## Authored propulsion and actuator tuning for this vessel body.
##
## This is the inspector-facing bridge between authored vessel scenes and the
## runtime `VesselState` propulsion logic.
@export var propulsion_model: PropulsionModel = PropulsionModel.new()

## Physics-only mount that defines where thrust is applied in the body frame.
## This must stay under the rigid body; visible exhaust now lives in the render
## subtree instead.
@onready var _thruster_mount: GPUParticles3D = $Model/EnginePivot/Thruster

## Thruster-mount offset in the vessel's local body frame.
var _thruster_mount_local_offset: Vector3 = Vector3.ZERO

## Neutral thruster-mount basis in the vessel's local body frame.
var _thruster_mount_local_basis: Basis = Basis.IDENTITY

## Approximate aerodynamic reference area in square meters.
##
## Frame and meaning:
## - scalar simulation property, not tied to a specific node transform
## - used by the current first-order drag approximation as the exposed area to
##   airflow
##
## Runtime role:
## - affects drag magnitude only
## - safe to tune in the editor; changing it at runtime changes subsequent drag
##   calculations immediately
@export var reference_area_m2: float = 1.0

## Lumped drag coefficient for the current first-order drag approximation.
##
## This is dimensionless simulation tuning. It is intentionally exposed here so
## the authored vessel body can carry its own aerodynamic placeholder values.
@export var drag_coefficient: float = 0.47

## Atmosphere is static for now. Keeping wind explicit preserves the API for
## future extensions without changing the drag call contract again.
##
## Frame:
## - scene-space meters per second in the current harness
##
## Runtime role:
## - subtracted from body velocity before drag is computed
## - currently simulation-only; there is no visual wind system tied to it
@export var wind_velocity: Vector3 = Vector3.ZERO

## Latest gravity acceleration resolved from the current planet model.
var _gravity: Vector3 = Vector3.ZERO

## Cached gravity force for HUD/debug presentation.
var _gravity_force: Vector3 = Vector3.ZERO

## Cached thrust force for HUD/debug presentation.
var _thrust: Vector3 = Vector3.ZERO

## Cached drag force for HUD/debug presentation.
var _drag: Vector3 = Vector3.ZERO

## Whether the most recent physics step produced non-zero thrust. This is kept
## on the engine-facing adapter so render seams can mirror exhaust state without
## turning `VesselState` into a presentation contract.
var _thruster_active: bool = false

## Environment model used to resolve simulation-space gravity and altitude.
var _planet_model: CelestialBodyModel = null

@onready var _velocity_vector := $Debug/VelocityVector
@onready var _thrust_vector := $Debug/ThrustVector
@onready var _torque_vector := $Debug/TorqueVector
@onready var _gravity_vector := $Debug/GravityVector

func _ready() -> void:
	_state.configure_models(mass_model, propulsion_model)
	mass = _state.get_mass()
	_thruster_mount_local_offset = _thruster_mount.transform.origin
	_thruster_mount_local_basis = _thruster_mount.transform.basis.orthonormalized()


func get_custom_gravity() -> Vector3:
	return _gravity


func get_gravity_force() -> Vector3:
	return _gravity_force


func set_throttle(p_throttle: float) -> void:
	_state.set_throttle(p_throttle)
	if _state.get_throttle() > 0.0:
		sleeping = false


func set_gimbal_command(p_gimbal_command: Vector3) -> void:
	_state.set_gimbal_command(p_gimbal_command)
	if (
		p_gimbal_command.length_squared() > 0.0
		or _state.get_gimbal_angles().length_squared() > 0.0
	):
		sleeping = false


func _process(_delta: float) -> void:
	# Cache render-facing exhaust state from the last applied force result, not
	# from the requested throttle, so fuel starvation visibly cuts off.
	_thruster_active = _thrust.length_squared() > 0.0
	_thruster_mount.emitting = _thruster_active
	
	_velocity_vector.vector = _state.velocity
	_thrust_vector.vector = _thrust
	_gravity_vector.vector = _gravity_force

func get_throttle() -> float:
	return _state.get_throttle()


func get_thrust() -> Vector3:
	return _thrust


func get_gimbal_command() -> Vector3:
	return _state.get_gimbal_command()


func get_gimbal_angles() -> Vector3:
	return _state.get_gimbal_angles()


func get_gimbal_angles_degrees() -> Vector3:
	return _state.get_gimbal_angles_degrees()


func get_thruster_gimbal_basis_local() -> Basis:
	return _state.get_actual_gimbal_basis_local()


func get_actual_thrust_direction_local() -> Vector3:
	return (
		_thruster_mount_local_basis
		* Vector3.UP
	).normalized()


func get_propellant_mass() -> float:
	return _state.get_propellant_mass()


func get_drag() -> Vector3:
	return _drag


func is_thruster_active() -> bool:
	return _thruster_active


## Injects the environment model used by the standalone launch harness.
func set_planet_model(p_planet_model: CelestialBodyModel) -> void:
	_planet_model = p_planet_model


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_state.position = state.transform.origin
	_state.velocity = state.linear_velocity
	_state.rotation = state.transform.basis
	_state.angular_velocity = state.angular_velocity

	var world_torque = state.transform.basis * _state.get_gimbal_angles()
	_torque_vector.vector =_state.get_gimbal_angles()
	state.apply_torque(world_torque)
	var thrust_magnitude := _state.resolve_propulsion_step(state.step)
	var current_mass := _state.get_mass()
	mass = current_mass

	var body_position := state.transform.origin
	var body_velocity := state.linear_velocity

	if _planet_model != null:
		# Planet queries live in simulation space, but Godot force application
		# still happens in scene space. Once the frame can rotate, gravity
		# must be brought back through the frame instead of being treated as if
		# the two spaces were always axis-aligned.
		var gravity_simulation: Vector3 = _planet_model.get_gravity_at(body_position)
		_gravity = gravity_simulation
		_gravity_force = _gravity * current_mass
		state.apply_central_force(_gravity_force)

		var altitude_m := _planet_model.get_altitude_at(body_position)
		var air_density := AtmosphereModel.get_density_at(altitude_m)
		var relative_air_velocity := body_velocity - wind_velocity
		_drag = AerodynamicsModel.get_drag_force(
			relative_air_velocity,
			air_density,
			drag_coefficient,
			reference_area_m2
		)
		state.apply_central_force(_drag)
	else:
		_gravity = Vector3.ZERO
		_gravity_force = Vector3.ZERO
		_drag = Vector3.ZERO

	if thrust_magnitude > 0.0:
		var thrust_dir := (
			state.transform.basis
			* get_actual_thrust_direction_local()
		).normalized()
		_thrust = thrust_dir * thrust_magnitude
		var offset = state.transform.basis * _thruster_mount_local_offset
		state.apply_force(_thrust, offset)
	else:
		_thrust = Vector3.ZERO
