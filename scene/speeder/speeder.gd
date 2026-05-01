extends MeshInstance3D

@export var speed: float = 1000.0
@export var rotation_speed: float = 1.0

var thrust_input: Vector3 = Vector3.ZERO
var rotation_input: Vector3 = Vector3.ZERO

func _process(delta: float) -> void:
	# Process input
	thrust_input = Vector3.ZERO
	rotation_input = Vector3.ZERO
	if Input.is_action_pressed("throttle"):
		thrust_input.z = 1
	if Input.is_action_pressed("roll_right"):
		rotation_input.y = -1
	if Input.is_action_pressed("roll_left"):
		rotation_input.y = 1
	if Input.is_action_pressed("pitch_up"):
		rotation_input.x = -1
	if Input.is_action_pressed("pitch_down"):
		rotation_input.x = 1
	if Input.is_action_pressed("yaw_right"):
		rotation_input.z = -1
	if Input.is_action_pressed("yaw_left"):
		rotation_input.z = 1

	# Move the vessel based on thrust input
	var forward_direction = -transform.basis.z.normalized()
	var right_direction = transform.basis.x.normalized()
	var up_direction = transform.basis.y.normalized()
	
	var movement = (forward_direction * thrust_input.z + right_direction * thrust_input.x + up_direction * thrust_input.y) * speed * delta
	global_translate(movement)
	
	# Rotate the vessel based on rotation input
	var l_rotation = Vector3(rotation_input.x, rotation_input.y, rotation_input.z) * rotation_speed * delta
	rotate_x(l_rotation.x)
	rotate_y(l_rotation.y)
	rotate_z(l_rotation.z)
