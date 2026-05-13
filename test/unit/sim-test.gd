## Chapter: Small Atmosphere and Drag Resources
##
## The simulation helpers in this file are deliberately modest. `AtmosphereModel`
## supplies a first Earth-style vertical column through instance methods.
## `AerodynamicsModel` supplies the vessel-side drag resource: enable state,
## coefficient, reference area, and the quadratic force law. The tests keep those
## responsibilities separate so planet-owned atmosphere data can grow without
## turning drag into an Earth-only helper.
##
## The assertions use fixed boundary altitudes and simple velocity vectors. They
## serve as reference points for active vessel work: density comes from the local
## environment, while the vessel resource determines whether drag exists and how
## strongly it reacts to relative airflow.
extends GdUnitTestSuite


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
