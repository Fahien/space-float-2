extends Node

var _sources: Array[CelestialBodyModel] = []
var _bodies: Array[GravityRigidBody3D] = []


func register_source(p_body: CelestialBodyModel) -> void:
	if p_body != null and not _sources.has(p_body):
		_sources.push_back(p_body)


func unregister_source(p_body: CelestialBodyModel) -> void:
	if p_body != null and _sources.has(p_body):
		_sources.erase(p_body)


func register_body(p_body: GravityRigidBody3D) -> void:
	if p_body != null and not _bodies.has(p_body):
		_bodies.push_back(p_body)


func unregister_body(p_body: GravityRigidBody3D) -> void:
	if p_body != null and _bodies.has(p_body):
		_bodies.erase(p_body)


func apply_gravity(p_state: PhysicsDirectBodyState3D) -> void:
	var inverse_mass = p_state.inverse_mass
	if inverse_mass <= 0.0:
		return

	var mass = 1.0 / inverse_mass
	
	var position = p_state.transform.origin
	var acceleration = gravity_acceleration_at(position)

	var force = mass * acceleration
	p_state.apply_central_force(force)


func gravity_acceleration_at(p_position: Vector3) -> Vector3:
	# Kahan-style compensated summation helps when combining very large and small
	# accelerations, e.g. Sun + planet + moon.
	var sum: Vector3 = Vector3.ZERO
	var compensation: Vector3 = Vector3.ZERO

	for source in _sources:
		if not is_instance_valid(source):
			continue

		var contribution: Vector3 = source.acceleration_at(p_position)

		var y: Vector3 = contribution - compensation
		var t: Vector3 = sum + y
		compensation = (t - sum) - y
		sum = t

	return sum
