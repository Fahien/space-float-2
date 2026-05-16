## Chapter: Drawing the Current Conic
##
## This node turns a vessel's current two-body orbit estimate into an
## ImmediateMesh line. The mesh is anchored at the vessel so BigSpace floating
## origin rendering keeps it near the camera, while sampled `OrbitalElements`
## points are converted out of the primary-focus frame before drawing. The line
## starts at the vessel and follows the future branch, clipping suborbital paths
## at the primary surface instead of drawing the hidden half of the conic
## through the planet.
## Near-radial launch states use a short powered/coast fallback because the
## conic plane is otherwise undefined.
##
## Rendering strategy:
## The orbit is sampled as a PRIMITIVE_LINE_STRIP on an ImmediateMesh, redrawn
## every frame. Two distinct rendering modes exist:
##
## 1. CONIC MODE (normal orbital flight):
##    Computes OrbitalElements from the state vector, then sweeps true anomaly θ
##    from the vessel's current position forward. An adaptive subdivision scheme
##    (bisection) refines segments that are too long or whose chord error exceeds
##    a threshold, producing smooth curves near apoapsis where uniform θ sampling
##    would create long straight chords.
##    Reference: De Boor, "A Practical Guide to Splines" for adaptive refinement;
##    the orbit equation r(θ) = p/(1+e·cos θ) from Curtis §2.6.
##
## 2. RADIAL FALLBACK (near-vertical launch/landing):
##    When tangential speed is below a threshold, the orbital plane normal h = r×v
##    is numerically unstable. Instead, a simple Euler integration forward-predicts
##    position under gravity + current thrust for a fixed duration. This gives a
##    short "where am I going" arc during launch/landing without requiring a
##    well-defined conic.
##
## Collision clipping:
##    Both modes clip the trajectory at the primary's surface radius, so
##    suborbital arcs terminate at ground impact rather than passing through the
##    planet. For conics this uses the orbit equation solved for the collision
##    true anomaly; for radial mode it checks distance each Euler step.
##
## Coordinate frame:
##    All drawn points are relative to the vessel's current position (the mesh
##    origin). OrbitalElements produces points relative to the primary's focus,
##    so we subtract relative_position before appending vertices.
##
## References:
##   - Bate, Mueller & White, "Fundamentals of Astrodynamics" (1971)
##   - Curtis, "Orbital Mechanics for Engineering Students" (4th ed.), Ch. 2 & 4
##   - Vallado, "Fundamentals of Astrodynamics and Applications" (4th ed.)
##   - https://en.wikipedia.org/wiki/Conic_section (orbit geometry)
##   - https://en.wikipedia.org/wiki/Hyperbolic_trajectory (asymptote angle)
class_name OrbitTrajectory3D

extends MeshInstance3D

## Safety margin from the true asymptote angle for hyperbolic orbits.
## The orbit equation r(θ) = p/(1+e·cos θ) diverges at θ_∞ = ±acos(−1/e);
## we stop just short to avoid infinite-radius points.
## Reference: https://en.wikipedia.org/wiki/Hyperbolic_trajectory
const HYPERBOLA_ASYMPTOTE_MARGIN := 0.01

## Tolerance for comparing true anomaly values.
const ANOMALY_EPSILON := 0.000001

## Adaptive subdivision parameters for conic rendering.
## Uniform true-anomaly samples produce unacceptably long chords near apoapsis
## (where the vessel moves slowly and the curve is gentle but far from focus).
## The renderer uses recursive bisection: if a segment's chord length or its
## midpoint deviation from the true curve exceeds a threshold, it splits.
## This is analogous to adaptive quadrature but applied to polyline fidelity.
const MAX_CONIC_SUBDIVISION_DEPTH := 8
const MAX_CONIC_POINT_COUNT := 4096

## Segment length threshold as a fraction of the primary's radius.
## Keeps line segments short enough to appear smooth at typical zoom levels.
const CONIC_SEGMENT_LENGTH_TO_PRIMARY_RADIUS := 0.04

