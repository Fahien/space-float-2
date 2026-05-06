extends Node

const TOUCH_EMULATED_MOUSE_INDEX := -2
const ANDROID_BASELINE_DPI := 160.0
const ANDROID_FALLBACK_DPI := 320.0

var current: Selectable3D = null

signal selection_changed(current: Selectable3D)

@export var ray_length: float = 100_000.0

@export_flags_3d_physics var selection_collision_mask: int = 0xffffffff

## Matches CameraOrbit.drag_start_threshold by default so click/tap selection
## and orbit gestures make the same drag/click decision.
@export var pointer_drag_cancel_threshold := 8.0

## Touch positions are screen pixels too, but real finger jitter on Android is
## much larger than a mouse click. Keep this above the mouse drag threshold so
## long-press selection is reachable on device.
@export var touch_drag_cancel_threshold := 24.0

## Touch target selection uses a hold by default so orbit/pan gestures can start
## without immediately changing focus.
@export var touch_select_hold_seconds := 0.45

@export var touch_targets_require_hold := true

## Fallback radius in screen pixels. Touch uses the dp-sized Android affordance
## below when it would be larger.
@export var hold_indicator_radius := 18.0

## Android touch feedback should be large enough to read around a fingertip.
## 56dp keeps the ring above the 48dp Material/Android minimum touch size.
@export var touch_hold_indicator_diameter_dp := 56.0

## Move the progress ring away from the contact point. It prefers above the
## finger and flips below near the top screen edge.
@export var touch_hold_indicator_offset_dp := 72.0

@export var touch_hold_indicator_screen_margin_dp := 8.0

@export var hold_indicator_layer := 100

var _pointer_active := false
var _pointer_is_touch := false
var _pointer_index := -1
var _press_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _pressed_selectable: Selectable3D = null
var _gesture_canceled := false
var _hold_elapsed := 0.0
var _hold_committed := false
var _ignore_emulated_mouse_until_msec := 0

var _hold_overlay: CanvasLayer = null
var _hold_indicator: HoldIndicator = null


class HoldIndicator:
	extends Control

	var radius := 18.0:
		set(value):
			radius = maxf(value, 1.0)
			custom_minimum_size = Vector2.ONE * radius * 2.0
			size = custom_minimum_size
			queue_redraw()

	var track_width := 2.0:
		set(value):
			track_width = maxf(value, 1.0)
			queue_redraw()

	var progress_width := 4.0:
		set(value):
			progress_width = maxf(value, 1.0)
			queue_redraw()

	var progress := 0.0:
		set(value):
			progress = clampf(value, 0.0, 1.0)
			queue_redraw()


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


	func set_center_position(
		screen_position: Vector2,
		visible_rect: Rect2,
		margin: float
	) -> void:
		var half_size := size * 0.5
		var min_center := visible_rect.position + half_size + Vector2.ONE * margin
		var max_center := visible_rect.position + visible_rect.size - half_size - Vector2.ONE * margin
		var center := screen_position

		if min_center.x <= max_center.x:
			center.x = clampf(center.x, min_center.x, max_center.x)
		else:
			center.x = visible_rect.position.x + visible_rect.size.x * 0.5

		if min_center.y <= max_center.y:
			center.y = clampf(center.y, min_center.y, max_center.y)
		else:
			center.y = visible_rect.position.y + visible_rect.size.y * 0.5

		position = center - half_size


	func _draw() -> void:
		var center := size * 0.5
		var outer_radius := minf(size.x, size.y) * 0.5
		var inner_radius := maxf(outer_radius - progress_width, 1.0)

		draw_circle(center, outer_radius, Color(0.02, 0.05, 0.08, 0.62))
		draw_arc(
			center,
			inner_radius,
			0.0,
			TAU,
			64,
			Color(0.7, 0.9, 1.0, 0.38),
			track_width,
			true
		)
		if progress > 0.0:
			draw_arc(
				center,
				inner_radius,
				-PI * 0.5,
				-PI * 0.5 + TAU * progress,
				64,
				Color(0.2, 0.85, 1.0, 0.95),
				progress_width,
				true
			)


func _ready() -> void:
	_create_hold_indicator()


func _input(p_event: InputEvent) -> void:
	if p_event is InputEventScreenTouch:
		_handle_screen_touch(p_event as InputEventScreenTouch)
	elif p_event is InputEventScreenDrag:
		_handle_screen_drag(p_event as InputEventScreenDrag)
	elif _should_handle_mouse_as_touch() and p_event is InputEventMouseButton:
		_handle_touch_mouse_button(p_event as InputEventMouseButton)
	elif _should_handle_mouse_as_touch() and p_event is InputEventMouseMotion:
		_handle_touch_mouse_motion(p_event as InputEventMouseMotion)


