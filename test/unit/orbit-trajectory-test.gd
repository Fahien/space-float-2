extends GdUnitTestSuite

const EARTH_MU := 398600441800000.0


func test_orbit_trajectory_draws_radial_launch_prediction() -> void:
	var primary := auto_free(CelestialBody3D.new()) as CelestialBody3D
	add_child(primary)
	primary.radius = 6371000.0
	primary.mu = EARTH_MU

	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	add_child(vessel)
	vessel.global_position = Vector3(0.0, primary.radius + 100.0, 0.0)
	vessel.linear_velocity = Vector3.UP * 200.0
	vessel.current_primary = primary

	var trajectory := auto_free(OrbitTrajectory3D.new()) as OrbitTrajectory3D
	add_child(trajectory)
	trajectory.body = vessel
	trajectory.segment_count = 32
	trajectory.radial_prediction_duration = 120.0

	trajectory._redraw()

	assert_int(trajectory.mesh.get_surface_count()).is_equal(1)
	assert_float(trajectory.mesh.get_aabb().size.y).is_greater(100.0)
	assert_vector(trajectory.global_position).is_equal(vessel.global_position)


func test_radial_prediction_uses_current_engine_acceleration() -> void:
	var primary := auto_free(CelestialBody3D.new()) as CelestialBody3D
	add_child(primary)
	primary.radius = 6371000.0
	primary.mu = EARTH_MU

	var tank := PropellantModel.new()
	tank.propellant_mass = 100.0

	var engine := EngineModel.new()
	engine.propellant_model = tank
	engine.engine_mass = 100.0
	engine.propulsion_model.max_thrust_newtons = 16000.0

	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	vessel.add_child(tank)
	vessel.add_child(engine)
	add_child(vessel)
	vessel.global_position = Vector3(0.0, primary.radius + 2.0, 0.0)
	vessel.current_primary = primary
	engine.set_throttle(1.0)
	vessel.sync_mass_properties()

	var trajectory := auto_free(OrbitTrajectory3D.new()) as OrbitTrajectory3D
	add_child(trajectory)
	trajectory.body = vessel
	trajectory.segment_count = 16
	trajectory.radial_prediction_duration = 5.0

	trajectory._redraw()

	assert_int(trajectory.mesh.get_surface_count()).is_equal(1)
	assert_float(trajectory.mesh.get_aabb().size.y).is_greater(100.0)


func test_conic_prediction_starts_at_current_vessel_position() -> void:
	var primary := auto_free(CelestialBody3D.new()) as CelestialBody3D
	add_child(primary)
	primary.radius = 6371000.0
	primary.mu = EARTH_MU

	var periapsis := 7000000.0
	var apoapsis := 13000000.0
	var semi_major_axis := (periapsis + apoapsis) * 0.5
	var speed_at_periapsis := sqrt(EARTH_MU * (2.0 / periapsis - 1.0 / semi_major_axis))

	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	add_child(vessel)
	vessel.global_position = Vector3(periapsis, 0.0, 0.0)
	vessel.linear_velocity = Vector3(0.0, speed_at_periapsis, 0.0)
	vessel.current_primary = primary

	var trajectory := auto_free(OrbitTrajectory3D.new()) as OrbitTrajectory3D
	add_child(trajectory)
	trajectory.body = vessel
	trajectory.segment_count = 64

	trajectory._redraw()

	var vertices := _get_trajectory_vertices(trajectory)
	assert_int(vertices.size()).is_greater_equal(trajectory.segment_count + 1)
	assert_vector(vertices[0]).is_equal_approx(
		Vector3.ZERO,
		Vector3(0.001, 0.001, 0.001)
	)
	assert_vector(vertices[vertices.size() - 1]).is_equal_approx(
		Vector3.ZERO,
		Vector3(0.001, 0.001, 0.001)
	)
	assert_float(trajectory.mesh.get_aabb().size.x).is_greater(19000000.0)
	assert_float(trajectory.mesh.get_aabb().size.y).is_greater(18000000.0)