## Maximum allowed chord error (deviation of the true midpoint from the linear
## interpolant) as a fraction of primary radius. Controls curve smoothness.
const CONIC_CHORD_ERROR_TO_PRIMARY_RADIUS := 0.0025

## Absolute minimum thresholds (used when primary radius is very small or zero).
const MIN_CONIC_SEGMENT_LENGTH := 100000.0
const MIN_CONIC_CHORD_ERROR := 5000.0

## The vessel whose orbit to predict and draw.
@export var body: GravityRigidBody3D = null:
	set(p_body):
		body = p_body
		update_configuration_warnings()

## Number of uniformly-spaced true anomaly samples before adaptive subdivision.
## Higher values produce smoother base curves but cost more even for simple orbits.
@export_range(8, 512, 1) var segment_count: int = 128

## Below this tangential speed [m/s], the orbit normal h = r×v is too noisy to
## define a conic plane, so the renderer switches to radial (Euler) fallback.
@export_custom(PROPERTY_HINT_NONE, "suffix: m/s")
var radial_tangential_speed_threshold: float = 10.0

## How far into the future [s] the radial fallback predicts (Euler integration).
@export_custom(PROPERTY_HINT_NONE, "suffix: s")
var radial_prediction_duration: float = 240.0

## Polylines shorter than this [m] are not drawn, avoiding visual noise from
## near-zero-velocity states or nearly-impacted suborbital hops.
@export_custom(PROPERTY_HINT_NONE, "suffix: m")
var minimum_visible_trajectory_length: float = 10.0

## Line material. Typically uses no_depth_test=true so the orbit line renders
## on top of geometry (visible through the planet body).
@export var material: StandardMaterial3D = StandardMaterial3D.new()


func _ready() -> void:
	mesh = ImmediateMesh.new()
	_redraw()


func _process(_delta: float) -> void:
	_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	if body == null:
		return PackedStringArray(["Assign a GravityRigidBody3D body for orbit prediction."])
	return PackedStringArray()


## Main per-frame entry point. Decides between conic and radial rendering,
## computes the orbital state, and draws the trajectory line strip.
func _redraw() -> void:
	var immediate := mesh as ImmediateMesh
	if immediate == null:
		return

	immediate.clear_surfaces()
	if body == null or not is_instance_valid(body):
		return

	var primary := body.current_primary
	if primary == null or not is_instance_valid(primary) or primary.mu <= 0.0:
		return

	var relative_position := body.global_position - primary.global_position
	var relative_velocity := body.linear_velocity
	var non_gravity_acceleration := _current_non_gravity_acceleration()
	global_transform = Transform3D(Basis.IDENTITY, body.global_position)

	# Mode selection: if tangential speed is too low for a stable conic plane,
	# or if OrbitalElements reports degenerate, use Euler radial fallback.
	if _should_draw_radial_trajectory(relative_position, relative_velocity):
		_draw_radial_trajectory(
			immediate,
			relative_position,
			relative_velocity,
			non_gravity_acceleration,
			primary.mu,
			primary.radius
		)
		return

	var elements := OrbitalElements.new()
	elements.set_from_state_vector(
		relative_position,
		relative_velocity,
		primary.mu
	)
	if elements.is_degenerate():
		_draw_radial_trajectory(
			immediate,
			relative_position,
			relative_velocity,
			non_gravity_acceleration,
			primary.mu,
			primary.radius
		)
		return

	_draw_conic_trajectory(immediate, elements, relative_position, primary.radius)


