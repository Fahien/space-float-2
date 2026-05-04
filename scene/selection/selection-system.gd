extends Node

var current: Selectable3D = null

signal selection_changed(current: Selectable3D)

@export var ray_length: float = 100_000.0

@export_flags_3d_physics var selection_collision_mask: int = 0xffffffff


func _unhandled_input(p_event: InputEvent) -> void:
	if p_event is InputEventMouseButton:
		if p_event.button_index == MOUSE_BUTTON_LEFT and p_event.pressed:
			_pick(p_event.position)


func _pick(p_position_in_screen_space: Vector2) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return

	# Get main camera.
	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	if has_selection():
		return

	# Ray origin in world space.
	var from := camera.project_ray_origin(p_position_in_screen_space)
	# Ray direction in world space.
	var to := from + camera.project_ray_normal(p_position_in_screen_space) * ray_length

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = selection_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result := viewport.world_3d.direct_space_state.intersect_ray(query)
	if result.is_empty():
		clear_selection()
		return

	var collider := result["collider"] as Node
	var selectable := _find_selectable(collider)
	if selectable == null:
		clear_selection()
		return

	select(selectable)


func has_selection() -> bool:
	return current != null


func clear_selection() -> void:
	select(null)


func select(selectable: Selectable3D) -> void:
	if current == selectable:
		return

	current = selectable
	print("Selected: ", current)
	selection_changed.emit(current)


## Walk up the node tree to find a Selectable3D.
func _find_selectable(p_node: Node) -> Selectable3D:
	var node := p_node
	while node != null:
		if node is Selectable3D:
			return node as Selectable3D
		node = node.get_parent()
	return null
