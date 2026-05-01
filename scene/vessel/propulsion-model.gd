## Pure engine-performance model for the standalone launch harness.
##
## This class maps throttle to scalar outputs only:
## - thrust magnitude in Newtons
## - propellant flow in kg/s
##
## It deliberately does not know about scene nodes, thruster transforms, or
## world-space force vectors. Those stay in `VesselModel`, which is the
## Godot-facing rigid-body adapter.

class_name PropulsionModel

extends Resource

## Maximum engine thrust at full throttle, in Newtons.
##
## Editor role:
## - primary scalar tuning knob for the vessel's propulsion authority
##
## Runtime role:
## - read by `VesselState` to convert throttle into requested force magnitude
## - applied in scene space later by `VesselModel`
##
## Interaction:
## - does not set burn duration by itself; pair with
##   `max_propellant_flow_kg_per_s`
@export var max_thrust_newtons := 20000.0

## Maximum propellant consumption at full throttle, in kilograms per second.
##
## This is the fuel-side counterpart to `max_thrust_newtons`. It controls burn
## duration and mass depletion, not direction or mounting.
@export var max_propellant_flow_kg_per_s := 1.0

## Maximum nozzle deflection around the vessel-local pitch axis, in degrees.
##
## Frame:
## - vessel-local actuator space
##
## Runtime role:
## - converted to radians and used by `VesselState` to clamp pitch commands
## - mirrored visually by the render-only thruster pivot
@export_range(0.0, 3000.0, 1.0) var max_gimbal_pitch_degrees := 5.0

## Maximum nozzle deflection around the vessel-local yaw axis, in degrees.
##
## This is independent from pitch so asymmetric actuator limits can be authored
## later without changing the contract.
@export_range(0.0, 3000.0, 1.0) var max_gimbal_yaw_degrees := 5.0

@export_range(0.0, 3000.0, 1.0) var max_gimbal_roll_degrees := 0.0

## Maximum actuator slew rate for both gimbal axes, in degrees per second.
##
## Why it is exposed:
## - the harness wants physical thrust redirection to lag behind command input
##   instead of snapping instantly
##
## Runtime role:
## - used by `VesselState.resolve_gimbal_step(...)`
## - affects both simulation thrust direction and the mirrored render exhaust
##
## Safety:
## - safe to author in the editor
## - changing it at runtime changes actuator response immediately
@export_range(0.0, 500.0, 0.1) var gimbal_slew_degrees_per_second := 20.0


## Returns requested thrust magnitude for the given throttle command.
## The response is intentionally linear for now.
func get_thrust_magnitude(throttle: float) -> float:
	return max_thrust_newtons * clampf(throttle, 0.0, 1.0)


## Returns requested propellant flow for the given throttle command.
## Actual fuel use may be lower if the vessel runs out of propellant mid-step.
func get_propellant_flow(throttle: float) -> float:
	return max_propellant_flow_kg_per_s * clampf(throttle, 0.0, 1.0)


## Returns the configured gimbal limits in radians for pitch and yaw.
func get_gimbal_limit_radians() -> Vector3:
	return Vector3(
		deg_to_rad(maxf(max_gimbal_pitch_degrees, 0.0)),
		deg_to_rad(maxf(max_gimbal_yaw_degrees, 0.0)),
		deg_to_rad(maxf(max_gimbal_roll_degrees, 0.0))
	)


## Returns the configured actuator slew rate in radians per second.
func get_gimbal_slew_rate_radians() -> float:
	return deg_to_rad(maxf(gimbal_slew_degrees_per_second, 0.0))


## Converts a normalized actuator command into bounded target angles.
func get_gimbal_target_angles(command: Vector3) -> Vector3:
	var limits := get_gimbal_limit_radians()
	var clamped_command := Vector3(
		clampf(command.x, -1.0, 1.0),
		clampf(command.y, -1.0, 1.0),
		clampf(command.z, -1.0, 1.0)
	)
	return Vector3(
		clamped_command.x * limits.x,
		clamped_command.y * limits.y,
		clamped_command.z * limits.z
	)
