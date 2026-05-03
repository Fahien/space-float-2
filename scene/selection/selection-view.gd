class_name SelectionView

extends Node3D

@export
var follow_smoothing: float = 20.0

var target: Selectable3D = null


func _ready() -> void:
	SelectionSystem.selection_changed.connect(_on_selection_changed)


func _on_selection_changed(current: Selectable3D):
	target = current
	
	print("Target: ", target)
	if is_instance_valid(target):
		print("Target is valid")
		var anchor := target.get_selection_anchor()
		global_position = anchor.global_position
		scale = Vector3.ONE * target.get_selection_radius()
		visible = true
	else:
		visible = false


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		visible = false
		return

	var anchor := target.get_selection_anchor()
	var desired_position := anchor.global_position

	global_position = global_position.lerp(desired_position, 1.0 - exp(-follow_smoothing * delta))
	scale = Vector3.ONE * target.get_selection_radius()
	visible = true
