class_name Selectable3D

extends Area3D

@export
## Optional scene-space node used by selection rings and camera focus.
var anchor: Node3D = null

@export
## Receiver that accepts command payloads while this selectable is active.
var command_receiver: CommandReceiver = CommandReceiver.new()

@export
## Optional runtime info source rendered by selection UI panels.
var info: Selectable3DInfo = null


## Returns the node that visual selection affordances should follow.
func get_selection_anchor() -> Node3D:
	if anchor != null:
		return anchor
	return self


## Returns the command receiver for gameplay input while selected.
func get_command_receiver() -> CommandReceiver:
	return command_receiver


## Returns a conservative world-space radius for selection affordances.
func get_selection_radius() -> float:
	var shape := _get_shape()
	if shape == null:
		return 1.0
	if shape is BoxShape3D:
		var box_shape := shape as BoxShape3D
		return box_shape.size.length() * 0.5
	elif shape is SphereShape3D:
		var sphere_shape := shape as SphereShape3D
		return sphere_shape.radius
	elif shape is CapsuleShape3D:
		var capsule_shape := shape as CapsuleShape3D
		return max(capsule_shape.radius, capsule_shape.height * 0.5)
	else:
		return 1.0


func _get_shape() -> Shape3D:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		return null
	return collision_shape.shape


## Returns the optional info source for UI panels.
func get_info() -> Selectable3DInfo:
	return info
