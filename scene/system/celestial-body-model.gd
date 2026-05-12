## Scene-authored celestial gravity source.
##
## Celestial body scenes attach this script to the node that marks the body's
## current gravity center. When the node enters the tree, it registers with
## `CelestialBodySystem`; affected rigid bodies then query the system for the
## summed acceleration from every registered source.
##
## The model owns only static source parameters and local radial queries. It does
## not move planets, solve orbits, stream terrain, or apply forces by itself.
## Positions are interpreted in the same scene-space meter frame used by the
## current physics step.
class_name CelestialBodyModel

extends Node3D

## Human-readable body identifier for inspector clarity and HUD/debug output.
##
## This does not currently drive gameplay identity, registration, or save/load
## lookup. Use it as authoring metadata only.
@export var planet_name: String = "Unknown"

## Mean body radius in scene-space meters.
##
## Gravity uses this radius for the uniform-density interior approximation when a
## queried point is inside the body. Altitude and up-vector helpers also use it
## as the surface reference.
@export_custom(PROPERTY_HINT_NONE, "suffix: m") var radius: float = 0.0

## Standard gravitational parameter μ = G·M in m³/s².
## Earth ≈ 3.986 × 10¹⁴. Using mu avoids carrying G and M separately and
## keeps source data in the same units as force and rigid-body mass.
##
## This value controls acceleration returned by `acceleration_at(...)`; it does
## not move this node or any other scene node by itself.
@export_custom(PROPERTY_HINT_NONE, "suffix: m³/s²") var mu: float = 0.0


func _enter_tree() -> void:
	CelestialBodySystem.register_source(self)


func _exit_tree() -> void:
	CelestialBodySystem.unregister_source(self)


## Returns the current gravity center in scene-space meters.
##
## Keeping this as a helper keeps all radial queries on one center contract if
## later frame conversion or on-rails body motion needs to be inserted here.
func _get_center() -> Vector3:
	return global_position


## Returns gravitational acceleration toward this source at `p_position`.
##
## Outside the body, acceleration follows μ * r / |r|³. Inside the configured
## radius, the source uses a uniform-density sphere approximation so acceleration
## approaches zero at the center instead of becoming singular.
func acceleration_at(p_position: Vector3) -> Vector3:
	var r: Vector3 = _get_center() - p_position
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


## Returns radial altitude above this body's mean surface.
func get_altitude_at(p_position: Vector3) -> float:
	var r := (p_position - _get_center()).length()
	return r - radius


## Returns the radial "up" direction away from this body's center.
func get_up_at(p_position: Vector3) -> Vector3:
	var offset := p_position - _get_center()
	if offset.length_squared() <= 0.000001:
		return Vector3.ZERO
	return offset.normalized()
