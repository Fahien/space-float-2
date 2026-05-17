extends GdUnitTestSuite


func test_aerodynamic_drag_is_zero_without_relative_air_speed() -> void:
	var aerodynamics := AerodynamicsModel.new()

	assert_vector(
		aerodynamics.get_drag_force(Vector3.ZERO, 1.2)
	).is_equal(Vector3.ZERO)


func test_aerodynamic_drag_is_zero_when_disabled_or_without_air() -> void:
	var aerodynamics := AerodynamicsModel.new()

	aerodynamics.enabled = false
	assert_vector(
		aerodynamics.get_drag_force(Vector3(10.0, 0.0, 0.0), 1.2)
	).is_equal(Vector3.ZERO)

	aerodynamics.enabled = true
	assert_vector(
		aerodynamics.get_drag_force(Vector3(10.0, 0.0, 0.0), 0.0)
	).is_equal(Vector3.ZERO)


func test_aerodynamic_drag_points_opposite_velocity_with_expected_magnitude() -> void:
	var aerodynamics := AerodynamicsModel.new()
	aerodynamics.drag_coefficient = 2.0
	aerodynamics.reference_area = 0.5

	var drag := aerodynamics.get_drag_force(Vector3(3.0, 4.0, 0.0), 1.0)

	assert_vector(drag).is_equal_approx(Vector3(-7.5, -10.0, 0.0), Vector3(0.000001, 0.000001, 0.000001))
	assert_float(drag.length()).is_equal_approx(12.5, 0.000001)
