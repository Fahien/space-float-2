@tool
class_name EngineCommandReceiver

extends CommandReceiver

@export
var engine_model: EngineModel = null:
	set(p_model):
		engine_model = p_model
		update_configuration_warnings()


func _ready() -> void:
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if engine_model == null:
		warnings.append("Engine model is not set.")
	return warnings


func receive_command(command: Command) -> void:
	if engine_model == null:
		return
	if command is ThrottleCommand:
		engine_model.set_throttle(command.throttle)