func _unhandled_input(p_event: InputEvent) -> void:
	if p_event is InputEventMouseButton:
		if _should_handle_mouse_as_touch():
			return
		_handle_mouse_button(p_event as InputEventMouseButton)
	elif p_event is InputEventMouseMotion:
		if _should_handle_mouse_as_touch():
			return
		_handle_mouse_motion(p_event as InputEventMouseMotion)
	elif p_event.is_action_pressed("exit"):
		clear_selection()


func _process(delta: float) -> void:
	if not _pointer_active or not _pointer_is_touch or _gesture_canceled:
		return
	if _hold_committed or not _has_touch_selection_action():
		return

	_hold_elapsed += delta
	_update_hold_indicator()

	if _hold_elapsed >= touch_select_hold_seconds:
		_commit_touch_selection_action()
		_hold_committed = true
		_hide_hold_indicator()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _should_ignore_emulated_mouse():
		return

	if event.pressed:
		_begin_pointer(event.position, false)
	else:
		_finish_pointer(event.position, false)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _pointer_active or _pointer_is_touch:
		return
	_update_pointer_position(event.position)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	_ignore_emulated_mouse_until_msec = Time.get_ticks_msec() + 750
	if event.canceled:
		if _pointer_active and _pointer_is_touch and event.index == _pointer_index:
			_reset_pointer()
		return

	if event.pressed:
		if _pointer_active:
			_reset_pointer()
		_pointer_index = event.index
		_begin_pointer(event.position, true)
		return

	if _pointer_active and _pointer_is_touch and event.index == _pointer_index:
		_finish_pointer(event.position, true)


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_ignore_emulated_mouse_until_msec = Time.get_ticks_msec() + 750
	if not _pointer_active or not _pointer_is_touch:
		return
	if event.index != _pointer_index:
		return
	_update_pointer_position(event.position)


func _handle_touch_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _should_ignore_emulated_mouse():
		return

	if event.pressed:
		if _pointer_active:
			_reset_pointer()
		_pointer_index = TOUCH_EMULATED_MOUSE_INDEX
		_begin_pointer(event.position, true)
		return

	if (
		_pointer_active
		and _pointer_is_touch
		and _pointer_index == TOUCH_EMULATED_MOUSE_INDEX
	):
		_finish_pointer(event.position, true)


func _handle_touch_mouse_motion(event: InputEventMouseMotion) -> void:
	if _should_ignore_emulated_mouse():
		return
	if not _pointer_active or not _pointer_is_touch:
		return
	if _pointer_index != TOUCH_EMULATED_MOUSE_INDEX:
		return
	_update_pointer_position(event.position)


func _begin_pointer(screen_position: Vector2, is_touch: bool) -> void:
	_pointer_active = true
	_pointer_is_touch = is_touch
	_press_position = screen_position
	_last_position = screen_position
	_pressed_selectable = _pick_selectable(screen_position)
	_gesture_canceled = false
	_hold_elapsed = 0.0
	_hold_committed = false

	if _should_show_hold_indicator():
		_show_hold_indicator(screen_position)
	else:
		_hide_hold_indicator()


func _update_pointer_position(screen_position: Vector2) -> void:
	_last_position = screen_position
	if _press_position.distance_to(screen_position) < _get_drag_cancel_threshold():
		if _should_show_hold_indicator():
			_update_hold_indicator()
		return

	_gesture_canceled = true
	_hide_hold_indicator()


func _finish_pointer(screen_position: Vector2, is_touch: bool) -> void:
	if not _pointer_active or _pointer_is_touch != is_touch:
		return

	_update_pointer_position(screen_position)

	if not _gesture_canceled and not _hold_committed:
		if _pointer_is_touch:
			if _has_touch_selection_action() and not _touch_action_requires_hold():
				_commit_touch_selection_action()
		else:
			select(_pressed_selectable)

	_reset_pointer()


func _reset_pointer() -> void:
	_pointer_active = false
	_pointer_is_touch = false
	_pointer_index = -1
	_pressed_selectable = null
	_gesture_canceled = false
	_hold_elapsed = 0.0
	_hold_committed = false
	_hide_hold_indicator()


