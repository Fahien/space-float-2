## Simulation-layer environment model used by the standalone launch harness.
##
## `PlanetInfo` exists for multiplayer replication. `CelestialBodyModel` exists for
## the harness and answers physical questions such as gravity and altitude
## without exposing scene details to the vessel controller.
##
## The harness currently runs local Godot physics inside one scene-space
## bubble while the analytic planet model lives in an Earth-centered inertial
## space. Frame placement is handled separately by `SceneFrame`; this class
## only answers inertial planet queries.
class_name CelestialBodyModel

extends Node3D

## Human-readable planet identifier for inspector clarity and HUD/debug output.
##
## This does not currently drive gameplay identity or multiplayer lookup; it is
## authoring metadata for the local simulation harness.
@export var planet_name: String = "Unknown"

## Planet center in inertial coordinates.
##
## Frame:
## - simulation space
## - meters
##
## The harness currently keeps Earth centered at the simulation origin, but the
## property stays explicit so the analytic planet contract does not silently
## depend on that one-body assumption.
@export var center: Vector3 = Vector3.ZERO

## Mean planet radius in simulation-space meters.
##
## This is used by gravity, altitude, surface-normal queries, and the render
## layer's literal-scale globe placement. Changing it affects both simulation
## and presentation.
@export var radius: float = 0.0

## Standard gravitational parameter μ = G·M in m³/s².
## Earth ≈ 3.986 × 10¹⁴. Using mu avoids carrying G and M separately and
## is the standard parameterization for orbital mechanics.
##
## This is simulation-only state. It affects gravity queries directly and does
## not by itself move any scene nodes.
@export var mu: float = 0.0


func _enter_tree() -> void:
	CelestialBodySystem.register_source(self)


func _exit_tree() -> void:
	CelestialBodySystem.unregister_source(self)


func acceleration_at(p_position: Vector3) -> Vector3:
	var r: Vector3 = global_position - p_position
	var r2: float = r.length_squared()

	if r2 <= 0.0:
		return Vector3.ZERO

	if radius > 0.0 and r2 < radius * radius:
		# Inside a uniform sphere:
		# a = μ * r / R^3
		return r * (mu / (radius * radius * radius))

	var softening_length = 0.0
	var e2: float = softening_length * softening_length
	var softened_r2: float = r2 + e2
	var softened_r: float = sqrt(softened_r2)

	# μ * r / |r|^3
	return r * (mu / (softened_r2 * softened_r))


## Returns gravitational acceleration at a given position in inertial space.
## The direction is radial toward the planet center, not a fixed global down.
func get_gravity_at(p_position_inertial: Vector3) -> Vector3:
	var offset := p_position_inertial - center
	var r := offset.length()
	if r <= 0.000001:
		return Vector3.ZERO
	var g_magnitude := mu / (r * r)
	return -offset / r * g_magnitude


## Returns the radial altitude above the planet surface at a given position in inertial space.
func get_altitude_at(p_position_inertial: Vector3) -> float:
	var r := (p_position_inertial - center).length()
	return r - radius


## Returns the "up" direction at a given position in inertial space.
## In the radial model this is the surface normal from the planet center.
func get_up_at(p_position_inertial: Vector3) -> Vector3:
	var offset := p_position_inertial - center
	if offset.length_squared() <= 0.000001:
		return Vector3.ZERO
	return offset.normalized()
