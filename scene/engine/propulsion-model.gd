## Chapter: The Engine's Contract
##
## Spaceflight engineering begins with a small inventory of promises: how much
## force an engine can give, how quickly it spends propellant, and how far its
## nozzle can turn before the machinery reaches its stops. `PropulsionModel`
## keeps those promises together as authored engine doctrine. It does not fly a
## craft by itself; it records the terms under which an engine may be asked to
## fly.
##
## The class belongs to `scene/engine` because the active propulsion path is now
## an engine component installed under `VesselRigidBody3D`, not the retiring
## `scene/vessel` prototype. `EngineModel` reads this resource while resolving
## the vessel's per-step force contribution, `PropellantModel` accounts for
## available fuel, and command receivers supply normalized throttle and gimbal
## input. Older vessel scripts may still refer to `PropulsionModel` while they
## are phased out, but they are historical clients rather than the owner of this
## contract.
##
## The contract remains deliberately narrow. Throttle maps linearly to requested
## thrust and propellant flow; gimbal commands become clamped actuator targets;
## slew rate tells components how quickly an ideal command becomes a physical
## angle. Scene-space force, tank depletion, plume transforms, and rigid-body
## integration stay outside the resource. Keeping that frontier clear lets
## engine scenes share propulsion figures without carrying the old vessel
## scene's assumptions forward.

class_name PropulsionModel

extends Resource

## Maximum engine thrust at full throttle, in Newtons.
##
## Editor role:
## - primary scalar tuning knob for propulsion authority
##
## Runtime role:
## - read by engine components to convert throttle into requested force magnitude
## - applied in scene space later by the owning vessel body
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

## Maximum nozzle deflection around the component-local pitch axis, in degrees.
##
## Frame:
## - component-local actuator space
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
## Rolling around the thrust axis does not redirect a single engine's thrust,
## so `EngineModel` ignores this axis. The value remains in the resource for
## command compatibility, future multi-actuator layouts, and legacy vessel code
## that may read it until that path is retired.
@export_range(0.0, 3000.0, 1.0) var max_gimbal_roll_degrees := 0.0

## Maximum actuator slew rate for configured gimbal axes, in degrees per second.
##
## Why it is exposed:
## - active engine components model physical thrust redirection as a response that
##   lags behind command input instead of snapping instantly
##
## Runtime role:
## - used by components that slew from command input toward target gimbal angles
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
## Actual fuel use may be lower if the attached tank runs dry mid-step.
func get_propellant_flow(throttle: float) -> float:
	return max_propellant_flow_kg_per_s * clampf(throttle, 0.0, 1.0)


## Returns configured gimbal limits in radians for pitch, yaw, and compatibility roll.
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