func test_high_altitude_conic_prediction_subdivides_long_segments() -> void:
	var primary := auto_free(CelestialBody3D.new()) as CelestialBody3D
	add_child(primary)
	primary.radius = 6371000.0
	primary.mu = EARTH_MU

	var periapsis := 7000000.0
	var apoapsis := 80000000.0
	var semi_major_axis := (periapsis + apoapsis) * 0.5
	var speed_at_apoapsis := sqrt(EARTH_MU * (2.0 / apoapsis - 1.0 / semi_major_axis))

	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	add_child(vessel)
	vessel.global_position = Vector3(-apoapsis, 0.0, 0.0)
	vessel.linear_velocity = Vector3(0.0, -speed_at_apoapsis, 0.0)
	vessel.current_primary = primary

	var trajectory := auto_free(OrbitTrajectory3D.new()) as OrbitTrajectory3D
	add_child(trajectory)
	trajectory.body = vessel
	trajectory.segment_count = 16

	trajectory._redraw()

	var vertices := _get_trajectory_vertices(trajectory)
	var maximum_segment_length := trajectory._get_maximum_conic_segment_length(primary.radius)
	assert_int(vertices.size()).is_greater(trajectory.segment_count + 1)
	assert_float(_get_maximum_vertex_spacing(vertices)).is_less_equal(
		maximum_segment_length * 1.1
	)
	assert_vector(vertices[0]).is_equal_approx(
		Vector3.ZERO,
		Vector3(0.001, 0.001, 0.001)
	)


func test_conic_prediction_clips_suborbital_paths_at_primary_radius() -> void:
	var primary := auto_free(CelestialBody3D.new()) as CelestialBody3D
	add_child(primary)
	primary.radius = 6371000.0
	primary.mu = EARTH_MU

	var relative_position := Vector3(0.0, primary.radius + 100000.0, 0.0)
	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	add_child(vessel)
	vessel.global_position = relative_position
	vessel.linear_velocity = Vector3(1000.0, 0.0, 0.0)
	vessel.current_primary = primary

	var trajectory := auto_free(OrbitTrajectory3D.new()) as OrbitTrajectory3D
	add_child(trajectory)
	trajectory.body = vessel
	trajectory.segment_count = 128

	trajectory._redraw()

	var vertices := _get_trajectory_vertices(trajectory)
	assert_int(vertices.size()).is_greater_equal(trajectory.segment_count + 1)
	assert_vector(vertices[0]).is_equal_approx(
		Vector3.ZERO,
		Vector3(0.001, 0.001, 0.001)
	)

	for vertex in vertices:
		var point: Vector3 = vertex + relative_position
		assert_bool(point.length() >= primary.radius - 1.0).is_true()

	var impact_point: Vector3 = vertices[vertices.size() - 1] + relative_position
	assert_float(impact_point.length()).is_equal_approx(primary.radius, 1.0)


func test_radial_prediction_hides_immediate_surface_impact() -> void:
	var primary := auto_free(CelestialBody3D.new()) as CelestialBody3D
	add_child(primary)
	primary.radius = 6371000.0
	primary.mu = EARTH_MU

	var vessel := auto_free(VesselRigidBody3D.new()) as VesselRigidBody3D
	add_child(vessel)
	vessel.global_position = Vector3(0.0, primary.radius + 2.0, 0.0)
	vessel.linear_velocity = Vector3.ZERO
	vessel.current_primary = primary

	var trajectory := auto_free(OrbitTrajectory3D.new()) as OrbitTrajectory3D
	add_child(trajectory)
	trajectory.body = vessel
	trajectory.segment_count = 32

	trajectory._redraw()

	assert_int(trajectory.mesh.get_surface_count()).is_equal(0)


func _get_trajectory_vertices(trajectory: OrbitTrajectory3D) -> PackedVector3Array:
	var arrays := trajectory.mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]


func _get_maximum_vertex_spacing(vertices: PackedVector3Array) -> float:
	var maximum_spacing := 0.0
	for index in range(1, vertices.size()):
		maximum_spacing = maxf(
			maximum_spacing,
			vertices[index - 1].distance_to(vertices[index])
		)
	return maximum_spacing
