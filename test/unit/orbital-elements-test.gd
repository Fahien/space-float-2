extends GdUnitTestSuite

const EARTH_MU := 398600441800000.0


func test_circular_orbit_uses_position_as_periapsis_axis() -> void:
	var radius := 7000000.0
	var speed := sqrt(EARTH_MU / radius)
	var elements: Variant = OrbitalElements.from_state_vector(
		Vector3(radius, 0.0, 0.0),
		Vector3(0.0, speed, 0.0),
		EARTH_MU
	)

	assert_bool(elements.is_degenerate()).is_false()
	assert_bool(elements.is_closed()).is_true()
	assert_float(elements.eccentricity).is_equal_approx(0.0, 0.000001)
	assert_float(elements.semi_latus_rectum).is_equal_approx(radius, 0.001)
	assert_float(elements.semi_major_axis).is_equal_approx(radius, 0.001)
	assert_float(elements.periapsis).is_equal_approx(radius, 0.001)
	assert_float(elements.apoapsis).is_equal_approx(radius, 0.001)
	assert_vector(elements.p_hat).is_equal_approx(Vector3.RIGHT, Vector3(0.000001, 0.000001, 0.000001))
	assert_vector(elements.q_hat).is_equal_approx(Vector3.UP, Vector3(0.000001, 0.000001, 0.000001))
	assert_vector(elements.get_orbit_point(0.0)).is_equal_approx(
		Vector3(radius, 0.0, 0.0),
		Vector3(0.001, 0.001, 0.001)
	)


func test_elliptical_orbit_reports_periapsis_and_apoapsis() -> void:
	var periapsis := 7000000.0
	var apoapsis := 13000000.0
	var semi_major_axis := (periapsis + apoapsis) * 0.5
	var eccentricity := (apoapsis - periapsis) / (apoapsis + periapsis)
	var speed_at_periapsis := sqrt(EARTH_MU * (2.0 / periapsis - 1.0 / semi_major_axis))

	var elements: Variant = OrbitalElements.from_state_vector(
		Vector3(periapsis, 0.0, 0.0),
		Vector3(0.0, speed_at_periapsis, 0.0),
		EARTH_MU
	)

	assert_bool(elements.is_degenerate()).is_false()
	assert_bool(elements.is_closed()).is_true()
	assert_float(elements.eccentricity).is_equal_approx(eccentricity, 0.000001)
	assert_float(elements.semi_major_axis).is_equal_approx(semi_major_axis, 0.001)
	assert_float(elements.periapsis).is_equal_approx(periapsis, 0.001)
	assert_float(elements.apoapsis).is_equal_approx(apoapsis, 0.001)
	assert_vector(elements.get_orbit_point(PI)).is_equal_approx(
		Vector3(-apoapsis, 0.0, 0.0),
		Vector3(0.001, 0.001, 0.001)
	)


func test_hyperbolic_orbit_has_no_apoapsis_or_period() -> void:
	var periapsis := 7000000.0
	var eccentricity := 1.5
	var semi_latus_rectum := periapsis * (1.0 + eccentricity)
	var speed_at_periapsis := sqrt(EARTH_MU * semi_latus_rectum) / periapsis

	var elements: Variant = OrbitalElements.from_state_vector(
		Vector3(periapsis, 0.0, 0.0),
		Vector3(0.0, speed_at_periapsis, 0.0),
		EARTH_MU
	)

	assert_bool(elements.is_degenerate()).is_false()
	assert_bool(elements.is_closed()).is_false()
	assert_float(elements.eccentricity).is_equal_approx(eccentricity, 0.000001)
	assert_float(elements.semi_major_axis).is_equal_approx(-14000000.0, 0.001)
	assert_float(elements.periapsis).is_equal_approx(periapsis, 0.001)
	assert_bool(is_inf(elements.apoapsis)).is_true()
	assert_bool(is_inf(elements.orbital_period)).is_true()
	assert_vector(elements.get_orbit_point(0.0)).is_equal_approx(
		Vector3(periapsis, 0.0, 0.0),
		Vector3(0.001, 0.001, 0.001)
	)


func test_near_radial_state_returns_degenerate_elements() -> void:
	var elements: Variant = OrbitalElements.from_state_vector(
		Vector3(7000000.0, 0.0, 0.0),
		Vector3(-100.0, 0.0, 0.0),
		EARTH_MU
	)

	assert_bool(elements.is_degenerate()).is_true()
	assert_vector(elements.get_orbit_point(0.0)).is_equal(Vector3.ZERO)


func test_orbit_point_stays_in_orbital_plane_with_expected_radius() -> void:
	var periapsis := 7000000.0
	var apoapsis := 13000000.0
	var semi_major_axis := (periapsis + apoapsis) * 0.5
	var eccentricity := (apoapsis - periapsis) / (apoapsis + periapsis)
	var semi_latus_rectum := semi_major_axis * (1.0 - eccentricity * eccentricity)
	var speed_at_periapsis := sqrt(EARTH_MU * (2.0 / periapsis - 1.0 / semi_major_axis))
	var elements: Variant = OrbitalElements.from_state_vector(
		Vector3(periapsis, 0.0, 0.0),
		Vector3(0.0, speed_at_periapsis, 0.0),
		EARTH_MU
	)

	var true_anomaly := deg_to_rad(60.0)
	var point: Vector3 = elements.get_orbit_point(true_anomaly)
	var expected_radius := semi_latus_rectum / (1.0 + eccentricity * cos(true_anomaly))

	assert_float(point.length()).is_equal_approx(expected_radius, 0.001)
	assert_float(point.dot(elements.w_hat)).is_equal_approx(0.0, 0.000001)


func test_true_anomaly_for_position_matches_sampled_point() -> void:
	var periapsis := 7000000.0
	var apoapsis := 13000000.0
	var semi_major_axis := (periapsis + apoapsis) * 0.5
	var speed_at_periapsis := sqrt(EARTH_MU * (2.0 / periapsis - 1.0 / semi_major_axis))
	var elements: Variant = OrbitalElements.from_state_vector(
		Vector3(periapsis, 0.0, 0.0),
		Vector3(0.0, speed_at_periapsis, 0.0),
		EARTH_MU
	)

	var true_anomaly := deg_to_rad(60.0)
	var point: Vector3 = elements.get_orbit_point(true_anomaly)

	assert_float(elements.get_true_anomaly_for_position(point)).is_equal_approx(true_anomaly, 0.000001)


func test_earth_iss_reference_values() -> void:
	var radius := 6371000.0 + 420000.0
	var speed := sqrt(EARTH_MU / radius)
	var elements: Variant = OrbitalElements.from_state_vector(
		Vector3(radius, 0.0, 0.0),
		Vector3(0.0, speed, 0.0),
		EARTH_MU
	)

	assert_float(speed).is_equal_approx(7661.29213082409, 0.000001)
	assert_float(elements.semi_major_axis).is_equal_approx(radius, 0.001)
	assert_float(elements.orbital_period).is_equal_approx(5569.440597283014, 0.001)
