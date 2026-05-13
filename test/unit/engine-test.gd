## Chapter: Proving the Single-Body Vessel
##
## These tests mark the boundary between the early engine-as-rigid-body
## prototype and the current compound-body design. They guard every contract
## that changed when the architecture collapsed multiple rigid bodies into one
## `VesselRigidBody3D` with child `MassModel` components.
##
## The first group of cases covers the mass ledger: component dry mass stays
## separate from tank mass, the vessel aggregates only direct `MassModel`
## children, center of mass shifts with component placement, and propellant
## burn updates the vessel's total mass in real time.
##
## The propulsion cases verify that throttle clamps to [0, 1], gimbal commands
## clamp per axis, fuel limits thrust proportionally when the tank runs dry
## partway through a step, and the mount-frame transform converts local thrust
## into the correct scene-space force and offset.
##
## A third group tests `VesselCommandReceiver`, the vessel-level node that
## replaced per-engine command wiring. The receiver discovers engines from its
## parent, fans `EngineCommand` payloads to every active engine, ignores
## unrelated command types, and respects a manually narrowed engine subset for
## staging transitions.
##
## The final integration cases load the authored LAMAE scene and assert the
## structural invariants: exactly one rigid body, zero joints, vessel-level
## selectable and command receiver wired to a shared `Selectable3DInfo`, and
## component masses that sum correctly and track propellant consumption through
## the vessel's Jolt body.
extends GdUnitTestSuite


class FixedMassModel:
	extends MassModel

	var reported_mass := 0.0

	func get_total_mass() -> float:
		return reported_mass


class LooseMassNode:
	extends Node3D

	func get_total_mass() -> float:
		return 999.0


func test_mass_model_notifies_immediate_parent_vessel() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var component := FixedMassModel.new()
	component.reported_mass = 12.5
	vessel.add_child(component)

	assert_object(component.get_vessel_body()).is_same(vessel)

	component.notify_mass_changed()

	assert_float(vessel.mass).is_equal_approx(12.5, 0.000001)
	assert_vector(vessel.center_of_mass).is_equal(Vector3.ZERO)


func test_vessel_mass_ledger_uses_direct_mass_models_only() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D

	var light_component := FixedMassModel.new()
	light_component.reported_mass = 10.0
	light_component.position = Vector3(-1.0, 0.0, 0.0)
	vessel.add_child(light_component)

	var heavy_component := FixedMassModel.new()
	heavy_component.reported_mass = 30.0
	heavy_component.position = Vector3(1.0, 0.0, 0.0)
	vessel.add_child(heavy_component)

	var negative_component := FixedMassModel.new()
	negative_component.reported_mass = -20.0
	negative_component.position = Vector3(0.0, 10.0, 0.0)
	vessel.add_child(negative_component)

	var loose_node := LooseMassNode.new()
	vessel.add_child(loose_node)

	var nested_component := FixedMassModel.new()
	nested_component.reported_mass = 500.0
	loose_node.add_child(nested_component)

	assert_int(vessel.get_mass_components().size()).is_equal(3)
	assert_float(vessel.get_total_mass()).is_equal_approx(40.0, 0.000001)
	assert_vector(vessel.get_center_of_mass_from_components()).is_equal_approx(
		Vector3(0.5, 0.0, 0.0),
		Vector3(0.000001, 0.000001, 0.000001)
	)


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


func test_vessel_command_receiver_updates_info_with_throttle_state() -> void:
	var propellant_model := auto_free(PropellantModel.new()) as PropellantModel
	propellant_model.propellant_mass = 10.0

	var propulsion_model := PropulsionModel.new()
	propulsion_model.max_thrust_newtons = 100.0
	propulsion_model.max_propellant_flow_kg_per_s = 1.0

	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var engine_model := EngineModel.new()
	engine_model.propellant_model = propellant_model
	engine_model.propulsion_model = propulsion_model
	vessel.add_child(engine_model)

	var info := auto_free(Selectable3DInfo.new()) as Selectable3DInfo
	var receiver := VesselCommandReceiver.new()
	receiver.info = info
	vessel.add_child(receiver)

	engine_model.set_throttle(1.0)
	engine_model.set_gimbal(Vector3(0.5, -0.3, 0.0))
	receiver._update_info()

	assert_float(info.info["throttle"]).is_equal_approx(1.0, 0.000001)
	assert_vector(info.info["gimbal"]).is_equal(Vector2(0.5, -0.3))

	engine_model.set_throttle(0.0)
	receiver._update_info()

	assert_float(info.info["throttle"]).is_zero()


