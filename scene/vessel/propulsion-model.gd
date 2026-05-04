## Pure propulsion-performance model shared by scene adapters.
##
## This class maps throttle to scalar outputs:
## - thrust magnitude in Newtons
## - propellant flow in kg/s
## - bounded gimbal target angles
##
## It deliberately does not know about scene nodes, propellant storage,
## thruster transforms, or world-space force vectors. Those stay in adapters
## such as `VesselState` / `VesselModel` and `EngineModel`.

class_name PropulsionModel

extends Resource

## Maximum engine thrust at full throttle, in Newtons.
##
## Editor role:
## - primary scalar tuning knob for propulsion authority
##
## Runtime role:
## - read by scene adapters to convert throttle into requested force magnitude
## - applied in scene space later by the owning rigid-body adapter
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

## Maximum nozzle deflection around the adapter-local pitch axis, in degrees.
##
## Frame:
## - adapter-local actuator space
##
## Runtime role:
## - converted to radians and used to clamp pitch commands
## - mirrored visually by render-only thruster adapters when present
@export_range(0.0, 3000.0, 1.0) var max_gimbal_pitch_degrees := 5.0

## Maximum nozzle deflection around the adapter-local yaw axis, in degrees.
##
## This is independent from pitch so asymmetric actuator limits can be authored
## later without changing the contract.
@export_range(0.0, 3000.0, 1.0) var max_gimbal_yaw_degrees := 5.0

## Optional roll command limit, in degrees.
##
## Rolling around the thrust axis does not redirect a single engine's thrust.
## `EngineModel` ignores this axis; the standalone vessel harness still uses it
## for its torque-control prototype.
@export_range(0.0, 3000.0, 1.0) var max_gimbal_roll_degrees := 0.0

## Maximum actuator slew rate for configured gimbal axes, in degrees per second.
##
## Why it is exposed:
## - the harness wants physical thrust redirection to lag behind command input
##   instead of snapping instantly
##
## Runtime role:
## - used by adapters that slew from command input toward target gimbal angles
## - affects simulation thrust direction and mirrored render exhaust where used
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


## Returns the configured gimbal limits in radians for pitch, yaw, and roll.
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
