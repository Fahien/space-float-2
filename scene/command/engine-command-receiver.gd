@tool
## Applies `EngineCommand` payloads to a standalone `EngineModel`.
##
## The receiver intentionally ignores unrelated command subclasses so selected
## nodes can share the generic `CommandReceiver` interface.
class_name EngineCommandReceiver

extends CommandReceiver

@export
## Engine body that owns throttle, fuel consumption, force application, and
## render-only plume synchronization for this receiver.
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
	if command is EngineCommand:
		engine_model.set_throttle(command.throttle)
		engine_model.set_gimbal(command.gimbal)