func test_vessel_command_receiver_reports_current_primary_body_name() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var engine_model := EngineModel.new()
	vessel.add_child(engine_model)

	var info := auto_free(Selectable3DInfo.new()) as Selectable3DInfo
	var receiver := VesselCommandReceiver.new()
	receiver.info = info
	vessel.add_child(receiver)
	add_child(vessel)

	var body := auto_free(CelestialBody3D.new()) as CelestialBody3D
	body.name = "Earth"
	add_child(body)

	receiver._update_info()

	assert_str(info.info["celestial_body"]).is_equal("None")

	vessel.current_primary = body
	receiver._update_info()

	assert_str(info.info["celestial_body"]).is_equal("Earth")


func test_vessel_command_receiver_reports_orbital_parameters() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D

	var info := auto_free(Selectable3DInfo.new()) as Selectable3DInfo
	var receiver := VesselCommandReceiver.new()
	receiver.info = info
	vessel.add_child(receiver)
	add_child(vessel)
	vessel.global_position = Vector3(20.0, 0.0, 0.0)
	vessel.linear_velocity = Vector3(0.0, sqrt(100.0 / 20.0), 0.0)

	var body := auto_free(CelestialBody3D.new()) as CelestialBody3D
	body.name = "Primary"
	body.radius = 10.0
	body.mu = 100.0
	add_child(body)
	vessel.current_primary = body

	receiver._update_info()

	assert_float(info.info["eccentricity"]).is_equal_approx(0.0, 0.000001)
	assert_float(info.info["periapsis"]).is_equal_approx(10.0, 0.000001)
	assert_float(info.info["apoapsis"]).is_equal_approx(10.0, 0.000001)


func test_vessel_command_receiver_aggregates_propellant_mass_in_info() -> void:
	var tank_a := auto_free(PropellantModel.new()) as PropellantModel
	tank_a.propellant_mass = 20.0
	var tank_b := auto_free(PropellantModel.new()) as PropellantModel
	tank_b.propellant_mass = 30.0

	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var engine_a := EngineModel.new()
	engine_a.propellant_model = tank_a
	var engine_b := EngineModel.new()
	engine_b.propellant_model = tank_b
	vessel.add_child(engine_a)
	vessel.add_child(engine_b)

	var info := auto_free(Selectable3DInfo.new()) as Selectable3DInfo
	var receiver := VesselCommandReceiver.new()
	receiver.info = info
	vessel.add_child(receiver)

	receiver._update_info()

	assert_float(info.info["propellant_mass"]).is_equal_approx(50.0, 0.000001)
	assert_str(info.info["name"]).is_equal(vessel.name)


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


func test_engine_model_mass_clamps_and_notifies_parent_vessel() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var engine_model := EngineModel.new()
	vessel.add_child(engine_model)

	engine_model.engine_mass = 42.0

	assert_object(engine_model).is_instanceof(MassModel)
	assert_float(vessel.mass).is_equal_approx(42.0, 0.000001)

	engine_model.engine_mass = -3.0

	assert_float(engine_model.get_total_mass()).is_zero()
	assert_float(vessel.mass).is_equal_approx(vessel.minimum_mass, 0.000001)


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


func test_vessel_command_receiver_discovers_engines_from_parent() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var engine_a := EngineModel.new()
	var engine_b := EngineModel.new()
	var tank := FixedMassModel.new()
	vessel.add_child(engine_a)
	vessel.add_child(engine_b)
	vessel.add_child(tank)

	var receiver := VesselCommandReceiver.new()
	vessel.add_child(receiver)

	assert_int(receiver.get_active_engines().size()).is_equal(2)
	assert_object(receiver.get_active_engines()[0]).is_same(engine_a)
	assert_object(receiver.get_active_engines()[1]).is_same(engine_b)


