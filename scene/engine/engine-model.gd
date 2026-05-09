## Rigid-body adapter for a standalone engine assembly.
##
## `PropulsionModel` provides immutable tuning, while `PropellantModel` owns
## the mutable tank state consumed by this engine at runtime.
class_name EngineModel

extends GravityRigidBody3D

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
## Render-only exhaust plume that mirrors the resolved gimbal angle. Its
## authored local transform is captured as neutral so runtime deflection can be
## reapplied without accumulating transform drift.
var plume: MeshInstance3D = null:
	set(p_plume):
		plume = p_plume
		if plume != null:
			_plume_neutral_transform = plume.transform
		update_configuration_warnings()

@export
## Optional selection panel data source updated from this engine's runtime state.
var info: Selectable3DInfo = null:
	set(p_info):
		info = p_info
		update_configuration_warnings()

## Current throttle setting, 0.0 (off) to 1.0 (full).
var _throttle: float = 0.0

## Normalized actuator command for pitch and yaw deflection. Roll input is
## accepted by `set_gimbal()` for command-payload compatibility, but a single
## engine's roll axis does not redirect thrust and is not stored here.
var _gimbal: Vector2 = Vector2.ZERO

## Actual slewed gimbal angles in radians for pitch and yaw.
var _gimbal_angles: Vector2 = Vector2.ZERO

## Authored local plume transform before runtime gimbal deflection is applied.
var _plume_neutral_transform: Transform3D = Transform3D.IDENTITY

## Cached thrust force.
var _thrust_force: Vector3 = Vector3.ZERO

@export
var engine_mass: float = 100.0

func _ready() -> void:
	if plume != null:
		_plume_neutral_transform = plume.transform
		_sync_plume_visual(false)
	update_configuration_warnings()
	_update_info()
	_update_mass()


## Keeps selection-panel fields fresh between physics steps.
func _process(_delta: float) -> void:
	_update_info()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if propellant_model == null:
		warnings.append("Propellant model is not set.")
	if propulsion_model == null:
		warnings.append("Propulsion model is not set.")
	if plume == null:
		warnings.append("Plume mesh is not set.")
	if info == null:
		warnings.append("Selectable info is not set.")
	return warnings


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	CelestialBodySystem.apply_gravity(state)
	resolve_gimbal_step(state.step)
	var thrust_magnitude := resolve_propulsion_step(state.step)
	_sync_plume_visual(thrust_magnitude > 0.0)
	if thrust_magnitude > 0.0:
		var thrust_dir := (
			state.transform.basis
			* get_actual_thrust_direction_local()
		).normalized()
		_thrust_force = thrust_dir * thrust_magnitude
		state.apply_force(_thrust_force)


func _update_info() -> void:
	if info == null:
		return

	info.info["name"] = name
	info.info["total_mass"] = get_total_mass()
	info.info["propellant_mass"] = get_propellant_mass()
	info.info["speed"] = linear_velocity.length()
	info.info["throttle"] = _throttle
	info.info["thrust"] = _thrust_force
	info.info["gimbal"] = _gimbal
	info.info["gimbal_angles"] = _gimbal_angles


func get_total_mass() -> float:
	return mass + get_propellant_mass()


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


## Sets the desired actuator command in normalized pitch/yaw space.
##
## `p_gimbal.x` is pitch, `p_gimbal.y` is yaw, and `p_gimbal.z` is ignored by
## this adapter. Values are clamped before they are turned into target angles.
func set_gimbal(p_gimbal: Vector3) -> void:
	_gimbal = Vector2(
		clampf(p_gimbal.x, -1.0, 1.0),
		clampf(p_gimbal.y, -1.0, 1.0)
	)


## Returns the clamped pitch/yaw command currently requested by the receiver.
func get_gimbal() -> Vector2:
	return _gimbal


## Returns the resolved actuator angles after slew-rate limiting.
func get_gimbal_angles() -> Vector2:
	return _gimbal_angles


## Returns the resolved actuator angles in degrees for HUD/debug output.
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
		Vector3(_gimbal.x, _gimbal.y, 0.0)
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


## Mirrors the current resolved actuator basis onto the render-only plume and
## toggles visibility from the actual thrust result, not the requested throttle.
func _sync_plume_visual(is_burning: bool) -> void:
	if plume == null:
		return

	var gimbal_basis := get_actual_gimbal_basis_local()
	plume.transform = Transform3D(
		gimbal_basis * _plume_neutral_transform.basis,
		gimbal_basis * _plume_neutral_transform.origin
	)
	plume.visible = is_burning


func _update_mass():
	mass = engine_mass + propellant_model.get_propellant_mass()


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

	_update_mass()

	var burn_fraction := actual_burn / requested_burn
	return propulsion_model.get_thrust_magnitude(_throttle) * burn_fraction
