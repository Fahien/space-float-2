## Rigid-body adapter for a standalone engine assembly.
##
## `PropulsionModel` provides immutable tuning, while `PropellantModel` owns
## the mutable tank state consumed by this engine at runtime.
class_name EngineModel

extends RigidBody3D

@export
## Mutable propellant source consumed by this engine instance.
var propellant_model: PropellantModel = null:
	set(p_model):
		propellant_model = p_model
		update_configuration_warnings()

@export
## Thrust, flow, and actuator tuning for this engine instance.
var propulsion_model: PropulsionModel = PropulsionModel.new():
	set(p_model):
		propulsion_model = p_model
		update_configuration_warnings()

@export
var plume: MeshInstance3D = null:
	set(p_plume):
		plume = p_plume
		update_configuration_warnings()

## Current throttle setting, 0.0 (off) to 1.0 (full).
var _throttle: float = 0.0

## Normalized actuator command for pitch and yaw deflection.
var _gimbal_command: Vector2 = Vector2.ZERO

## Actual slewed gimbal angles in radians for pitch and yaw.
var _gimbal_angles: Vector2 = Vector2.ZERO


func _ready() -> void:
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if propellant_model == null:
		warnings.append("Propellant model is not set.")
	if propulsion_model == null:
		warnings.append("Propulsion model is not set.")
	if plume == null:
		warnings.append("Plume mesh is not set.")
	return warnings


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	resolve_gimbal_step(state.step)
	var thrust_magnitude := resolve_propulsion_step(state.step)
	if plume != null:
		plume.visible = thrust_magnitude > 0.0
	if thrust_magnitude > 0.0:
		var thrust_dir := (
			state.transform.basis
			* get_actual_thrust_direction_local()
		).normalized()
		var thrust := thrust_dir * thrust_magnitude
		state.apply_force(thrust)


func get_propellant_mass() -> float:
	if propellant_model == null:
		return 0.0
	return propellant_model.get_propellant_mass()


func set_throttle(p_throttle: float) -> void:
	_throttle = clampf(p_throttle, 0.0, 1.0)
	if get_throttle() > 0.0:
		sleeping = false

func get_throttle() -> float:
	return _throttle


## Desired actuator command in normalized pitch/yaw space.
func set_gimbal_command(p_gimbal_command: Vector2) -> void:
	_gimbal_command = Vector2(
		clampf(p_gimbal_command.x, -1.0, 1.0),
		clampf(p_gimbal_command.y, -1.0, 1.0)
	)


func get_gimbal_command() -> Vector2:
	return _gimbal_command


func get_gimbal_angles() -> Vector2:
	return _gimbal_angles


func get_gimbal_angles_degrees() -> Vector2:
	return Vector2(
		rad_to_deg(_gimbal_angles.x),
		rad_to_deg(_gimbal_angles.y)
	)


## Returns the currently requested thrust before fuel-availability limits are
## applied for a specific simulation step.
func get_thrust_magnitude() -> float:
	return propulsion_model.get_thrust_magnitude(_throttle)


## Resolves one gimbal-actuator step and returns the actual local gimbal basis.
##
## The harness currently recenters to neutral whenever the pilot is not
## commanding deflection, so released inputs do not leave the engine canted.
func resolve_gimbal_step(delta: float) -> Basis:
	if delta <= 0.0 or propulsion_model == null:
		return get_actual_gimbal_basis_local()

	var target_angles := propulsion_model.get_gimbal_target_angles(
		Vector3(_gimbal_command.x, _gimbal_command.y, 0.0)
	)
	var max_step := propulsion_model.get_gimbal_slew_rate_radians() * delta
	if max_step <= 0.0:
		_gimbal_angles = Vector2(target_angles.x, target_angles.y)
	else:
		_gimbal_angles.x = move_toward(_gimbal_angles.x, target_angles.x, max_step)
		_gimbal_angles.y = move_toward(_gimbal_angles.y, target_angles.y, max_step)
	return get_actual_gimbal_basis_local()


## Returns the current local actuator rotation relative to the authored mount.
func get_actual_gimbal_basis_local() -> Basis:
	var gimbal_transform := Transform3D.IDENTITY
	gimbal_transform = gimbal_transform.rotated_local(Vector3.RIGHT, _gimbal_angles.x)
	gimbal_transform = gimbal_transform.rotated_local(Vector3.BACK, _gimbal_angles.y)
	return gimbal_transform.basis.orthonormalized()


## Returns the current thrust axis relative to the neutral mount frame.
func get_actual_thrust_direction_local() -> Vector3:
	return (get_actual_gimbal_basis_local() * Vector3.UP).normalized()


## Resolves one propulsion step, consuming propellant and returning the thrust
## magnitude that should be applied during that step.
##
## When the tank runs dry partway through the step, the returned thrust is
## scaled by the fraction of requested propellant that was actually available.
func resolve_propulsion_step(delta: float) -> float:
	if (
		delta <= 0.0
		or _throttle <= 0.0
		or propulsion_model == null
		or propellant_model == null
	):
		return 0.0

	var requested_flow := propulsion_model.get_propellant_flow(_throttle)
	if requested_flow <= 0.0:
		return 0.0

	var requested_burn := requested_flow * delta
	var actual_burn := propellant_model.consume_propellant(delta, requested_flow)
	if requested_burn <= 0.0 or actual_burn <= 0.0:
		return 0.0

	var burn_fraction := actual_burn / requested_burn
	return propulsion_model.get_thrust_magnitude(_throttle) * burn_fraction
