extends GdUnitTestSuite


func test_selectable_uses_self_as_default_selection_anchor() -> void:
	var selectable := auto_free(Selectable3D.new()) as Selectable3D

	assert_object(selectable.get_selection_anchor()).is_same(selectable)


func test_selectable_uses_configured_selection_anchor() -> void:
	var selectable := auto_free(Selectable3D.new()) as Selectable3D
	var anchor := auto_free(Node3D.new()) as Node3D
	selectable.anchor = anchor

	assert_object(selectable.get_selection_anchor()).is_same(anchor)


func test_selectable_returns_receiver_and_info_accessors() -> void:
	var selectable := auto_free(Selectable3D.new()) as Selectable3D
	var receiver := auto_free(CommandReceiver.new()) as CommandReceiver
	var info := auto_free(Selectable3DInfo.new()) as Selectable3DInfo

	selectable.command_receiver = receiver
	selectable.info = info

	assert_object(selectable.get_command_receiver()).is_same(receiver)
	assert_object(selectable.get_info()).is_same(info)


func test_selectable_radius_defaults_without_shape() -> void:
	var selectable := auto_free(Selectable3D.new()) as Selectable3D

	assert_float(selectable.get_selection_radius()).is_equal_approx(1.0, 0.000001)


func test_selectable_radius_uses_box_shape_extents() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 4.0, 4.0)
	var selectable := _selectable_with_shape(shape)

	assert_float(selectable.get_selection_radius()).is_equal_approx(3.0, 0.000001)


func test_selectable_radius_uses_sphere_radius() -> void:
	var shape := SphereShape3D.new()
	shape.radius = 2.5
	var selectable := _selectable_with_shape(shape)

	assert_float(selectable.get_selection_radius()).is_equal_approx(2.5, 0.000001)


func test_selectable_radius_uses_capsule_larger_axis() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 1.0
	shape.height = 6.0
	var selectable := _selectable_with_shape(shape)

	assert_float(selectable.get_selection_radius()).is_equal_approx(3.0, 0.000001)


func _selectable_with_shape(shape: Shape3D) -> Selectable3D:
	var selectable := auto_free(Selectable3D.new()) as Selectable3D
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = shape
	selectable.add_child(collision_shape)
	return selectable
