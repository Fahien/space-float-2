## Chapter: A Conic From One Moment
##
## The gravity simulation already knows a vessel's instantaneous position,
## velocity, and strongest celestial primary. `OrbitalElements` turns that
## state vector into a two-body conic that UI and debug renderers can sample
## without owning their own orbital math.
class_name OrbitalElements

extends RefCounted

const EPSILON := 0.000001
const CIRCULAR_EPSILON := 0.00000001

var h_vec: Vector3 = Vector3.ZERO
var e_vec: Vector3 = Vector3.ZERO
var eccentricity: float = 0.0
var semi_latus_rectum: float = 0.0
var semi_major_axis: float = 0.0
var periapsis: float = 0.0
var apoapsis: float = INF
var orbital_period: float = INF
var p_hat: Vector3 = Vector3.RIGHT
var q_hat: Vector3 = Vector3.UP
var w_hat: Vector3 = Vector3.FORWARD
var degenerate: bool = true


static func from_state_vector(r: Vector3, v: Vector3, mu: float) -> OrbitalElements:
	var elements := OrbitalElements.new()
	elements.set_from_state_vector(r, v, mu)
	return elements


func set_from_state_vector(r: Vector3, v: Vector3, mu: float) -> void:
	_reset()
	var r_magnitude := r.length()
	if mu <= EPSILON or r_magnitude <= EPSILON:
		return

	h_vec = r.cross(v)
	var h_magnitude_squared := h_vec.length_squared()
	if h_magnitude_squared <= EPSILON:
		return

	w_hat = h_vec.normalized()
	var v_magnitude_squared := v.length_squared()
	e_vec = (
		r * (v_magnitude_squared - mu / r_magnitude)
		- v * r.dot(v)
	) / mu
	eccentricity = e_vec.length()
	semi_latus_rectum = h_magnitude_squared / mu
	var semi_major_denominator := 1.0 - eccentricity * eccentricity
	if absf(semi_major_denominator) > EPSILON:
		semi_major_axis = semi_latus_rectum / semi_major_denominator
	else:
		semi_major_axis = INF

	if eccentricity < CIRCULAR_EPSILON:
		p_hat = r.normalized()
	else:
		p_hat = e_vec.normalized()
	q_hat = w_hat.cross(p_hat).normalized()

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


func get_orbit_point(true_anomaly: float) -> Vector3:
	if degenerate:
		return Vector3.ZERO

	var denominator := 1.0 + eccentricity * cos(true_anomaly)
	if absf(denominator) <= EPSILON:
		return Vector3.ZERO

	var radius := semi_latus_rectum / denominator
	return radius * (cos(true_anomaly) * p_hat + sin(true_anomaly) * q_hat)


func get_true_anomaly_for_position(r: Vector3) -> float:
	if degenerate or r.length_squared() <= EPSILON:
		return 0.0

	return atan2(r.dot(q_hat), r.dot(p_hat))


func is_closed() -> bool:
	return eccentricity < 1.0


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
