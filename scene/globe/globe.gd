@tool
extends Node3D

@export
var patch: PackedScene = null:
	set(p_patch):
		patch = p_patch
		update_configuration_warnings()
		_build()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if patch == null:
		warnings.append("Patch is not assigned. Set 'patch' property to a MeshInstance3D.")
		
	return warnings

func _ready() -> void:
	update_configuration_warnings()

func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _build() -> void:
	if get_tree() == null:
		return

	_clear_children()

	if patch == null:
		return

	var instances = []

	# Front (-Z)
	var instance0 = patch.instantiate() as Node3D
	instances.push_back(instance0)

	# Right (+X)
	var instance1 = instance0.duplicate()
	instance1.rotate_y(PI/2.0)
	instances.push_back(instance1)

	# Up (+Y)
	var instance2 = instance0.duplicate()
	instance2.rotate_x(-PI/2.0)
	instances.push_back(instance2)
	
	# Back (Z)
	var instance3 = instance0.duplicate()
	instance3.rotate_y(PI)
	instances.push_back(instance3)
	
	# Left (-X)
	var instance4 = instance0.duplicate()
	instance4.rotate_y(-PI/2.0)
	instances.push_back(instance4)
	
	# Bottom (-Y)
	var instance5 = instance0.duplicate()
	instance5.rotate_x(PI/2.0)
	instances.push_back(instance5)

	for instance in instances:
		add_child(instance)
		if Engine.is_editor_hint():
			instance.owner = get_tree().edited_scene_root
