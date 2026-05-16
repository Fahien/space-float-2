## Chapter: A Conic From One Moment
##
## The gravity simulation already knows a vessel's instantaneous position,
## velocity, and strongest celestial primary. `OrbitalElements` turns that
## state vector into a two-body conic that UI and debug renderers can sample
## without owning their own orbital math.
##
## Theory overview:
## In the two-body problem, the trajectory of an orbiting body is always a conic
## section (ellipse, parabola, or hyperbola) with the central body at one focus.
## Given a position vector r and velocity vector v relative to the primary, all
## orbital parameters can be derived without numerical integration.
##
## This class implements the "state vector to orbital elements" transformation
## described in:
##   - Bate, Mueller & White, "Fundamentals of Astrodynamics" (2nd ed.)
##     https://store.doverpublications.com/products/9780486497044
##   - Curtis, "Orbital Mechanics for Engineering Students" (4th ed.)
##     https://www.sciencedirect.com/book/monograph/9780128240250/orbital-mechanics-for-engineering-students
##   - Vallado, "Fundamentals of Astrodynamics and Applications" (5th ed.)
##     https://microcosmpress.com/vallado/
##
## The approach avoids computing classical orientation angles (Ω, i, ω) because
## visualization only needs the orbital plane basis vectors and the conic shape.
## See plan/trajectory-prediction.md for the design rationale.
class_name OrbitalElements

extends RefCounted

## Guard against division-by-zero in general geometric computations.
const EPSILON := 0.000001
## Threshold below which eccentricity is treated as exactly zero (circular orbit).
## A separate, tighter epsilon avoids numerical noise in nearly-circular orbits
## from producing an unstable periapsis direction.
const CIRCULAR_EPSILON := 0.00000001

## Specific angular momentum vector: h = r × v [m²/s].
## Defines the orbital plane normal. Its magnitude squared gives μ·p.
## Reference: Curtis §2.4, eq. 2.21
var h_vec: Vector3 = Vector3.ZERO

## Eccentricity vector (Laplace-Runge-Lenz vector scaled by 1/μ).
## Points from the focus toward periapsis with magnitude equal to eccentricity.
## Derived via: e_vec = ((v² − μ/r)·r − (r·v)·v) / μ
## Reference: Bate et al. §1.5, eq. 1.5-10; also known as the "LRL vector"
## https://en.wikipedia.org/wiki/Laplace%E2%80%93Runge%E2%80%93Lenz_vector
var e_vec: Vector3 = Vector3.ZERO

## Orbital eccentricity (dimensionless). Classifies the conic:
##   e = 0       → circle
##   0 < e < 1   → ellipse
##   e = 1       → parabola
##   e > 1       → hyperbola
## Reference: https://en.wikipedia.org/wiki/Orbital_eccentricity
var eccentricity: float = 0.0

## Semi-latus rectum p = |h|²/μ [m]. The conic parameter that appears in the
## orbit equation r(θ) = p / (1 + e·cos θ). Geometrically, it is the distance
## from the focus to the curve measured perpendicular to the major axis.
## Reference: Curtis §2.6, eq. 2.51
var semi_latus_rectum: float = 0.0

## Semi-major axis a = p / (1 − e²) [m]. Half the longest diameter of an
## ellipse; negative for hyperbolic orbits (by convention). Related to specific
## orbital energy via the vis-viva identity: ε = −μ/(2a).
## Reference: https://en.wikipedia.org/wiki/Semi-major_and_semi-minor_axes
var semi_major_axis: float = 0.0

## Periapsis distance (closest approach to focus) [m]: r_p = p / (1 + e).
var periapsis: float = 0.0

## Apoapsis distance (farthest point from focus) [m]: r_a = p / (1 − e).
## INF for open (hyperbolic/parabolic) trajectories.
var apoapsis: float = INF

