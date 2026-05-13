## Selection details panel populated from the current selectable's info source.
##
## The panel owns presentation only; selected scenes own the dictionary keys and
## update their values at their own cadence.
class_name Ui

extends CanvasLayer

@onready var vbox := $Margin/Panel/Margin/VBox

var _labels: Dictionary[String, Label] = {}


func _ready() -> void:
	_clear_vbox()
	SelectionSystem.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(SelectionSystem.current)


## Refreshes existing labels without rebuilding the node tree every frame.
func _process(_delta: float) -> void:
	var info_source := _get_current_info()
	if info_source == null:
		return

	_sync_labels(info_source)


## Removes all rows so the next selection starts from its own info schema.
func _clear_vbox() -> void:
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	_labels.clear()


## Returns the current selectable's info source, if one is available.
func _get_current_info() -> Selectable3DInfo:
	if not SelectionSystem.has_selection():
		return null

	var selected := SelectionSystem.current
	if selected == null:
		return null

	return selected.get_info()


## Synchronizes rows with the selected scene's current info dictionary.
func _sync_labels(info_source: Selectable3DInfo) -> void:
	for key in _labels.keys():
		if not info_source.info.has(key):
			var stale_label := _labels[key]
			_labels.erase(key)
			vbox.remove_child(stale_label)
			stale_label.queue_free()

	for key in info_source.info.keys():
		var label: Label = null
		if key in _labels:
			label = _labels[key]
		else:
			label = Label.new()
			label.name = key
			vbox.add_child(label)
			_labels[key] = label

		var value = info_source.info[key]
		label.text = "%s: %s" % [key.capitalize(), _format_value(key, value)]


func _format_value(key: String, value: Variant) -> String:
	match key:
		"total_mass", "propellant_mass":
			return "%.1f kg" % value
		"speed", "vertical_speed":
			return "%.1f m/s" % value
		"altitude":
			return "%.1f m" % value
		"eccentricity":
			return "%.4f" % value
		"periapsis", "apoapsis":
			return _format_distance_or_na(value)
		"throttle":
			return "%.0f%%" % (value * 100.0)
		"gimbal":
			return "(%.2f, %.2f)" % [value.x, value.y]
		"gimbal_angles":
			return "(%.1f°, %.1f°)" % [rad_to_deg(value.x), rad_to_deg(value.y)]
		_:
			return str(value)


func _format_distance_or_na(value: Variant) -> String:
	if value == null:
		return "N/A"
	if typeof(value) == TYPE_FLOAT and is_inf(value):
		return "N/A"
	return "%.1f m" % float(value)


## Rebuilds rows when the active selectable changes.
func _on_selection_changed(selected: Selectable3D) -> void:
	_clear_vbox()

	if selected == null:
		return

	var info := selected.get_info()
	if info == null:
		return

	_sync_labels(info)
