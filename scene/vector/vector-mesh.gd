## Debug vector visualizer drawn as an ImmediateMesh line with a four-fin
## arrowhead.
##
## This node is intentionally just a mesh primitive:
## - callers set this node's transform explicitly
## - callers feed a vector expressed in this node's local axes
##
## In the current harness the view layer owns the anchor transform, while the
## coordinator owns scene/simulation/render conversion. `VectorMesh` should not
## guess which parent transform to follow or which frame the vector belongs to.
@tool
class_name VectorMesh

extends MeshInstance3D


@export var vector: Vector3 = Vector3(1, 0, 0):
	set(p_vector):
		vector = p_vector
		_create_lines()

## Scalar that converts source units such as Newtons or m/s into visible arrow
## length in this node's local space.
##
## Why it is exposed:
## - different debug quantities have very different magnitudes
## - the view layer can tune readability without corrupting the underlying data
##
## Runtime role:
## - multiplies the vector
@export var length_scale: float = 1.0:
	set(p_length_scale):
		length_scale = p_length_scale
		_create_lines()


@export var material: StandardMaterial3D = StandardMaterial3D.new():
	set(p_material):
		material = p_material


func _ready() -> void:
	_create_lines()


func _process(_delta: float) -> void:
	_create_lines()
	global_rotation = Vector3.ZERO


func _create_lines() -> void:
	if not is_inside_tree():
		return

	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	mesh.surface_add_vertex(Vector3.ZERO)

	var scaled_vector := vector * length_scale
	mesh.surface_add_vertex(scaled_vector)

	if scaled_vector.length() > 0.001:
		var dir := scaled_vector.normalized()
		var base_arrow := scaled_vector - dir * minf(0.1, scaled_vector.length() * 0.3)
		var ref_axis := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var u_vector := scaled_vector.cross(ref_axis).normalized() * 0.05
		var v_vector := scaled_vector.cross(u_vector).normalized() * 0.05

		mesh.surface_add_vertex(scaled_vector)
		mesh.surface_add_vertex(base_arrow + u_vector)

		mesh.surface_add_vertex(scaled_vector)
		mesh.surface_add_vertex(base_arrow - u_vector)

		mesh.surface_add_vertex(scaled_vector)
		mesh.surface_add_vertex(base_arrow + v_vector)

		mesh.surface_add_vertex(scaled_vector)
		mesh.surface_add_vertex(base_arrow - v_vector)

	mesh.surface_end()
