## Authoritative vessel state for the simulation layer.
##
## This is a pure data object with no scene dependency. In the current harness
## phase it owns only propulsion-related mutable state:
## - throttle
## - mass / propellant bookkeeping
## - the resolved thrust magnitude for one step
##
## Full translational and rotational motion still comes from Godot rigid-body
## integration in `VesselModel`. That split is intentional for the prototype:
## it extracts fuel/thrust state now without claiming that the harness already
## owns a full custom flight integrator.
class_name VesselState

extends RefCounted

const GIMBAL_STRENGTH := 10000.0

## Global position in meters, in the simulation's reference frame.
var position: Vector3 = Vector3.ZERO

## Global velocity in m/s.
var velocity: Vector3 = Vector3.ZERO

## Orientation basis. Kept as Basis (not Quaternion) for direct compatibility
## with Godot Transform3D when synchronizing the scene proxy.
var rotation: Basis = Basis.IDENTITY

## Angular velocity in rad/s, in world-space.
var angular_velocity: Vector3 = Vector3.ZERO

## Current throttle setting, 0.0 (off) to 1.0 (full).
var _throttle: float = 0.0

## Normalized actuator command for pitch, yaw, and roll deflection.
var _gimbal_command: Vector3 = Vector3.ZERO

## Actual slewed gimbal angles in radians for pitch, yaw, and roll.
var _gimbal_angles: Vector3 = Vector3.ZERO

## Mutable mass state for this vessel instance.
var _mass_model: MassModel = MassModel.new()

## Propulsion tuning for this vessel instance.
var _propulsion_model: PropulsionModel = PropulsionModel.new()


## Replace the default models with authored harness tuning.
## Mutable resource state is duplicated so each vessel instance owns its own
## propellant tank even if the scene reuses the same resource asset.
func configure_models(
	p_mass_model: MassModel,
	p_propulsion_model: PropulsionModel
) -> void:
	if p_mass_model != null:
		_mass_model = p_mass_model.duplicate(true) as MassModel
	if p_propulsion_model != null:
		_propulsion_model = p_propulsion_model.duplicate(true) as PropulsionModel


func get_mass() -> float:
	return _mass_model.get_mass()


func get_propellant_mass() -> float:
	return _mass_model.get_propellant_mass()


func set_throttle(p_throttle: float) -> void:
	_throttle = clampf(p_throttle, 0.0, 1.0)


func get_throttle() -> float:
	return _throttle


## Desired actuator command in normalized pitch/yaw/roll space.
func set_gimbal_command(p_gimbal_command: Vector3) -> void:
	_gimbal_command = Vector3(
		clampf(p_gimbal_command.x, -1.0, 1.0),
		clampf(p_gimbal_command.y, -1.0, 1.0),
		clampf(p_gimbal_command.z, -1.0, 1.0)
	)


func get_gimbal_command() -> Vector3:
	return _gimbal_command


func get_gimbal_angles() -> Vector3:
	return _gimbal_angles


func get_gimbal_angles_degrees() -> Vector3:
	return Vector3(
		rad_to_deg(_gimbal_angles.x),
		rad_to_deg(_gimbal_angles.y),
		rad_to_deg(_gimbal_angles.z)
	)


## Returns the currently requested thrust before fuel-availability limits are
## applied for a specific simulation step.
func get_thrust_magnitude() -> float:
	return _propulsion_model.get_thrust_magnitude(_throttle)


## Resolves one gimbal-actuator step and returns the actual local gimbal basis.
##
## The harness currently recenters to neutral whenever the pilot is not
## commanding deflection, so released inputs do not leave the engine canted.
func resolve_gimbal_step(delta: float) -> Basis:
	if delta <= 0.0:
		return get_actual_gimbal_basis_local()

	var target_angles := _propulsion_model.get_gimbal_target_angles(_gimbal_command)
	var max_step := _propulsion_model.get_gimbal_slew_rate_radians() * delta
	if max_step <= 0.0:
		_gimbal_angles = target_angles
	else:
		_gimbal_angles.x = move_toward(_gimbal_angles.x, target_angles.x, max_step)
		_gimbal_angles.y = move_toward(_gimbal_angles.y, target_angles.y, max_step)
		_gimbal_angles.z = move_toward(_gimbal_angles.z, target_angles.z, max_step)
	return get_actual_gimbal_basis_local()


## Returns the current local actuator rotation relative to the authored mount.
func get_actual_gimbal_basis_local() -> Basis:
	var gimbal_transform := Transform3D.IDENTITY
	gimbal_transform = gimbal_transform.rotated_local(Vector3.RIGHT, _gimbal_angles.x)
	gimbal_transform = gimbal_transform.rotated_local(Vector3.BACK, _gimbal_angles.y)
	gimbal_transform = gimbal_transform.rotated_local(Vector3.UP, _gimbal_angles.z)
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
	if delta <= 0.0 or _throttle <= 0.0:
		return 0.0

	var requested_flow := _propulsion_model.get_propellant_flow(_throttle)
	if requested_flow <= 0.0:
		return 0.0

	var requested_burn := requested_flow * delta
	var actual_burn := _mass_model.consume_propellant(delta, requested_flow)
	if requested_burn <= 0.0 or actual_burn <= 0.0:
		return 0.0

	var burn_fraction := actual_burn / requested_burn
	return _propulsion_model.get_thrust_magnitude(_throttle) * burn_fraction
