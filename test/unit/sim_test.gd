extends GdUnitTestSuite


func test_atmosphere_zone_boundaries() -> void:
	assert_int(AtmosphereModel.get_zone_at(-100.0)).is_equal(AtmosphereModel.Zone.TROPOSPHERE)
	assert_int(AtmosphereModel.get_zone_at(0.0)).is_equal(AtmosphereModel.Zone.TROPOSPHERE)
	assert_int(AtmosphereModel.get_zone_at(10999.0)).is_equal(AtmosphereModel.Zone.TROPOSPHERE)
	assert_int(AtmosphereModel.get_zone_at(11000.0)).is_equal(AtmosphereModel.Zone.LOWER_STRATOSPHERE)
	assert_int(AtmosphereModel.get_zone_at(24999.0)).is_equal(AtmosphereModel.Zone.LOWER_STRATOSPHERE)
	assert_int(AtmosphereModel.get_zone_at(25000.0)).is_equal(AtmosphereModel.Zone.UPPER_STRATOSPHERE)


func test_atmosphere_temperature_pressure_and_density() -> void:
	assert_float(AtmosphereModel.get_temperature_at(-50.0)).is_equal_approx(15.04, 0.0001)
	assert_float(AtmosphereModel.get_temperature_at(10000.0)).is_equal_approx(-49.86, 0.0001)
	assert_float(AtmosphereModel.get_temperature_at(15000.0)).is_equal_approx(-56.46, 0.0001)
	assert_float(AtmosphereModel.get_temperature_at(30000.0)).is_equal_approx(-41.51, 0.0001)

	assert_float(AtmosphereModel.get_pressure_at(0.0)).is_equal_approx(101.40, 0.01)
	assert_float(AtmosphereModel.get_density_at(0.0)).is_equal_approx(1.226, 0.001)
	assert_float(AtmosphereModel.get_density_at(30000.0)).is_equal_approx(0.01748, 0.0001)


func test_aerodynamic_drag_is_zero_without_relative_air_speed() -> void:
	assert_vector(
		AerodynamicsModel.get_drag_force(Vector3.ZERO, 1.2, 0.5, 2.0)
	).is_equal(Vector3.ZERO)


func test_aerodynamic_drag_points_opposite_velocity_with_expected_magnitude() -> void:
	var drag := AerodynamicsModel.get_drag_force(Vector3(3.0, 4.0, 0.0), 1.0, 2.0, 0.5)

	assert_vector(drag).is_equal_approx(Vector3(-7.5, -10.0, 0.0), Vector3(0.000001, 0.000001, 0.000001))
	assert_float(drag.length()).is_equal_approx(12.5, 0.000001)
