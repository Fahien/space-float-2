## Physics harness — test scene controller.
##
## This scene exists to verify Godot rigid-body behavior before building the
## full rocket simulation. It proves:
##   - manual gravity application via PlanetModel (Godot's built-in gravity is
##     zeroed on the RigidBody3D so the sim layer owns it)
##   - off-center thrust producing both translation and torque
##   - stable pad contact under Jolt physics
##   - basic atmosphere-driven drag plus debug instrumentation for key forces
##
## The harness is standalone — it does not depend on the multiplayer stack,
## ServerRuntime, or SectorRuntime. It can be run directly as the main scene
## for quick iteration on launch physics.
##
## This scene is also the composition root for the current scene ->
## simulation mapping: it chooses the launch-site inputs and injects the
## resulting `SurfaceTangentFrame` and `SceneFrame` into the authored entity
## scenes mounted under it.
##
## It also wires the current render seam:
## - `RenderCoordinator` owns the live `RenderFrame`
## - render-only consumers live under `HarnessRenderView`
## - physics-authoritative nodes must not be repositioned through it
## - per-frame render updates stay out of this composition root
## - the harness camera still owns the authored clip range
## - Earth-only presentation receives only the scalar budget left inside that
##   clip range plus the globe renderer's current visible-distance measurement
class_name PhysicsHarness

extends Node

@onready var ground : PlanetModel = $EarthGrid/EarthOrigin
@onready var vessel: VesselModel = $EarthGrid/Z1/Vessel2

@onready var vessel_hud := $CanvasLayer/Margin/VesselPanel/Margin/VBox/Vessel
@onready var mass_hud := $CanvasLayer/Margin/VesselPanel/Margin/VBox/Mass
@onready var speed_hud := $CanvasLayer/Margin/VesselPanel/Margin/VBox/Speed
@onready var altitude_hud := $CanvasLayer/Margin/VesselPanel/Margin/VBox/Altitude
@onready var gravity_hud := $"CanvasLayer/Margin/VesselPanel/Margin/VBox/Gravity"
@onready var gravity_force_hud := $"CanvasLayer/Margin/VesselPanel/Margin/VBox/GravityForce"
@onready var thrust_hud := $"CanvasLayer/Margin/VesselPanel/Margin/VBox/ThrustForce"
@onready var drag_hud := $"CanvasLayer/Margin/VesselPanel/Margin/VBox/DragForce"
@onready var gimbal_command_hud := $"CanvasLayer/Margin/VesselPanel/Margin/VBox/GimbalCommand"
@onready var gimbal_state_hud := $"CanvasLayer/Margin/VesselPanel/Margin/VBox/GimbalState"


func _input(event: InputEvent) -> void:
	if _is_vessel_control_event(event):
		_apply_vessel_control_inputs()


func _ready() -> void:
	vessel.set_planet_model(ground)

	_apply_vessel_control_inputs()


func _process(_delta: float) -> void:
	vessel_hud.text = "%s" % vessel.name
	mass_hud.text = "Mass: %.2f kg" % vessel.mass
	speed_hud.text = "Speed: %.2f m/s" % vessel.linear_velocity.length()
	altitude_hud.text = "Altitude: %.2f m" % ground.get_altitude_at(vessel.get_global_position())
	gravity_hud.text = "Gravity: %.2f m/s²" % vessel.get_custom_gravity().length()
	gravity_force_hud.text = "Gravity Force: %.2f N" % vessel.get_gravity_force().length()
	thrust_hud.text = "Thrust Force: %.2f N" % vessel.get_thrust().length()
	drag_hud.text = "Drag Force: %.2f N" % vessel.get_drag().length()
	gimbal_command_hud.text = "Gimbal Command: (%.2f, %.2f)" % [
		vessel.get_gimbal_command().x,
		vessel.get_gimbal_command().y,
	]
	gimbal_state_hud.text = "Gimbal State: pitch %.2f deg, yaw %.2f deg" % [
		vessel.get_gimbal_angles_degrees().x,
		vessel.get_gimbal_angles_degrees().y,
	]


func _apply_vessel_control_inputs() -> void:
	vessel.set_throttle(_sample_throttle_input())
	vessel.set_gimbal_command(_sample_gimbal_input())


func _sample_throttle_input() -> float:
	if Input.is_action_pressed("ship_thrust_forward", true):
		return 1.0
	return 0.0


## Positive pitch/yaw values are chosen so the resulting off-axis thrust
## produces pitch-up / yaw-left vehicle response for the current launch rig.
func _sample_gimbal_input() -> Vector2:
	var gimbal_command := Vector2.ZERO
	if Input.is_action_pressed("ship_pitch_up", true):
		gimbal_command.x += 1.0
	if Input.is_action_pressed("ship_pitch_down", true):
		gimbal_command.x -= 1.0
	if Input.is_action_pressed("ship_yaw_left", true):
		gimbal_command.y += 1.0
	if Input.is_action_pressed("ship_yaw_right", true):
		gimbal_command.y -= 1.0
	return gimbal_command


func _is_vessel_control_event(event: InputEvent) -> bool:
	if event == null:
		return false
	return (
		event.is_action("ship_thrust_forward")
		or event.is_action("ship_pitch_up")
		or event.is_action("ship_pitch_down")
		or event.is_action("ship_yaw_left")
		or event.is_action("ship_yaw_right")
	)