## Draws the conic (elliptical or hyperbolic) trajectory as an adaptively-refined
## line strip.
##
## Sweep range:
##   - Ellipse: full orbit from current θ forward by 2π (one complete revolution).
##   - Hyperbola: from current θ to the asymptote angle θ_∞ = acos(−1/e), with a
##     small margin to avoid the singularity where r → ∞.
##     Reference: https://en.wikipedia.org/wiki/Hyperbolic_trajectory
##
## After determining the angular range, the trajectory is clipped at planet
## surface impact (if the periapsis dips below the collision radius), then
## sampled with uniform base segments refined by adaptive bisection.
func _draw_conic_trajectory(
	immediate: ImmediateMesh,
	elements: OrbitalElements,
	relative_position: Vector3,
	collision_radius: float
) -> void:
	var anomaly_start := elements.get_true_anomaly_for_position(relative_position)
	var anomaly_end := anomaly_start + TAU
	if not elements.is_closed():
		# Hyperbolic asymptote: θ_∞ = acos(−1/e). Beyond this angle the orbit
		# equation gives negative radius (physically meaningless).
		var asymptote := acos(-1.0 / elements.eccentricity)
		anomaly_start = clampf(
			anomaly_start,
			-asymptote + HYPERBOLA_ASYMPTOTE_MARGIN,
			asymptote - HYPERBOLA_ASYMPTOTE_MARGIN
		)
		anomaly_end = asymptote - HYPERBOLA_ASYMPTOTE_MARGIN

	# Clip at surface collision (suborbital impact point).
	anomaly_end = _get_collision_limited_anomaly_end(
		elements,
		anomaly_start,
		anomaly_end,
		collision_radius
	)

	if anomaly_end <= anomaly_start:
		return

	# Build the polyline: uniform base samples + adaptive refinement.
	var points := PackedVector3Array()
	var segment_start_anomaly := anomaly_start
	var previous_point := elements.get_orbit_point(segment_start_anomaly)
	var max_segment_length := _get_maximum_conic_segment_length(collision_radius)
	var max_chord_error := _get_maximum_conic_chord_error(collision_radius)
	points.append(previous_point - relative_position)
	for index in range(1, segment_count + 1):
		var weight := float(index) / float(segment_count)
		var true_anomaly := lerpf(anomaly_start, anomaly_end, weight)
		var point := elements.get_orbit_point(true_anomaly)
		_append_adaptive_conic_segment(
			points,
			elements,
			segment_start_anomaly,
			true_anomaly,
			previous_point,
			point,
			relative_position,
			max_segment_length,
			max_chord_error,
			MAX_CONIC_SUBDIVISION_DEPTH
		)
		if points.size() >= MAX_CONIC_POINT_COUNT:
			break
		segment_start_anomaly = true_anomaly
		previous_point = point

	_commit_line_strip(immediate, points)


## Recursively refines a single conic segment [θ_start, θ_end] via bisection.
##
## The algorithm evaluates the true orbit position at the midpoint anomaly and
## compares it to the linear interpolant (chord midpoint). If either:
##   - The chord is longer than max_segment_length, or
##   - The midpoint deviation (chord error) exceeds max_chord_error,
## the segment is split in half and each half is refined recursively.
##
## This is a form of adaptive curve tessellation that concentrates vertices
## where the conic has high curvature (near periapsis) or long arcs (near
## apoapsis), similar to de Casteljau subdivision for Bézier curves.
##
## Terminates when:
##   - Both criteria are satisfied (segment is "flat enough"), or
##   - Maximum recursion depth is reached, or
##   - Point budget is exhausted.
func _append_adaptive_conic_segment(
	points: PackedVector3Array,
	elements: OrbitalElements,
	anomaly_start: float,
	anomaly_end: float,
	point_start: Vector3,
	point_end: Vector3,
	relative_position: Vector3,
	max_segment_length: float,
	max_chord_error: float,
	depth_remaining: int
) -> void:
	if points.size() >= MAX_CONIC_POINT_COUNT:
		return

	var middle_anomaly := (anomaly_start + anomaly_end) * 0.5
	var middle_point := elements.get_orbit_point(middle_anomaly)
	var chord_middle := point_start.lerp(point_end, 0.5)
	var chord_error := middle_point.distance_to(chord_middle)
	var segment_length := point_start.distance_to(point_end)

	if (
		depth_remaining > 0
		and (
			segment_length > max_segment_length
			or chord_error > max_chord_error
		)
	):
		_append_adaptive_conic_segment(
			points,
			elements,
			anomaly_start,
			middle_anomaly,
			point_start,
			middle_point,
			relative_position,
			max_segment_length,
			max_chord_error,
			depth_remaining - 1
		)
		_append_adaptive_conic_segment(
			points,
			elements,
			middle_anomaly,
			anomaly_end,
			middle_point,
			point_end,
			relative_position,
			max_segment_length,
			max_chord_error,
			depth_remaining - 1
		)
		return

	points.append(point_end - relative_position)


