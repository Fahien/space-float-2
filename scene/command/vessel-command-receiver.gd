## Chapter: The Command Bridge
##
## When engines lived as independent rigid bodies, each one carried its own
## `EngineCommandReceiver` and its own `Selectable3DInfo` updater. Pilot input
## arrived at a single engine; multi-engine craft required external wiring to
## duplicate that input, and every engine ran its own `_process()` loop to push
## throttle, gimbal, and environment data to the selection panel. The coupling
## was fragile — adding or staging engines meant rewiring command paths by hand.
##
## `VesselCommandReceiver` replaces that per-engine wiring with a single
## vessel-level node. On `NOTIFICATION_PARENTED` it discovers every
## `EngineModel` among its parent's direct children and stores them as the
## active engine set. When a command arrives, the receiver fans it out: an
## `EngineCommand` sets throttle and gimbal on every active engine; other
## command types pass through silently so the receiver can grow without breaking
## existing traffic. At runtime, `set_active_engines()` narrows or widens that
## set for staging transitions without touching the scene tree.
##
## The same node owns the HUD reporting loop that engines used to run
## individually. Each `_process()` frame, `VesselCommandReceiver` reads the
## parent vessel's mass, velocity, and orbital primary, aggregates propellant
## mass across active engines, and writes the result to a single
## `Selectable3DInfo`. The selection panel therefore reflects the vessel as a
## whole — not whichever engine happened to update last.
class_name VesselCommandReceiver

extends CommandReceiver

@export var info: Selectable3DInfo = null:
	set(p_info):
		info = p_info
		update_configuration_warnings()

## Engines that currently receive command input. Populated automatically from
## the parent vessel's direct EngineModel children on _ready(); call
## set_active_engines() at runtime for staging transitions.
var _active_engines: Array[EngineModel] = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED:
		_discover_engines()


func _ready() -> void:
	update_configuration_warnings()


func _process(_delta: float) -> void:
	_update_info()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _active_engines.is_empty():
		warnings.append("No active engines discovered.")
	if info == null:
		warnings.append("Selectable info is not set.")
	return warnings


func receive_command(command: Command) -> void:
	if command is EngineCommand:
		for engine in _active_engines:
			if is_instance_valid(engine):
				engine.set_throttle(command.throttle)
				engine.set_gimbal(command.gimbal)


func get_active_engines() -> Array[EngineModel]:
	return _active_engines


func set_active_engines(p_engines: Array[EngineModel]) -> void:
	_active_engines = p_engines
	update_configuration_warnings()


func _discover_engines() -> void:
	_active_engines.clear()
	var vessel := _get_vessel()
	if vessel == null:
		return
	for child in vessel.get_children():
		if child is EngineModel:
			_active_engines.append(child)


func _update_info() -> void:
	if info == null:
		return

	var vessel := _get_vessel()
	if vessel == null:
		return

	info.info["name"] = vessel.name
	info.info["total_mass"] = vessel.get_total_mass()
	info.info["speed"] = vessel.linear_velocity.length()

	_clear_orbital_info()
	info.info["celestial_body"] = "None"
	if vessel.current_primary != null and is_instance_valid(vessel.current_primary):
		var primary := vessel.current_primary
		info.info["celestial_body"] = primary.name
		info.info["altitude"] = primary.get_altitude_at(vessel.global_position)
		var up := primary.get_up_at(vessel.global_position)
		info.info["vertical_speed"] = vessel.linear_velocity.dot(up)
		_update_orbital_info(vessel, primary)

	var propellant_mass := 0.0
	for engine in _active_engines:
		if is_instance_valid(engine):
			propellant_mass += engine.get_propellant_mass()
	info.info["propellant_mass"] = propellant_mass

	if not _active_engines.is_empty() and is_instance_valid(_active_engines[0]):
		var engine := _active_engines[0]
		info.info["throttle"] = engine.get_throttle()
		info.info["gimbal"] = engine.get_gimbal()
		info.info["gimbal_angles"] = engine.get_gimbal_angles()


func _update_orbital_info(vessel: VesselRigidBody3D, primary: CelestialBody3D) -> void:
	if primary.mu <= 0.0:
		return

	var elements := OrbitalElements.new()
	elements.set_from_state_vector(
		vessel.global_position - primary.global_position,
		vessel.linear_velocity,
		primary.mu
	)
	if elements.is_degenerate():
		return

	info.info["eccentricity"] = elements.eccentricity
	info.info["periapsis"] = elements.periapsis - primary.radius
	if elements.is_closed():
		info.info["apoapsis"] = elements.apoapsis - primary.radius
	else:
		info.info["apoapsis"] = null


func _clear_orbital_info() -> void:
	info.info.erase("eccentricity")
	info.info.erase("periapsis")
	info.info.erase("apoapsis")


func _get_vessel() -> VesselRigidBody3D:
	var parent := get_parent()
	if parent is VesselRigidBody3D:
		return parent
	return null
