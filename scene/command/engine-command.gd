## Command payload for one engine's thrust and actuator inputs.
##
## `throttle` is normalized from 0.0 (off) to 1.0 (full). `gimbal` is a
## normalized actuator command where x = pitch, y = yaw, and z = roll.
## `EngineModel` consumes pitch/yaw only; the roll component is preserved here
## so richer receivers can share the same command shape.
class_name EngineCommand

extends Command

## Requested throttle fraction. Receivers clamp this before applying it.
var throttle: float = 0.0

## Requested normalized gimbal command in pitch/yaw/roll order.
var gimbal: Vector3 = Vector3.ZERO


func _init(p_throttle: float = 0.0, p_gimbal: Vector3 = Vector3.ZERO) -> void:
	type = Type.ENGINE
	throttle = p_throttle
	gimbal = p_gimbal
