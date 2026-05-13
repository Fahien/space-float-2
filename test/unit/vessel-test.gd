extends GdUnitTestSuite


func test_mass_model_reports_and_consumes_propellant() -> void:
	var mass_model := MassModel.new()
	mass_model.dry_mass = 10.0
	mass_model.propellant_mass = 5.0

	assert_float(mass_model.get_mass()).is_equal_approx(15.0, 0.000001)
	assert_float(mass_model.consume_propellant(0.5, 4.0)).is_equal_approx(2.0, 0.000001)
	assert_float(mass_model.get_propellant_mass()).is_equal_approx(3.0, 0.000001)
	assert_float(mass_model.consume_propellant(2.0, 4.0)).is_equal_approx(3.0, 0.000001)
	assert_float(mass_model.get_mass()).is_equal_approx(10.0, 0.000001)


func test_mass_model_ignores_non_positive_burn_inputs() -> void:
	var mass_model := MassModel.new()
	mass_model.propellant_mass = 5.0

	assert_float(mass_model.consume_propellant(0.0, 1.0)).is_zero()
	assert_float(mass_model.consume_propellant(1.0, 0.0)).is_zero()
	assert_float(mass_model.get_propellant_mass()).is_equal_approx(5.0, 0.000001)


func test_propulsion_model_clamps_throttle_and_gimbal_targets() -> void:
	var propulsion_model := PropulsionModel.new()
	propulsion_model.max_thrust_newtons = 100.0
	propulsion_model.max_propellant_flow_kg_per_s = 4.0
	propulsion_model.max_gimbal_pitch_degrees = 10.0
	propulsion_model.max_gimbal_yaw_degrees = 5.0
	propulsion_model.max_gimbal_roll_degrees = 20.0

	assert_float(propulsion_model.get_thrust_magnitude(1.5)).is_equal_approx(100.0, 0.000001)
	assert_float(propulsion_model.get_thrust_magnitude(-1.0)).is_zero()
	assert_float(propulsion_model.get_propellant_flow(0.25)).is_equal_approx(1.0, 0.000001)

	var target := propulsion_model.get_gimbal_target_angles(Vector3(2.0, -2.0, 0.5))
	assert_vector(target).is_equal_approx(
		Vector3(deg_to_rad(10.0), deg_to_rad(-5.0), deg_to_rad(10.0)),
		Vector3(0.000001, 0.000001, 0.000001)
	)


func test_vessel_state_clamps_throttle_and_resolves_fuel_limited_thrust() -> void:
	var mass_model := MassModel.new()
	mass_model.dry_mass = 10.0
	mass_model.propellant_mass = 2.0

	var propulsion_model := PropulsionModel.new()
	propulsion_model.max_thrust_newtons = 100.0
	propulsion_model.max_propellant_flow_kg_per_s = 2.0

	var state := VesselState.new()
	state.configure_models(mass_model, propulsion_model)
	state.set_throttle(2.0)

	assert_float(state.get_throttle()).is_equal_approx(1.0, 0.000001)
	assert_float(state.resolve_propulsion_step(0.25)).is_equal_approx(100.0, 0.000001)
	assert_float(state.get_propellant_mass()).is_equal_approx(1.5, 0.000001)
	assert_float(state.resolve_propulsion_step(1.0)).is_equal_approx(75.0, 0.000001)
	assert_float(state.get_propellant_mass()).is_zero()
	assert_float(state.resolve_propulsion_step(1.0)).is_zero()


func test_vessel_state_duplicates_configured_models() -> void:
	var mass_model := MassModel.new()
	mass_model.dry_mass = 10.0
	mass_model.propellant_mass = 1.0

	var propulsion_model := PropulsionModel.new()
	propulsion_model.max_thrust_newtons = 100.0
	propulsion_model.max_propellant_flow_kg_per_s = 1.0

	var state := VesselState.new()
	state.configure_models(mass_model, propulsion_model)
	mass_model.propellant_mass = 10.0
	propulsion_model.max_thrust_newtons = 500.0

	state.set_throttle(1.0)

	assert_float(state.get_propellant_mass()).is_equal_approx(1.0, 0.000001)
	assert_float(state.get_thrust_magnitude()).is_equal_approx(100.0, 0.000001)
	assert_float(state.resolve_propulsion_step(0.5)).is_equal_approx(100.0, 0.000001)
	assert_float(mass_model.get_propellant_mass()).is_equal_approx(10.0, 0.000001)


func test_vessel_state_stores_gimbal_command_and_slews_actual_angles() -> void:
	var propulsion_model := PropulsionModel.new()
	propulsion_model.max_gimbal_pitch_degrees = 10.0
	propulsion_model.max_gimbal_yaw_degrees = 5.0
	propulsion_model.max_gimbal_roll_degrees = 20.0
	propulsion_model.gimbal_slew_degrees_per_second = 30.0

	var state := VesselState.new()
	state.configure_models(null, propulsion_model)
	state.set_gimbal_command(Vector3(2.0, -2.0, 0.5))

	assert_vector(state.get_gimbal_command()).is_equal(Vector3(1.0, -1.0, 0.5))
	assert_vector(state.get_gimbal_angles()).is_equal(Vector3.ZERO)

	state.resolve_gimbal_step(0.25)

	assert_vector(state.get_gimbal_angles_degrees()).is_equal_approx(
		Vector3(7.5, -5.0, 7.5),
		Vector3(0.0001, 0.0001, 0.0001)
	)

	state.resolve_gimbal_step(1.0)

	assert_vector(state.get_gimbal_angles_degrees()).is_equal_approx(
		Vector3(10.0, -5.0, 10.0),
		Vector3(0.0001, 0.0001, 0.0001)
	)
