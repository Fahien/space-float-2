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
class_name OrbitTrajectory3D

extends MeshInstance3D

const HYPERBOLA_ASYMPTOTE_MARGIN := 0.01
const ANOMALY_EPSILON := 0.000001
# Uniform true-anomaly samples create very long chords near high apoapsis.
# These limits add local detail only where the rendered conic needs it.
const MAX_CONIC_SUBDIVISION_DEPTH := 8
const MAX_CONIC_POINT_COUNT := 4096
const CONIC_SEGMENT_LENGTH_TO_PRIMARY_RADIUS := 0.04
const CONIC_CHORD_ERROR_TO_PRIMARY_RADIUS := 0.0025
const MIN_CONIC_SEGMENT_LENGTH := 100000.0
const MIN_CONIC_CHORD_ERROR := 5000.0

@export var body: GravityRigidBody3D = null:
	set(p_body):
		body = p_body
		update_configuration_warnings()

@export_range(8, 512, 1) var segment_count: int = 128
@export_custom(PROPERTY_HINT_NONE, "suffix: m/s")
var radial_tangential_speed_threshold: float = 10.0
@export_custom(PROPERTY_HINT_NONE, "suffix: s")
var radial_prediction_duration: float = 240.0
@export_custom(PROPERTY_HINT_NONE, "suffix: m")
var minimum_visible_trajectory_length: float = 10.0

@export var material: StandardMaterial3D = StandardMaterial3D.new()


func _ready() -> void:
	# Each vessel instance redraws independently; do not share the scene subresource mesh.
	mesh = ImmediateMesh.new()
	_redraw()


func _process(_delta: float) -> void:
	_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	if body == null:
		return PackedStringArray(["Assign a GravityRigidBody3D body for orbit prediction."])
	return PackedStringArray()


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


func _draw_conic_trajectory(
	immediate: ImmediateMesh,
	elements: OrbitalElements,
	relative_position: Vector3,
	collision_radius: float
) -> void:
	var anomaly_start := elements.get_true_anomaly_for_position(relative_position)
	var anomaly_end := anomaly_start + TAU
	if not elements.is_closed():
		var asymptote := acos(-1.0 / elements.eccentricity)
		anomaly_start = clampf(
			anomaly_start,
			-asymptote + HYPERBOLA_ASYMPTOTE_MARGIN,
			asymptote - HYPERBOLA_ASYMPTOTE_MARGIN
		)
		anomaly_end = asymptote - HYPERBOLA_ASYMPTOTE_MARGIN

	anomaly_end = _get_collision_limited_anomaly_end(
		elements,
		anomaly_start,
		anomaly_end,
		collision_radius
	)

	if anomaly_end <= anomaly_start:
		return

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


func _get_maximum_conic_segment_length(collision_radius: float) -> float:
	if collision_radius <= 0.0:
		return MIN_CONIC_SEGMENT_LENGTH
	return maxf(
		MIN_CONIC_SEGMENT_LENGTH,
		collision_radius * CONIC_SEGMENT_LENGTH_TO_PRIMARY_RADIUS
	)


func _get_maximum_conic_chord_error(collision_radius: float) -> float:
	if collision_radius <= 0.0:
		return MIN_CONIC_CHORD_ERROR
	return maxf(
		MIN_CONIC_CHORD_ERROR,
		collision_radius * CONIC_CHORD_ERROR_TO_PRIMARY_RADIUS
	)


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


func _normalize_anomaly_after(anomaly: float, anomaly_start: float) -> float:
	var future_anomaly := anomaly
	while future_anomaly <= anomaly_start + ANOMALY_EPSILON:
		future_anomaly += TAU
	while future_anomaly - TAU > anomaly_start + ANOMALY_EPSILON:
		future_anomaly -= TAU
	return future_anomaly


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


func _gravity_acceleration_at(relative_position: Vector3, mu: float) -> Vector3:
	var distance_squared := relative_position.length_squared()
	if distance_squared <= OrbitalElements.EPSILON * OrbitalElements.EPSILON:
		return Vector3.ZERO

	var distance := sqrt(distance_squared)
	return -relative_position * (mu / (distance_squared * distance))


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
