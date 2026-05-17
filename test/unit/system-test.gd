extends GdUnitTestSuite

const CelestialBodySystemScript := preload("res://scene/system/celestial-body-system.gd")


func test_atmosphere_zone_boundaries() -> void:
	var atmosphere := AtmosphereModel.new()

	assert_int(atmosphere.get_zone_at(-100.0)).is_equal(AtmosphereModel.Zone.TROPOSPHERE)
	assert_int(atmosphere.get_zone_at(0.0)).is_equal(AtmosphereModel.Zone.TROPOSPHERE)
	assert_int(atmosphere.get_zone_at(10999.0)).is_equal(AtmosphereModel.Zone.TROPOSPHERE)
	assert_int(atmosphere.get_zone_at(11000.0)).is_equal(AtmosphereModel.Zone.LOWER_STRATOSPHERE)
	assert_int(atmosphere.get_zone_at(24999.0)).is_equal(AtmosphereModel.Zone.LOWER_STRATOSPHERE)
	assert_int(atmosphere.get_zone_at(25000.0)).is_equal(AtmosphereModel.Zone.UPPER_STRATOSPHERE)


func test_atmosphere_temperature_pressure_and_density() -> void:
	var atmosphere := AtmosphereModel.new()

	assert_float(atmosphere.get_temperature_at(-50.0)).is_equal_approx(15.04, 0.0001)
	assert_float(atmosphere.get_temperature_at(10000.0)).is_equal_approx(-49.86, 0.0001)
	assert_float(atmosphere.get_temperature_at(15000.0)).is_equal_approx(-56.46, 0.0001)
	assert_float(atmosphere.get_temperature_at(30000.0)).is_equal_approx(-41.51, 0.0001)

	assert_float(atmosphere.get_pressure_at(0.0)).is_equal_approx(101.40, 0.01)
	assert_float(atmosphere.get_density_at(0.0)).is_equal_approx(1.226, 0.001)
	assert_float(atmosphere.get_density_at(30000.0)).is_equal_approx(0.01748, 0.0001)


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


func test_celestial_body_system_strongest_source_selects_largest_acceleration() -> void:
	var system: Variant = auto_free(CelestialBodySystemScript.new())

	var weak_near_source := _body_in_tree(Vector3(10.0, 0.0, 0.0), 0.0, 100.0)
	var strong_far_source := _body_in_tree(Vector3(0.0, 20.0, 0.0), 0.0, 800.0)

	system.register_source(weak_near_source)
	system.register_source(strong_far_source)

	assert_object(system.strongest_source_at(Vector3.ZERO)).is_same(strong_far_source)


func test_celestial_body_system_strongest_source_ignores_null_and_invalid_sources() -> void:
	var system: Variant = auto_free(CelestialBodySystemScript.new())

	var invalid_source := CelestialBody3D.new()
	system.register_source(null)
	system.register_source(invalid_source)
	invalid_source.free()

	assert_object(system.strongest_source_at(Vector3.ZERO)).is_null()


func test_celestial_body_system_local_down_uses_gravity_direction() -> void:
	var system: Variant = auto_free(CelestialBodySystemScript.new())
	var body := _body_in_tree(Vector3(10.0, 0.0, 0.0), 0.0, 100.0)

	system.register_source(body)

	assert_vector(system.local_down_at(Vector3.ZERO)).is_equal_approx(
		Vector3.RIGHT,
		Vector3(0.000001, 0.000001, 0.000001)
	)


func test_celestial_body_system_local_down_falls_back_without_gravity() -> void:
	var system: Variant = auto_free(CelestialBodySystemScript.new())

	assert_vector(system.local_down_at(Vector3.ZERO)).is_equal(Vector3.DOWN)


func test_gravity_rigid_body_caches_current_primary_during_physics_step() -> void:
	var source := _body_in_tree(Vector3(10.0, 0.0, 0.0), 0.0, 100.0)
	var body := auto_free(GravityRigidBody3D.new()) as GravityRigidBody3D
	body.mass = 1.0
	add_child(body)
	body.global_position = Vector3.ZERO

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_object(body.current_primary).is_same(source)


func _body_in_tree(p_position: Vector3, p_radius: float, p_mu: float) -> CelestialBody3D:
	var body := auto_free(CelestialBody3D.new()) as CelestialBody3D
	add_child(body)
	body.global_position = p_position
	body.radius = p_radius
	body.mu = p_mu
	return body