## Computes the maximum allowed segment length, scaled to the primary's size.
## Larger bodies need proportionally larger thresholds to avoid over-tessellation.
func _get_maximum_conic_segment_length(collision_radius: float) -> float:
	if collision_radius <= 0.0:
		return MIN_CONIC_SEGMENT_LENGTH
	return maxf(
		MIN_CONIC_SEGMENT_LENGTH,
		collision_radius * CONIC_SEGMENT_LENGTH_TO_PRIMARY_RADIUS
	)


## Computes the maximum allowed chord error, scaled to the primary's size.
func _get_maximum_conic_chord_error(collision_radius: float) -> float:
	if collision_radius <= 0.0:
		return MIN_CONIC_CHORD_ERROR
	return maxf(
		MIN_CONIC_CHORD_ERROR,
		collision_radius * CONIC_CHORD_ERROR_TO_PRIMARY_RADIUS
	)


## Finds the first true anomaly after anomaly_start where the orbit intersects
## the primary's surface, and clips the trajectory there.
##
## Derivation: Starting from the orbit equation r(θ) = p/(1 + e·cos θ),
## setting r = R_surface and solving for θ gives:
##   cos θ_collision = (p/R − 1) / e
## This yields two symmetric solutions ±θ_collision. We pick the first one that
## lies in the future arc (after anomaly_start) to clip the drawn trajectory at
## ground impact.
##
## Returns anomaly_end unchanged if no collision occurs (periapsis above surface,
## circular orbit, or no valid intersection in the forward arc).
func _get_collision_limited_anomaly_end(
	elements: OrbitalElements,
	anomaly_start: float,
	anomaly_end: float,
	collision_radius: float
) -> float:
	if (
		collision_radius <= 0.0
		or elements.eccentricity <= OrbitalElements.CIRCULAR_EPSILON
		or elements.periapsis >= collision_radius
	):
		return anomaly_end

	var collision_cosine := (
		elements.semi_latus_rectum / collision_radius - 1.0
	) / elements.eccentricity
	if collision_cosine < -1.0 or collision_cosine > 1.0:
		return anomaly_end

	var collision_angle := acos(clampf(collision_cosine, -1.0, 1.0))
	var best_anomaly := INF
	for candidate in [collision_angle, -collision_angle]:
		var future_candidate := _normalize_anomaly_after(candidate, anomaly_start)
		if (
			future_candidate <= anomaly_start + ANOMALY_EPSILON
			or future_candidate > anomaly_end + ANOMALY_EPSILON
		):
			continue
		if future_candidate < best_anomaly:
			best_anomaly = future_candidate

	if is_inf(best_anomaly):
		return anomaly_end
	return minf(anomaly_end, best_anomaly)


## Normalizes a true anomaly so that it falls in the range (anomaly_start, anomaly_start + 2π].
## Used to pick the "next" occurrence of a collision angle after the vessel's current position.
func _normalize_anomaly_after(anomaly: float, anomaly_start: float) -> float:
	var future_anomaly := anomaly
	while future_anomaly <= anomaly_start + ANOMALY_EPSILON:
		future_anomaly += TAU
	while future_anomaly - TAU > anomaly_start + ANOMALY_EPSILON:
		future_anomaly -= TAU
	return future_anomaly


## Determines whether the vessel's motion is too radial for a stable conic.
## Decomposes velocity into radial and tangential components:
##   v_radial    = (v · r̂) · r̂
##   v_tangential = v − v_radial
## If |v_tangential| < threshold, the angular momentum h = r × v is near zero
## and the orbital plane is numerically undefined.
func _should_draw_radial_trajectory(
	relative_position: Vector3,
	relative_velocity: Vector3
) -> bool:
	if relative_position.length_squared() <= OrbitalElements.EPSILON:
		return false

	var radial_direction := relative_position.normalized()
	var radial_velocity := radial_direction * relative_velocity.dot(radial_direction)
	var tangential_speed := (relative_velocity - radial_velocity).length()
	return tangential_speed <= radial_tangential_speed_threshold


