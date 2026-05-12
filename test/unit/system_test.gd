extends GdUnitTestSuite

const CelestialBodySystemScript := preload("res://scene/system/celestial-body-system.gd")


func test_celestial_body_gravity_uses_inverse_square_outside_radius() -> void:
	var body := _body_in_tree(Vector3.ZERO, 10.0, 1000.0)

	assert_vector(body.acceleration_at(Vector3(20.0, 0.0, 0.0))).is_equal_approx(
		Vector3(-2.5, 0.0, 0.0),
		Vector3(0.000001, 0.000001, 0.000001)
	)
	assert_vector(body.acceleration_at(Vector3.ZERO)).is_equal(Vector3.ZERO)


func test_celestial_body_gravity_uses_uniform_sphere_inside_radius() -> void:
	var body := _body_in_tree(Vector3.ZERO, 10.0, 1000.0)

	assert_vector(body.acceleration_at(Vector3(5.0, 0.0, 0.0))).is_equal_approx(
		Vector3(-5.0, 0.0, 0.0),
		Vector3(0.000001, 0.000001, 0.000001)
	)


func test_celestial_body_altitude_and_up_vector() -> void:
	var body := _body_in_tree(Vector3(1.0, 2.0, 3.0), 10.0, 0.0)

	assert_float(body.get_altitude_at(Vector3(1.0, 15.0, 3.0))).is_equal_approx(3.0, 0.000001)
	assert_vector(body.get_up_at(Vector3(1.0, 15.0, 3.0))).is_equal(Vector3.UP)
	assert_vector(body.get_up_at(Vector3(1.0, 2.0, 3.0))).is_equal(Vector3.ZERO)


func test_celestial_body_system_registers_sources_once_and_sums_acceleration() -> void:
	var system: Variant = auto_free(CelestialBodySystemScript.new())

	var body_a := _body_in_tree(Vector3(10.0, 0.0, 0.0), 0.0, 100.0)

	var body_b := _body_in_tree(Vector3(0.0, 20.0, 0.0), 0.0, 200.0)

	system.register_source(body_a)
	system.register_source(body_a)
	system.register_source(body_b)

	assert_vector(system.gravity_acceleration_at(Vector3.ZERO)).is_equal_approx(
		Vector3(1.0, 0.5, 0.0),
		Vector3(0.000001, 0.000001, 0.000001)
	)

	system.unregister_source(body_a)

	assert_vector(system.gravity_acceleration_at(Vector3.ZERO)).is_equal_approx(
		Vector3(0.0, 0.5, 0.0),
		Vector3(0.000001, 0.000001, 0.000001)
	)


func _body_in_tree(p_position: Vector3, p_radius: float, p_mu: float) -> CelestialBodyModel:
	var body := auto_free(CelestialBodyModel.new()) as CelestialBodyModel
	add_child(body)
	body.global_position = p_position
	body.radius = p_radius
	body.mu = p_mu
	return body
