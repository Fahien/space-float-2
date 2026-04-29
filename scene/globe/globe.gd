@tool
extends Node3D

enum Face {
	FRONT,
	RIGHT,
	UP,
	BACK,
	LEFT,
	BOTTOM
}

@export
var patch: PackedScene = null:
	set(p_patch):
		patch = p_patch
		update_configuration_warnings()
		_build()

@export
var albedo: Texture2D = null:
	set(p_albedo):
		albedo = p_albedo
		_update_albedo()
		
@onready
var faces := $Faces
		

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if patch == null:
		warnings.append("Patch is not assigned. Set 'patch' property to a MeshInstance3D.")
		
	return warnings

func _ready() -> void:
	update_configuration_warnings()

func _clear_faces() -> void:
	for child in faces.get_children():
		faces.remove_child(child)
		child.queue_free()

func _build() -> void:
	if not is_inside_tree():
		return

	_clear_faces()

	if patch == null:
		return

	var instances = []

	instances.push_back(_instantiate_face(Face.FRONT))
	instances.push_back(_instantiate_face(Face.RIGHT))
	instances.push_back(_instantiate_face(Face.UP))
	instances.push_back(_instantiate_face(Face.BACK))
	instances.push_back(_instantiate_face(Face.LEFT))
	instances.push_back(_instantiate_face(Face.BOTTOM))
	
	for instance in instances:
		faces.add_child(instance)
		if Engine.is_editor_hint():
			instance.owner = get_tree().edited_scene_root

	_update_albedo()

func _instantiate_face(face: Face) -> MeshInstance3D:
	var instance = patch.instantiate() as MeshInstance3D

	# Let's transform the vertices of the patch.
	var vertices = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var indices = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var uvs = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]

	for i in range(vertices.size()):
		var vertex = vertices[i]
		# Let's use the algebraic sigmoid function to create a better distribution of vertices on the sphere.
		var sigma = 0.87 * 0.87
		var uv = uvs[i]
		uv.y = 1.0 - uv.y # Flip the V coordinate to match the expected orientation.
		vertex.x = (2 * uv.x - 1) / sqrt(1.0 - 4 * sigma * uv.x * (uv.x - 1.0))
		vertex.y = (2 * uv.y - 1) / sqrt(1.0 - 4 * sigma * uv.y * (uv.y - 1.0))
		vertex.z = 1.0
		vertices[i] = vertex.normalized()

	var l_rotation = Basis()

	match face:
		Face.RIGHT:
			l_rotation = Basis(Vector3(0, 1, 0), PI / 2.0)
		Face.UP:
			l_rotation = Basis(Vector3(1, 0, 0), -PI / 2.0)
		Face.BACK:
			l_rotation = Basis(Vector3(0, 1, 0), PI)
		Face.LEFT:
			l_rotation = Basis(Vector3(0, 1, 0), -PI / 2.0)
		Face.BOTTOM:
			l_rotation = Basis(Vector3(1, 0, 0), PI / 2.0)

	for i in range(vertices.size()):
		uvs[i] = _direction_to_equirectangular_uv(l_rotation * vertices[i])

	instance.transform.basis = l_rotation

	var arrays = instance.mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs

	var new_mesh = ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material = instance.mesh.surface_get_material(0).duplicate() as StandardMaterial3D

	new_mesh.surface_set_material(0, material)

	instance.mesh = new_mesh
	return instance


func _direction_to_equirectangular_uv(direction: Vector3) -> Vector2:
	if direction.is_zero_approx():
		return Vector2.ZERO
	var x = atan2(direction.x, direction.z) / (2.0 * PI) + 0.5
	var y = 0.5 - asin(clampf(direction.y, -1.0, 1.0)) / PI
	return Vector2(x, y)


func _update_albedo() -> void:
	if faces == null:
		return

	for child in faces.get_children():
		if child is MeshInstance3D:
			var material = child.get_active_material(0)
			if material is StandardMaterial3D:
				material.albedo_texture = albedo