func test_vessel_command_receiver_fans_engine_commands_to_active_engines() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var engine_a := EngineModel.new()
	var engine_b := EngineModel.new()
	vessel.add_child(engine_a)
	vessel.add_child(engine_b)

	var receiver := VesselCommandReceiver.new()
	vessel.add_child(receiver)

	receiver.receive_command(EngineCommand.new(0.8, Vector3(0.5, -0.3, 0.0)))

	assert_float(engine_a.get_throttle()).is_equal_approx(0.8, 0.000001)
	assert_vector(engine_a.get_gimbal()).is_equal(Vector2(0.5, -0.3))
	assert_float(engine_b.get_throttle()).is_equal_approx(0.8, 0.000001)
	assert_vector(engine_b.get_gimbal()).is_equal(Vector2(0.5, -0.3))


func test_vessel_command_receiver_ignores_non_engine_commands() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var engine := EngineModel.new()
	vessel.add_child(engine)

	var receiver := VesselCommandReceiver.new()
	vessel.add_child(receiver)

	receiver.receive_command(EngineCommand.new(1.0, Vector3.ZERO))
	receiver.receive_command(Command.new())

	assert_float(engine.get_throttle()).is_equal_approx(1.0, 0.000001)


func test_vessel_command_receiver_respects_active_engine_subset() -> void:
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	var engine_a := EngineModel.new()
	var engine_b := EngineModel.new()
	vessel.add_child(engine_a)
	vessel.add_child(engine_b)

	var receiver := VesselCommandReceiver.new()
	vessel.add_child(receiver)

	var subset: Array[EngineModel] = [engine_b]
	receiver.set_active_engines(subset)
	receiver.receive_command(EngineCommand.new(0.6, Vector3(1.0, 0.0, 0.0)))

	assert_float(engine_a.get_throttle()).is_zero()
	assert_float(engine_b.get_throttle()).is_equal_approx(0.6, 0.000001)


func test_lamae_scene_has_vessel_level_selectable_and_command_receiver() -> void:
	var scene := load("res://scene/craft/lamae.tscn") as PackedScene
	var vessel = auto_free(scene.instantiate())
	add_child(vessel)

	var selectable := vessel.get_node("Selectable3D") as Selectable3D
	var receiver := vessel.get_node("VesselCommandReceiver") as VesselCommandReceiver
	var info := vessel.get_node("Info") as Selectable3DInfo
	var trajectory: Variant = vessel.get_node("OrbitTrajectory")

	assert_object(selectable).is_not_null()
	assert_object(receiver).is_not_null()
	assert_object(info).is_not_null()
	assert_object(trajectory).is_not_null()
	assert_object(selectable.get_command_receiver()).is_same(receiver)
	assert_object(selectable.get_info()).is_same(info)
	assert_object(trajectory.get("body")).is_same(vessel)
	assert_bool(trajectory.is_set_as_top_level()).is_false()
	assert_int(receiver.get_active_engines().size()).is_equal(1)
	assert_object(receiver.get_active_engines()[0]).is_same(vessel.get_node("LamaeEngine"))


func test_lamae_scene_uses_one_rigid_body_and_component_masses() -> void:
	var scene := load("res://scene/craft/lamae.tscn") as PackedScene
	var vessel = auto_free(scene.instantiate())
	add_child(vessel)

	var rigid_bodies: Array[Node] = []
	var joints: Array[Node] = []
	_collect_rigid_bodies_and_joints(vessel, rigid_bodies, joints)

	assert_int(rigid_bodies.size()).is_equal(1)
	assert_object(rigid_bodies[0]).is_same(vessel)
	assert_int(joints.size()).is_equal(0)

	var engine := vessel.get_node("LamaeEngine") as EngineModel
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
