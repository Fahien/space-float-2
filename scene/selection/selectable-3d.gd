class_name Selectable3D

extends Area3D

@export
var anchor: Node3D = null


func get_selection_anchor() -> Node3D:
	if anchor != null:
		return anchor
	return self


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
