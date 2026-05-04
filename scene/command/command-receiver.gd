class_name CommandReceiver

extends Node

func receive_command(command: Command) -> void:
	printerr("Unhandled command: ", command.type)
