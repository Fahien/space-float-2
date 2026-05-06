## Samples the current selection's ship-control inputs and sends a normalized
## command payload to its receiver.
##
## Command signs match `PhysicsHarness._sample_gimbal_input()`: positive pitch
## means pitch-up intent, positive yaw means yaw-left intent, and positive roll
## means roll-left intent.
extends Node


func _process(_delta: float) -> void:
	if not SelectionSystem.has_selection():
		return

	var selectable := SelectionSystem.current
	var receiver := selectable.get_command_receiver()

	if not is_instance_valid(receiver):
		return

	var command := EngineCommand.new()

	if Input.is_action_pressed("ship_thrust_forward"):
		command.throttle = 1.0
	if Input.is_action_pressed("ship_roll_right"):
		command.gimbal.z -= 1.0
	if Input.is_action_pressed("ship_roll_left"):
		command.gimbal.z += 1.0
	if Input.is_action_pressed("ship_pitch_up"):
		command.gimbal.x += 1.0
	if Input.is_action_pressed("ship_pitch_down"):
		command.gimbal.x -= 1.0
	if Input.is_action_pressed("ship_yaw_left"):
		command.gimbal.y -= 1.0
	if Input.is_action_pressed("ship_yaw_right"):
		command.gimbal.y += 1.0

	receiver.receive_command(command)
