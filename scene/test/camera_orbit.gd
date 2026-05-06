## CameraOrbit owns orbit-style camera presentation around a chosen world
## target.
##
## Node layout:
## - CameraOrbitRoot moves to the current focus point.
## - YawPivot stores horizontal orbit rotation.
## - PitchPivot stores vertical orbit rotation.
## - SpringArm3D holds the camera at the requested zoom distance and moves it
##   closer when another collider blocks the view.
## - Camera3D renders the active view.
##
## Responsibilities:
## - keep the orbit rig aligned to the current target
## - turn pointer deltas into yaw/pitch intent
## - manage zoom on the spring arm
##
## It does not decide which gameplay object should be followed, and it does
## not own focus-selection policy. Higher-level nodes choose the target and
## decide whether a gesture means selection, orbit, or something else.
##
## Screen-space systems should use the wrapper methods at the end of this file
## instead of reaching into the child camera node directly.
class_name CameraOrbit

extends Node3D

const BIG_SPACE_OBSERVER_PROCESS_PRIORITY := -100

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

## The node the orbit rig follows.
##
## Exported so standalone scenes like the physics harness can wire the target
## in the editor without code. Setting this value snaps the rig immediately and
## rebuilds spring-arm exclusions so target changes do not lerp from unrelated
## world positions or collide with the new focus object.
@export var target: Node3D:
	set(new_target):
		target = new_target
		if is_node_ready():
			_snap_to_target()
			_refresh_spring_arm_exclusions()

var target_yaw := 0.0
var target_pitch := 0.0
var target_zoom := 4.0

var pending_mouse_delta := Vector2.ZERO

var is_lmb_down := false
var is_rotating := false
var drag_accumulator := Vector2.ZERO


func _enter_tree() -> void:
	# This node is the BigSpaceRoot3D floating origin in the main scenes. Move
	# it before the root's internal render refresh so the frame is not rendered
	# from the previous focus position.
	process_priority = BIG_SPACE_OBSERVER_PROCESS_PRIORITY


func _ready() -> void:
	_ensure_explicit_spring_arm_shape()
	target_yaw = yaw_pivot.rotation.y
	target_pitch = pitch_pivot.rotation.x
	target_zoom = spring_arm.spring_length
	_snap_to_target()
	_refresh_spring_arm_exclusions()

	SelectionSystem.selection_changed.connect(_on_selection_changed)


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


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		target_zoom = clamp(target_zoom - zoom_step, min_zoom, max_zoom)
	elif event.is_action_pressed("zoom_out"):
		target_zoom = clamp(target_zoom + zoom_step, min_zoom, max_zoom)


## Accumulates local orbit intent from mouse input.
##
## Left-button drag orbits the camera after `drag_start_threshold` pixels.
## Mouse-wheel input is handled by `_input()` through the `zoom_in` and
## `zoom_out` actions.
##
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
	if target != null and not is_instance_valid(target):
		target = null

	# Smoothly keep the orbit root centered on the current target.
	if _has_valid_target():
		var t_follow := 1.0 - exp(-target_follow_responsiveness * delta)
		global_position = global_position.lerp(_get_focus_position(), t_follow)

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


func _snap_to_target() -> void:
	if _has_valid_target():
		global_position = _get_focus_position()


## Resolves the point that should stay at the center of the orbit.
##
## Selectable scenes can provide a presentation anchor that differs from the
## selectable Area3D origin. This keeps selection rings, UI focus, and camera
## focus on the same authored point. Non-selectable targets focus their own
## origin.
func _get_focus_position() -> Vector3:
	var selectable := target as Selectable3D
	if selectable != null:
		var anchor := selectable.get_selection_anchor()
		if is_instance_valid(anchor):
			return anchor.global_position
	return target.global_position


func _has_valid_target() -> bool:
	return target != null and is_instance_valid(target)


## Keeps SpringArm3D obstacle sweeps from shortening against the followed
## object. The exclusions are rebuilt whenever the target changes because the
## selected node may be a child Area3D inside a larger rigid-body assembly.
##
## Exclusion rules:
## - Exclude the target when it is a CollisionObject3D.
## - Exclude descendant collision objects under the target.
## - If the target lives inside a PhysicsBody3D, exclude that body.
## - If that body belongs to a small authored assembly, exclude sibling bodies
##   in the same assembly.
func _refresh_spring_arm_exclusions() -> void:
	if spring_arm == null:
		return
	spring_arm.clear_excluded_objects()
	if not _has_valid_target():
		return

	var excluded: Dictionary = {}
	var roots := _get_spring_arm_exclusion_roots()
	for root in roots:
		_add_collision_object_exclusion(root, excluded)
		_add_descendant_collision_object_exclusions(root, excluded)


func _get_spring_arm_exclusion_roots() -> Array[Node]:
	var roots: Array[Node] = []
	if not _has_valid_target():
		return roots

	_add_unique_exclusion_root(roots, target)

	var collision_ancestor := _find_first_collision_object_ancestor(target)
	if collision_ancestor != null:
		_add_unique_exclusion_root(roots, collision_ancestor)

	var body_ancestor := target as PhysicsBody3D
	if body_ancestor == null:
		body_ancestor = _find_first_physics_body_ancestor(target)
	if body_ancestor != null:
		_add_unique_exclusion_root(roots, body_ancestor)
		var assembly_root := body_ancestor.get_parent()
		# Exclude small authored assemblies, but never broad spatial containers.
		if _should_exclude_descendants_of(assembly_root):
			_add_unique_exclusion_root(roots, assembly_root)

	return roots


func _add_unique_exclusion_root(roots: Array[Node], node: Node) -> void:
	if node == null or not is_instance_valid(node) or roots.has(node):
		return
	roots.append(node)


func _add_collision_object_exclusion(node: Node, excluded: Dictionary) -> void:
	var collision_object := node as CollisionObject3D
	if collision_object == null:
		return

	var rid: RID = collision_object.get_rid()
	if excluded.has(rid):
		return

	spring_arm.add_excluded_object(rid)
	excluded[rid] = true


func _add_descendant_collision_object_exclusions(root: Node, excluded: Dictionary) -> void:
	for child in root.get_children():
		_add_collision_object_exclusion(child, excluded)
		_add_descendant_collision_object_exclusions(child, excluded)


func _find_first_collision_object_ancestor(node: Node) -> CollisionObject3D:
	if node == null or not is_instance_valid(node):
		return null

	var parent: Node = node.get_parent()
	while parent != null:
		var collision_object := parent as CollisionObject3D
		if collision_object != null:
			return collision_object
		parent = parent.get_parent()
	return null


func _find_first_physics_body_ancestor(node: Node) -> PhysicsBody3D:
	if node == null or not is_instance_valid(node):
		return null

	var parent: Node = node.get_parent()
	while parent != null:
		var body := parent as PhysicsBody3D
		if body != null:
			return body
		parent = parent.get_parent()
	return null


func _should_exclude_descendants_of(node: Node) -> bool:
	if node == null:
		return false
	# Big-space nodes are broad spatial containers. Excluding their descendants
	# would hide too much of the world from spring-arm collision.
	return (
		not node.is_class("BigGrid3D")
		and not node.is_class("BigNode3D")
		and not node.is_class("BigSpaceRoot3D")
	)


## Convenience wrappers used by screen-space picking code.
func unproject_position(pos: Vector3) -> Vector2:
	return camera.unproject_position(pos)


func is_position_behind(pos: Vector3) -> bool:
	return camera.is_position_behind(pos)


func _on_selection_changed(selection: Node3D) -> void:
	set_target(selection)
