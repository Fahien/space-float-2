## Chapter: A Registry for Many Worlds
##
## Early versions of the simulation could ask a single body for a single pull.
## The active solar-system scene needs a broader instrument: a shared registry
## where planets, moons, and stars report themselves as gravity sources, while
## rigid bodies ask for the summed acceleration that belongs at their current
## point in space. `CelestialBodySystem` is that instrument.
##
## The system has two ledgers. `CelestialBodyModel` nodes enter the source
## ledger and provide radial acceleration fields. `GravityRigidBody3D` nodes
## enter the body ledger so the environment path can later grow from gravity
## into atmosphere, drag, wind, and frame-context updates. The immediate
## integration step still keeps Newtonian superposition: every valid source
## contributes to the acceleration vector applied to a body.
##
## A second question travels beside the force calculation. For local UI and
## environmental work, the simulation needs to know which registered body is
## strongest at a point. The answer is not used to discard the other gravity
## sources; it becomes a practical primary-body cache for local down, celestial
## body readouts, and later planet-owned atmosphere queries.
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


func apply_gravity(p_body: GravityRigidBody3D, p_state: PhysicsDirectBodyState3D) -> void:
	var inverse_mass = p_state.inverse_mass
	if inverse_mass <= 0.0:
		return

	var mass = 1.0 / inverse_mass

	var position = p_state.transform.origin
	var acceleration = gravity_acceleration_at(position)

	var force = mass * acceleration
	p_state.apply_central_force(force)

	p_body.current_primary = strongest_source_at(position)


## Returns summed gravitational acceleration from every valid registered source.
##
## The compensated summation matters most when a small local source and a large
## distant source both affect the same body, such as a moon beside a planet
## under solar gravity.
func gravity_acceleration_at(p_position: Vector3) -> Vector3:
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


## Returns the source with the largest acceleration magnitude at `p_position`.
##
## This is an environment-selection helper, not a gravity switch. Force
## integration still uses `gravity_acceleration_at(...)`.
func strongest_source_at(p_position: Vector3) -> CelestialBodyModel:
	var best: CelestialBodyModel = null
	var best_a2: float = 0.0

	for source in _sources:
		if not is_instance_valid(source):
			continue

		var a: Vector3 = source.acceleration_at(p_position)
		var a2: float = a.length_squared()

		if best == null or a2 > best_a2:
			best = source
			best_a2 = a2

	return best


## Returns the normalized direction of the summed gravity field.
##
## If no registered source contributes acceleration, Godot's global down is used
## as a conservative fallback for callers that need a direction.
func local_down_at(p_position: Vector3) -> Vector3:
	var a: Vector3 = gravity_acceleration_at(p_position)
	if a.length_squared() == 0.0:
		return Vector3.DOWN
	return a.normalized()