func _pick_selectable(p_position_in_screen_space: Vector2) -> Selectable3D:
	var viewport := get_viewport()
	if viewport == null:
		return null

	# Get main camera.
	var camera := viewport.get_camera_3d()
	if camera == null:
		return null

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
		return null

	var collider := result["collider"] as Node
	var selectable := _find_selectable(collider)
	if selectable == null:
		return null

	return selectable


func has_selection() -> bool:
	return current != null


func clear_selection() -> void:
	select(null)


func select(selectable: Selectable3D) -> void:
	if current == selectable:
		return

	current = selectable
	selection_changed.emit(current)


## Walk up the node tree to find a Selectable3D.
func _find_selectable(p_node: Node) -> Selectable3D:
	var node := p_node
	while node != null:
		if node is Selectable3D:
			return node as Selectable3D
		node = node.get_parent()
	return null


func _create_hold_indicator() -> void:
	_hold_overlay = CanvasLayer.new()
	_hold_overlay.name = "SelectionHoldOverlay"
	_hold_overlay.layer = hold_indicator_layer
	add_child(_hold_overlay)

	_hold_indicator = HoldIndicator.new()
	_hold_indicator.name = "HoldIndicator"
	_hold_indicator.radius = hold_indicator_radius
	_hold_indicator.visible = false
	_hold_overlay.add_child(_hold_indicator)


func _show_hold_indicator(screen_position: Vector2) -> void:
	if _hold_indicator == null:
		return
	_configure_hold_indicator_metrics()
	_hold_indicator.progress = 0.0
	_position_hold_indicator(screen_position)
	_hold_indicator.visible = true


func _update_hold_indicator() -> void:
	if _hold_indicator == null:
		return
	if not _hold_indicator.visible:
		return
	var progress := 1.0
	if touch_select_hold_seconds > 0.0:
		progress = _hold_elapsed / touch_select_hold_seconds
	_hold_indicator.progress = progress
	_position_hold_indicator(_last_position)


func _hide_hold_indicator() -> void:
	if _hold_indicator == null:
		return
	_hold_indicator.visible = false
	_hold_indicator.progress = 0.0


func _should_show_hold_indicator() -> bool:
	return (
		_pointer_active
		and _pointer_is_touch
		and _touch_action_requires_hold()
		and _has_touch_selection_action()
		and not _gesture_canceled
	)


func _has_touch_selection_action() -> bool:
	return _pressed_selectable != null and _pressed_selectable != current


func _touch_action_requires_hold() -> bool:
	if not _pointer_is_touch:
		return false
	return touch_targets_require_hold


func _commit_touch_selection_action() -> void:
	if _has_touch_selection_action():
		select(_pressed_selectable)


func _get_drag_cancel_threshold() -> float:
	if _pointer_is_touch:
		return touch_drag_cancel_threshold
	return pointer_drag_cancel_threshold


func _should_ignore_emulated_mouse() -> bool:
	return Time.get_ticks_msec() < _ignore_emulated_mouse_until_msec


func _should_handle_mouse_as_touch() -> bool:
	return OS.get_name() == "Android"


func _configure_hold_indicator_metrics() -> void:
	if _hold_indicator == null:
		return

	var radius := hold_indicator_radius
	if _pointer_is_touch:
		radius = maxf(radius, _dp_to_screen_pixels(touch_hold_indicator_diameter_dp) * 0.5)
		_hold_indicator.track_width = _dp_to_screen_pixels(2.0)
		_hold_indicator.progress_width = _dp_to_screen_pixels(4.0)
	else:
		_hold_indicator.track_width = 2.0
		_hold_indicator.progress_width = 4.0

	_hold_indicator.radius = radius


func _position_hold_indicator(touch_position: Vector2) -> void:
	if _hold_indicator == null:
		return
	var visible_rect := get_viewport().get_visible_rect()
	var margin := _dp_to_screen_pixels(touch_hold_indicator_screen_margin_dp)
	var center := touch_position

	if _pointer_is_touch:
		var vertical_offset := _dp_to_screen_pixels(touch_hold_indicator_offset_dp)
		center.y -= vertical_offset

		var half_height := _hold_indicator.size.y * 0.5
		var top_center_limit := visible_rect.position.y + half_height + margin
		if center.y < top_center_limit:
			center.y = touch_position.y + vertical_offset

	_hold_indicator.set_center_position(center, visible_rect, margin)


func _dp_to_screen_pixels(dp: float) -> float:
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		dpi = ANDROID_FALLBACK_DPI
	return dp * dpi / ANDROID_BASELINE_DPI