## Orbital period T = 2π√(a³/μ) [s] (Kepler's third law).
## INF for open trajectories.
## Reference: https://en.wikipedia.org/wiki/Kepler%27s_laws_of_planetary_motion#Third_law
var orbital_period: float = INF

## Perifocal frame unit vector toward periapsis (P̂).
## For near-circular orbits (e < CIRCULAR_EPSILON), falls back to r̂ since
## periapsis direction is undefined.
var p_hat: Vector3 = Vector3.RIGHT

## Perifocal frame unit vector perpendicular to P̂ in the orbital plane (Q̂).
## Computed as Q̂ = Ŵ × P̂. Together with P̂, spans the orbital plane.
var q_hat: Vector3 = Vector3.UP

## Orbit normal unit vector (Ŵ = ĥ). Points along angular momentum.
## Defines the "up" direction of the orbital plane.
var w_hat: Vector3 = Vector3.FORWARD

## True when the state vector is too degenerate to define an orbit (e.g.,
## zero position, zero μ, or purely radial motion with no angular momentum).
var degenerate: bool = true


## Factory: creates OrbitalElements from a position/velocity state vector.
## This is the primary entry point for converting simulation state into orbital
## geometry that renderers and HUD can consume.
static func from_state_vector(r: Vector3, v: Vector3, mu: float) -> OrbitalElements:
	var elements := OrbitalElements.new()
	elements.set_from_state_vector(r, v, mu)
	return elements


## Computes all orbital elements from the instantaneous state vector.
##
## Parameters:
##   r  — position vector from the primary's center of mass [m]
##   v  — velocity vector in the inertial frame [m/s]
##   mu — standard gravitational parameter μ = G·M of the primary [m³/s²]
##
## Algorithm (Bate et al. §1.5–1.6; Curtis §4.4):
##   1. h = r × v                         (angular momentum)
##   2. e_vec = ((v²−μ/r)r − (r·v)v) / μ  (eccentricity vector)
##   3. p = |h|²/μ                         (semi-latus rectum)
##   4. a = p/(1−e²)                       (semi-major axis)
##   5. Build perifocal basis {P̂, Q̂, Ŵ}  (orbital plane frame)
##   6. Derive periapsis, apoapsis, period from geometry
##
## Degenerate cases:
##   - μ ≤ 0 or |r| ≈ 0: no meaningful orbit exists.
##   - |h| ≈ 0: radial trajectory (no orbital plane), marked degenerate.
##   - e ≈ 0: circular orbit, periapsis direction undefined → use r̂ as P̂.
##   - |1−e²| ≈ 0: parabolic limit, semi-major axis → ∞.
func set_from_state_vector(r: Vector3, v: Vector3, mu: float) -> void:
	_reset()
	var r_magnitude := r.length()
	if mu <= EPSILON or r_magnitude <= EPSILON:
		return

	# Step 1: Specific angular momentum h = r × v.
	# |h| = 0 implies purely radial motion — orbit plane is undefined.
	h_vec = r.cross(v)
	var h_magnitude_squared := h_vec.length_squared()
	if h_magnitude_squared <= EPSILON:
		return

	# Orbit normal (Ŵ): perpendicular to the orbital plane.
	w_hat = h_vec.normalized()

	# Step 2: Eccentricity vector via the vis-viva relation rearranged.
	# e_vec = ((v² − μ/r)·r − (r·v)·v) / μ
	# This is equivalent to the normalized Laplace-Runge-Lenz vector.
	# Reference: https://en.wikipedia.org/wiki/Eccentricity_vector
	var v_magnitude_squared := v.length_squared()
	e_vec = (
		r * (v_magnitude_squared - mu / r_magnitude)
		- v * r.dot(v)
	) / mu
	eccentricity = e_vec.length()

	# Step 3: Semi-latus rectum from angular momentum.
	# p = h²/μ — the "shape-independent" conic parameter.
	semi_latus_rectum = h_magnitude_squared / mu

	# Step 4: Semi-major axis from the conic relationship a = p/(1 − e²).
	# Near e = 1 (parabolic), denominator vanishes → a = ∞.
	var semi_major_denominator := 1.0 - eccentricity * eccentricity
	if absf(semi_major_denominator) > EPSILON:
		semi_major_axis = semi_latus_rectum / semi_major_denominator
	else:
		semi_major_axis = INF

	# Step 5: Perifocal frame {P̂, Q̂, Ŵ}.
	# P̂ points toward periapsis. For circular orbits (e ≈ 0) the periapsis is
	# undefined, so we pick the current radial direction as a stable fallback.
	if eccentricity < CIRCULAR_EPSILON:
		p_hat = r.normalized()
	else:
		p_hat = e_vec.normalized()
	q_hat = w_hat.cross(p_hat).normalized()

	# Step 6: Apsides and period from the orbit equation r(θ) = p/(1 + e·cos θ).
	# Periapsis (θ = 0):  r_p = p/(1+e)
	# Apoapsis  (θ = π):  r_a = p/(1−e)  [only for closed orbits]
	# Period (Kepler III): T = 2π√(a³/μ)
	periapsis = semi_latus_rectum / (1.0 + eccentricity)
	if is_closed():
		apoapsis = semi_latus_rectum / (1.0 - eccentricity)
		if semi_major_axis > 0.0:
			orbital_period = TAU * sqrt(
				semi_major_axis * semi_major_axis * semi_major_axis / mu
			)
	else:
		apoapsis = INF
		orbital_period = INF

	degenerate = false


