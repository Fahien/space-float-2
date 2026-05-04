extends Node


func _process(_delta: float) -> void:
	if not SelectionSystem.has_selection():
		return

	var selectable := SelectionSystem.current
	var receiver := selectable.get_command_receiver()

	if not is_instance_valid(receiver):
		return

	var command := ThrottleCommand.new()
	if Input.is_action_pressed("ship_thrust_forward"):
		command.throttle = 1.0
	else:
		command.throttle = 0.0

	receiver.receive_command(command)
