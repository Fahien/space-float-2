@tool
extends Node3D

class_name Globe

@export
var patch: PackedScene = null:
	set(p_patch):
		patch = p_patch
		update_configuration_warnings()
		_build()

@export
var lod := 0:
	set(p_lod):
		lod = p_lod
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

	if faces == null:
		return

	var instances = []

	_instantiate_face(faces, Patch.Face.FRONT)
	_instantiate_face(faces, Patch.Face.RIGHT)
	_instantiate_face(faces, Patch.Face.UP)
	_instantiate_face(faces, Patch.Face.BACK)
	_instantiate_face(faces, Patch.Face.LEFT)
	_instantiate_face(faces, Patch.Face.BOTTOM)
	
	for instance in instances:
		faces.add_child(instance)
		if Engine.is_editor_hint():
			instance.owner = get_tree().edited_scene_root

	_update_albedo()


func _instantiate_face(parent: Node3D, face: Patch.Face, level: int = 0, x: float = 0.0, y: float = 0.0, u: int = 0, v: int = 0) -> void:
	if patch == null:
		push_error("Patch is not assigned. Cannot instantiate face.")
		return

	if level < 0:
		push_error("Invalid LOD level. Cannot instantiate face.")
		return

	var face_width = 1.0 / pow(2, level)
	
	if level != lod:
		var level_node = Node3D.new()
		level_node.name = "Level_%d_%d_%d" % [level, u, v]
		parent.add_child(level_node)
		if Engine.is_editor_hint():
			level_node.owner = get_tree().edited_scene_root
		
		var next_level = level + 1

		var next_x = x + u * face_width
		var next_y = y + v * face_width

		_instantiate_face(level_node, face, next_level, next_x, next_y, 0, 0)
		_instantiate_face(level_node, face, next_level, next_x, next_y, 0, 1)
		_instantiate_face(level_node, face, next_level, next_x, next_y, 1, 0)
		_instantiate_face(level_node, face, next_level, next_x, next_y, 1, 1)

		return

	var instance = patch.instantiate() as Patch
	assert(instance != null)
	instance.set_face(face)
	instance.set_lod(level)

	# Let's transform the vertices of the patch.
	var vertices = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var indices = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var normals = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var uvs = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]

	for i in range(uvs.size()):
		var uv = uvs[i]
		uv.x = face_width * uv.x + float(u) * face_width + x
		uv.y = face_width * uv.y + float(v) * face_width + y
		uvs[i] = uv

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

	var l_basis = Basis()

	match face:
		Patch.Face.RIGHT:
			l_basis = Basis(Vector3(0, 1, 0), PI / 2.0)
		Patch.Face.UP:
			l_basis = Basis(Vector3(1, 0, 0), -PI / 2.0)
		Patch.Face.BACK:
			l_basis = Basis(Vector3(0, 1, 0), PI)
		Patch.Face.LEFT:
			l_basis = Basis(Vector3(0, 1, 0), -PI / 2.0)
		Patch.Face.BOTTOM:
			l_basis = Basis(Vector3(1, 0, 0), PI / 2.0)

	var l_scale = Vector3.ONE / float(1)
	l_basis = l_basis.scaled(l_scale)
	#instance.transform.basis = l_basis

	for i in range(vertices.size()):
		uvs[i] = _direction_to_equirectangular_uv(l_basis * vertices[i])

	var arrays = instance.mesh.surface_get_arrays(0)

	for i in range(vertices.size()):
		normals[i] = vertices[i]
		vertices[i].z -= 1.0
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs

	var new_mesh = ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material = instance.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	material.albedo_texture = albedo

	new_mesh.surface_set_material(0, material)

	instance.mesh = new_mesh

	# Create a static body for collision
	var static_body = StaticBody3D.new()
	instance.add_child(static_body)
	var collision_shape = CollisionShape3D.new()
	var shape = new_mesh.create_trimesh_shape()
	collision_shape.shape = shape
	static_body.add_child(collision_shape)

	var rotation_node = Node3D.new()
	rotation_node.position = Vector3(0.0, 0.0, 1.0)
	rotation_node.add_child(instance)

	var wrapper_node = Node3D.new()
	wrapper_node.add_child(rotation_node)
	wrapper_node.transform.basis = l_basis

	parent.add_child(wrapper_node)
	if Engine.is_editor_hint():
		rotation_node.owner = get_tree().edited_scene_root
		wrapper_node.owner = get_tree().edited_scene_root
		instance.owner = get_tree().edited_scene_root
		static_body.owner = get_tree().edited_scene_root
		collision_shape.owner = get_tree().edited_scene_root


func _direction_to_equirectangular_uv(direction: Vector3) -> Vector2:
	if direction.is_zero_approx():
		return Vector2.ZERO
	var x = atan2(direction.x, direction.z) / (2.0 * PI) + 0.5
	var y = 0.5 - asin(clampf(direction.y, -1.0, 1.0)) / PI
	return Vector2(x, y)


func _update_albedo() -> void:
	if faces == null:
		return

	for child in faces.get_children(true):
		if child is MeshInstance3D:
			var material = child.get_active_material(0)
			if material is StandardMaterial3D:
				material.albedo_texture = albedo