## Returns the position on the conic at a given true anomaly θ, relative to the
## focus (i.e., the primary's center of mass).
##
## Uses the polar orbit equation: r(θ) = p / (1 + e·cos θ)
## Then projects into 3D via the perifocal frame:
##   pos = r(θ) · (cos θ · P̂ + sin θ · Q̂)
##
## Reference: Curtis §2.6, eq. 2.51; Bate et al. §1.6, eq. 1.6-1
## https://en.wikipedia.org/wiki/Conic_section#Polar_coordinates
func get_orbit_point(true_anomaly: float) -> Vector3:
	if degenerate:
		return Vector3.ZERO

	var denominator := 1.0 + eccentricity * cos(true_anomaly)
	if absf(denominator) <= EPSILON:
		return Vector3.ZERO

	var radius := semi_latus_rectum / denominator
	return radius * (cos(true_anomaly) * p_hat + sin(true_anomaly) * q_hat)


## Recovers the true anomaly θ for a given position vector r by projecting r
## onto the perifocal frame axes P̂ and Q̂, then computing atan2(r·Q̂, r·P̂).
## This gives θ ∈ (−π, π] with θ = 0 at periapsis.
##
## Reference: Curtis §4.4 (inverse of the orbit equation)
func get_true_anomaly_for_position(r: Vector3) -> float:
	if degenerate or r.length_squared() <= EPSILON:
		return 0.0

	return atan2(r.dot(q_hat), r.dot(p_hat))


## Returns true for bound (closed) orbits: ellipses (e < 1) and circles (e = 0).
## Parabolic (e = 1) and hyperbolic (e > 1) trajectories are open (escape).
func is_closed() -> bool:
	return eccentricity < 1.0


## Returns true when the state vector was too degenerate to define a conic
## (radial trajectory, zero position, or zero gravitational parameter).
func is_degenerate() -> bool:
	return degenerate


func _reset() -> void:
	h_vec = Vector3.ZERO
	e_vec = Vector3.ZERO
	eccentricity = 0.0
	semi_latus_rectum = 0.0
	semi_major_axis = 0.0
	periapsis = 0.0
	apoapsis = INF
	orbital_period = INF
	p_hat = Vector3.RIGHT
	q_hat = Vector3.UP
	w_hat = Vector3.FORWARD
	degenerate = true