## Radial fallback: forward-predicts position using symplectic Euler integration
## under gravity + current non-gravitational acceleration (thrust).
##
## This is used for near-vertical flight (launch, landing, radial escape) where
## the two-body conic is undefined due to near-zero angular momentum. The
## integration uses:
##   a(t) = −μ·r̂/r² + a_thrust
##   v(t+Δt) = v(t) + a(t)·Δt
##   r(t+Δt) = r(t) + v(t+Δt)·Δt
##
## The "velocity-first" (symplectic Euler) update provides better energy
## conservation than naive Euler for gravitational problems.
## Reference: https://en.wikipedia.org/wiki/Semi-implicit_Euler_method
##
## Terminates early if the trajectory hits the primary surface.
func _draw_radial_trajectory(
	immediate: ImmediateMesh,
	relative_position: Vector3,
	relative_velocity: Vector3,
	non_gravity_acceleration: Vector3,
	mu: float,
	collision_radius: float
) -> void:
	if relative_position.length_squared() <= OrbitalElements.EPSILON * OrbitalElements.EPSILON:
		return

	var step_duration := radial_prediction_duration / float(segment_count)
	if step_duration <= 0.0:
		return

	var l_position := relative_position
	var velocity := relative_velocity
	var points := PackedVector3Array()
	points.append(l_position - relative_position)

	for _index in range(segment_count):
		var acceleration := _gravity_acceleration_at(l_position, mu) + non_gravity_acceleration
		velocity += acceleration * step_duration
		l_position += velocity * step_duration

		if collision_radius > 0.0 and l_position.length() <= collision_radius:
			l_position = l_position.normalized() * collision_radius
			points.append(l_position - relative_position)
			break

		points.append(l_position - relative_position)

	_commit_line_strip(immediate, points)


## Submits the computed polyline to the ImmediateMesh as a LINE_STRIP surface.
## Skips if too few points or total arc length is below the visibility threshold.
func _commit_line_strip(immediate: ImmediateMesh, points: PackedVector3Array) -> void:
	if points.size() < 2:
		return
	if _get_polyline_length(points) < minimum_visible_trajectory_length:
		return

	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for point in points:
		immediate.surface_add_vertex(point)
	immediate.surface_end()


func _get_polyline_length(points: PackedVector3Array) -> float:
	var length := 0.0
	for index in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	return length


## Computes gravitational acceleration at a position relative to the primary.
## Uses Newton's law of gravitation: a = −μ·r̂/r² = −μ·r / r³
## Reference: https://en.wikipedia.org/wiki/Newton%27s_law_of_universal_gravitation
func _gravity_acceleration_at(relative_position: Vector3, mu: float) -> Vector3:
	var distance_squared := relative_position.length_squared()
	if distance_squared <= OrbitalElements.EPSILON * OrbitalElements.EPSILON:
		return Vector3.ZERO

	var distance := sqrt(distance_squared)
	return -relative_position * (mu / (distance_squared * distance))


## Sums thrust from all active engines on the vessel and returns the resulting
## non-gravitational acceleration [m/s²]. Used by the radial fallback to predict
## powered trajectories (e.g., during launch with engines firing).
func _current_non_gravity_acceleration() -> Vector3:
	if body == null or not is_instance_valid(body):
		return Vector3.ZERO

	var body_mass := maxf(body.mass, OrbitalElements.EPSILON)
	var force := Vector3.ZERO
	for child in body.get_children():
		var engine := child as EngineModel
		if engine == null or not is_instance_valid(engine):
			continue
		if engine.get_propellant_mass() <= 0.0:
			continue

		var thrust_magnitude := engine.get_thrust_magnitude()
		if thrust_magnitude <= 0.0:
			continue

		var component_basis := (
			body.global_transform.basis * engine.transform.basis
		).orthonormalized()
		var thrust_direction := (
			component_basis * engine.get_actual_thrust_direction_local()
		).normalized()
		force += thrust_direction * thrust_magnitude

	return force / body_mass
