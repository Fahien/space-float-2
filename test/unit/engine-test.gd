## Chapter: Engine Tests for the Single-Body Vessel
##
## These tests mark the boundary between the old engine-as-rigid-body prototype
## and the current component model. They keep the propulsion contract honest:
## commands still clamp throttle and gimbal input, fuel still limits thrust,
## selection data still reports the vessel's environment, and the authored LAMAE
## scene now contains exactly one rigid body.
##
## The suite is intentionally close to the public script API. A future refactor
## may change visuals or scene nesting, but it should preserve the same outcomes:
## component dry mass stays separate from tank mass, propellant burn updates the
## vessel mass ledger, engine thrust resolves through the vessel mount frame,
## throttle wakes a sleeping parent body, and no joint is required for the engine
## and tank to fly as one craft.
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
	var vessel = auto_free(VesselRigidBody3D.new())
	var engine_model := EngineModel.new()
	var body := auto_free(CelestialBody3D.new()) as CelestialBody3D
	body.name = "Earth"
	vessel.add_child(engine_model)
	engine_model.propellant_model = propellant_model
	engine_model.info = info

	engine_model._update_info()

	assert_str(info.info["celestial_body"]).is_equal("None")

	vessel.current_primary = body
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


func test_engine_model_component_mass_excludes_propellant_tank() -> void:
	var propellant_model := auto_free(PropellantModel.new()) as PropellantModel
	propellant_model.dry_mass = 10.0
	propellant_model.propellant_mass = 90.0

	var engine_model := auto_free(EngineModel.new()) as EngineModel
	engine_model.engine_mass = 125.0
	engine_model.propellant_model = propellant_model

	assert_float(engine_model.get_total_mass()).is_equal_approx(125.0, 0.000001)
	assert_float(propellant_model.get_total_mass()).is_equal_approx(100.0, 0.000001)


func test_engine_model_resolves_vessel_force_and_offset_from_mount_frame() -> void:
	var propellant_model := auto_free(PropellantModel.new()) as PropellantModel
	propellant_model.propellant_mass = 10.0

	var propulsion_model := PropulsionModel.new()
	propulsion_model.max_thrust_newtons = 100.0
	propulsion_model.max_propellant_flow_kg_per_s = 1.0

	var engine_model := auto_free(EngineModel.new()) as EngineModel
	engine_model.propellant_model = propellant_model
	engine_model.propulsion_model = propulsion_model
	engine_model.transform = Transform3D(
		Basis(Vector3.FORWARD, PI * 0.5),
		Vector3(1.0, 2.0, 3.0)
	)
	engine_model.thrust_origin_local = Vector3(0.0, -0.5, 0.25)
	engine_model.set_throttle(1.0)
	var body_transform := Transform3D(
		Basis(Vector3.RIGHT, PI * 0.5),
		Vector3(10.0, 20.0, 30.0)
	)

	var force := engine_model.resolve_vessel_force(0.25, body_transform)
	var expected_direction := (
		body_transform.basis
		* engine_model.transform.basis
		* Vector3.UP
	).normalized()
	var expected_offset := (
		body_transform.basis
		* (
			engine_model.transform.origin
			+ engine_model.transform.basis * engine_model.thrust_origin_local
		)
	)

	assert_vector(force).is_equal_approx(
		expected_direction * 100.0,
		Vector3(0.000001, 0.000001, 0.000001)
	)
	assert_vector(engine_model.get_vessel_force_offset(body_transform)).is_equal_approx(
		expected_offset,
		Vector3(0.000001, 0.000001, 0.000001)
	)


func test_engine_model_wakes_parent_vessel_when_throttle_opens() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var engine_model := EngineModel.new()
	vessel.add_child(engine_model)
	vessel.sleeping = true

	engine_model.set_throttle(0.0)

	assert_bool(vessel.sleeping).is_true()

	engine_model.set_throttle(1.0)

	assert_bool(vessel.sleeping).is_false()


func test_lamae_scene_uses_one_rigid_body_and_component_masses() -> void:
	var scene := load("res://scene/engine/lamae.tscn") as PackedScene
	var vessel = auto_free(scene.instantiate())
	add_child(vessel)

	var rigid_bodies: Array[Node] = []
	var joints: Array[Node] = []
	_collect_rigid_bodies_and_joints(vessel, rigid_bodies, joints)

	assert_int(rigid_bodies.size()).is_equal(1)
	assert_object(rigid_bodies[0]).is_same(vessel)
	assert_int(joints.size()).is_equal(0)

	var engine := vessel.get_node("LemaeEngine") as EngineModel
	var tank := vessel.get_node("PropellantTank") as PropellantModel

	assert_object(engine).is_not_null()
	assert_object(tank).is_not_null()
	assert_float(engine.get_total_mass()).is_equal_approx(100.0, 0.000001)
	assert_float(tank.get_total_mass()).is_equal_approx(100.0, 0.000001)
	assert_float(vessel.get_total_mass()).is_equal_approx(200.0, 0.000001)

	tank.consume_propellant(1.0, 10.0)

	assert_float(vessel.get_total_mass()).is_equal_approx(190.0, 0.000001)
	assert_float(vessel.mass).is_equal_approx(190.0, 0.000001)


func _collect_rigid_bodies_and_joints(
	node: Node,
	rigid_bodies: Array[Node],
	joints: Array[Node]
) -> void:
	if node is RigidBody3D:
		rigid_bodies.append(node)
	if node is Joint3D:
		joints.append(node)

	for child in node.get_children():
		_collect_rigid_bodies_and_joints(child, rigid_bodies, joints)
