## CameraOrbit owns orbit-style camera presentation around a chosen world
## target.
##
## Responsibilities:
## - keep the orbit rig aligned to the current target
## - turn pointer deltas into yaw/pitch intent
## - manage zoom on the spring arm
##
## It does not decide which gameplay object should be followed, and it does
## not own focus-selection policy. Higher-level nodes choose the target and
## decide whether a gesture means selection, orbit, or something else.
class_name CameraOrbit

extends Node3D

@export var mouse_sensitivity := 0.01
@export var rotation_responsiveness := 20.0
@export var zoom_step := 2.0
@export var zoom_responsiveness := 12.0
@export var min_zoom := 3.0
@export var max_zoom := 40.0
@export var min_pitch_deg := -80.0
@export var max_pitch_deg := 80.0
@export var target_follow_responsiveness := 100.1
## Radius of the explicit spring-arm sweep shape.
##
## Leaving `SpringArm3D.shape` unset makes Godot derive a convex pyramid from
## the child camera frustum. That quietly couples obstacle avoidance to
## render-only clip-range changes. The orbit rig keeps an explicit bounded
## shape so collision sweeps remain stable even if a scene chooses a different
## camera clip range.
@export_range(0.01, 5.0, 0.01) var collision_probe_radius := 0.25

## How much the mouse must move, in pixels, before drag/orbit starts.
@export var drag_start_threshold := 8.0

@onready var yaw_pivot: Node3D = $YawPivot
@onready var pitch_pivot: Node3D = $YawPivot/PitchPivot
@onready var spring_arm: SpringArm3D = $YawPivot/PitchPivot/SpringArm3D
@onready var camera: Camera3D = $YawPivot/PitchPivot/SpringArm3D/Camera3D

## The node the orbit rig follows. Exported so standalone scenes like the
## physics harness can wire the target in the editor without code.
@export var target: Node3D

var target_yaw := 0.0
var target_pitch := 0.0
var target_zoom := 4.0

var pending_mouse_delta := Vector2.ZERO

var is_lmb_down := false
var is_rotating := false
var drag_accumulator := Vector2.ZERO


func _ready() -> void:
	_ensure_explicit_spring_arm_shape()
	target_yaw = yaw_pivot.rotation.y
	target_pitch = pitch_pivot.rotation.x
	target_zoom = spring_arm.spring_length


func _ensure_explicit_spring_arm_shape() -> void:
	if spring_arm.shape != null:
		return
	var collision_probe := SphereShape3D.new()
	collision_probe.radius = collision_probe_radius
	spring_arm.shape = collision_probe


## Changes the tracked target for the orbit rig.
## The orbit root snaps to a new target immediately so follow transitions do
## not interpolate from stale unrelated positions.
func set_target(new_target: Node3D) -> void:
	target = new_target
	if target:
		global_position = target.global_position


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		target_zoom = clamp(target_zoom - zoom_step, min_zoom, max_zoom)
	elif event.is_action_pressed("zoom_out"):
		target_zoom = clamp(target_zoom + zoom_step, min_zoom, max_zoom)


## Accumulates local orbit intent from mouse input.
## This node tracks drag/orbit state only; it does not decide whether a left
## click should instead be interpreted as a gameplay selection.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_lmb_down = true
				is_rotating = false
				drag_accumulator = Vector2.ZERO
				pending_mouse_delta = Vector2.ZERO
			else:
				is_lmb_down = false

				if is_rotating:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

				is_rotating = false
				drag_accumulator = Vector2.ZERO
				pending_mouse_delta = Vector2.ZERO

	elif event is InputEventMouseMotion:
		if not is_lmb_down:
			return

		if not is_rotating:
			drag_accumulator += event.screen_relative

			if drag_accumulator.length() >= drag_start_threshold:
				is_rotating = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

				# Use the motion that triggered the threshold so the start feels responsive.
				pending_mouse_delta += drag_accumulator
				drag_accumulator = Vector2.ZERO
		else:
			pending_mouse_delta += event.screen_relative


func _process(delta: float) -> void:
	# Smoothly keep the orbit root centered on the current target.
	if target:
		var t_follow := 1.0 - exp(-target_follow_responsiveness * delta)
		global_position = global_position.lerp(target.global_position, t_follow)

	# Convert accumulated pointer motion into desired orbit angles.
	if pending_mouse_delta != Vector2.ZERO:
		target_yaw -= pending_mouse_delta.x * mouse_sensitivity
		target_pitch -= pending_mouse_delta.y * mouse_sensitivity
		target_pitch = clamp(
			target_pitch,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)
		pending_mouse_delta = Vector2.ZERO

	# Apply delta-aware smoothing so orbit motion is frame-rate independent.
	var t_rot := 1.0 - exp(-rotation_responsiveness * delta)
	yaw_pivot.rotation.y = lerp_angle(yaw_pivot.rotation.y, target_yaw, t_rot)
	pitch_pivot.rotation.x = lerp_angle(pitch_pivot.rotation.x, target_pitch, t_rot)

	# Smooth zoom toward the requested spring-arm length.
	var t_zoom := 1.0 - exp(-zoom_responsiveness * delta)
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_zoom, t_zoom)


## Convenience wrappers used by screen-space picking code.
func unproject_position(pos: Vector3) -> Vector2:
	return camera.unproject_position(pos)


func is_position_behind(pos: Vector3) -> bool:
	return camera.is_position_behind(pos)
