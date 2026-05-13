extends GdUnitTestSuite


func test_propellant_model_clamps_mass_and_consumes_propellant() -> void:
	var propellant_model := auto_free(PropellantModel.new()) as PropellantModel
	propellant_model.dry_mass = -5.0
	propellant_model.propellant_mass = 3.0

	assert_float(propellant_model.dry_mass).is_zero()
	assert_float(propellant_model.get_total_mass()).is_equal_approx(3.0, 0.000001)
	assert_float(propellant_model.consume_propellant(0.5, 4.0)).is_equal_approx(2.0, 0.000001)
	assert_float(propellant_model.get_propellant_mass()).is_equal_approx(1.0, 0.000001)
	assert_float(propellant_model.consume_propellant(1.0, 4.0)).is_equal_approx(1.0, 0.000001)
	assert_float(propellant_model.get_total_mass()).is_zero()


func test_engine_command_sets_type_and_preserves_payload() -> void:
	var command := EngineCommand.new(0.75, Vector3(1.0, -0.5, 0.25))

	assert_int(command.type).is_equal(Command.Type.ENGINE)
	assert_float(command.throttle).is_equal_approx(0.75, 0.000001)
	assert_vector(command.gimbal).is_equal(Vector3(1.0, -0.5, 0.25))


func test_engine_command_receiver_applies_engine_commands_only() -> void:
	var engine_model := auto_free(EngineModel.new()) as EngineModel
	var receiver := auto_free(EngineCommandReceiver.new()) as EngineCommandReceiver
	receiver.engine_model = engine_model

	receiver.receive_command(EngineCommand.new(1.5, Vector3(2.0, -3.0, 9.0)))

	assert_float(engine_model.get_throttle()).is_equal_approx(1.0, 0.000001)
	assert_vector(engine_model.get_gimbal()).is_equal(Vector2(1.0, -1.0))

	receiver.receive_command(Command.new())

	assert_float(engine_model.get_throttle()).is_equal_approx(1.0, 0.000001)
	assert_vector(engine_model.get_gimbal()).is_equal(Vector2(1.0, -1.0))


func test_engine_model_resolves_propulsion_step_against_propellant_supply() -> void:
	var propellant_model := auto_free(PropellantModel.new()) as PropellantModel
	propellant_model.propellant_mass = 0.5

	var propulsion_model := PropulsionModel.new()
	propulsion_model.max_thrust_newtons = 100.0
	propulsion_model.max_propellant_flow_kg_per_s = 2.0

	var engine_model := auto_free(EngineModel.new()) as EngineModel
	engine_model.propellant_model = propellant_model
	engine_model.propulsion_model = propulsion_model
	engine_model.set_throttle(2.0)

	assert_float(engine_model.get_throttle()).is_equal_approx(1.0, 0.000001)
	assert_float(engine_model.get_thrust_magnitude()).is_equal_approx(100.0, 0.000001)
	assert_float(engine_model.resolve_propulsion_step(0.25)).is_equal_approx(100.0, 0.000001)
	assert_float(propellant_model.get_propellant_mass()).is_zero()
	assert_float(engine_model.resolve_propulsion_step(0.25)).is_zero()


func test_engine_model_clears_reported_thrust_when_throttle_released() -> void:
	var propellant_model := auto_free(PropellantModel.new()) as PropellantModel
	propellant_model.propellant_mass = 10.0

	var propulsion_model := PropulsionModel.new()
	propulsion_model.max_thrust_newtons = 100.0
	propulsion_model.max_propellant_flow_kg_per_s = 1.0

	var info := auto_free(Selectable3DInfo.new()) as Selectable3DInfo
	var engine_model := auto_free(EngineModel.new()) as EngineModel
	engine_model.propellant_model = propellant_model
	engine_model.propulsion_model = propulsion_model
	engine_model.info = info

	engine_model.set_throttle(1.0)
	engine_model._cache_thrust_force(engine_model.resolve_propulsion_step(0.25), Basis.IDENTITY)
	engine_model._update_info()

	var burning_thrust: Vector3 = info.info["thrust"]
	assert_float(burning_thrust.length()).is_greater(0.0)

	engine_model.set_throttle(0.0)
	engine_model._cache_thrust_force(engine_model.resolve_propulsion_step(0.25), Basis.IDENTITY)
	engine_model._update_info()

	assert_vector(info.info["thrust"]).is_equal(Vector3.ZERO)


func test_engine_model_reports_current_primary_body_name() -> void:
	var propellant_model := auto_free(PropellantModel.new()) as PropellantModel
	var info := auto_free(Selectable3DInfo.new()) as Selectable3DInfo
	var engine_model := auto_free(EngineModel.new()) as EngineModel
	var body := auto_free(CelestialBodyModel.new()) as CelestialBodyModel
	body.name = "Earth"
	engine_model.propellant_model = propellant_model
	engine_model.info = info

	engine_model._update_info()

	assert_str(info.info["celestial_body"]).is_equal("None")

	engine_model.current_primary = body
	engine_model._update_info()

	assert_str(info.info["celestial_body"]).is_equal("Earth")


func test_engine_model_slews_gimbal_angles() -> void:
	var propulsion_model := PropulsionModel.new()
	propulsion_model.max_gimbal_pitch_degrees = 10.0
	propulsion_model.max_gimbal_yaw_degrees = 5.0
	propulsion_model.gimbal_slew_degrees_per_second = 30.0

	var engine_model := auto_free(EngineModel.new()) as EngineModel
	engine_model.propulsion_model = propulsion_model
	engine_model.set_gimbal(Vector3(2.0, -2.0, 1.0))

	assert_vector(engine_model.get_gimbal()).is_equal(Vector2(1.0, -1.0))

	engine_model.resolve_gimbal_step(0.25)

	assert_vector(engine_model.get_gimbal_angles_degrees()).is_equal_approx(
		Vector2(7.5, -5.0),
		Vector2(0.0001, 0.0001)
	)
