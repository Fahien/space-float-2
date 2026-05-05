## Selection details panel populated from the current selectable's info source.
##
## The panel owns presentation only; selected scenes own the dictionary keys and
## update their values at their own cadence.
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
		label.text = "%s: %s" % [key.capitalize(), str(value)]


## Rebuilds rows when the active selectable changes.
func _on_selection_changed(selected: Selectable3D) -> void:
	_clear_vbox()

	if selected == null:
		return

	var info := selected.get_info()
	if info == null:
		return

	_sync_labels(info)
