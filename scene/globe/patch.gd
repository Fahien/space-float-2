@tool
## Mesh-backed globe tile generated from a square seed mesh.
##
## A `Patch` represents one quadtree tile on one cube face of a cube-sphere
## globe. The seed mesh supplies only the local tessellation and canonical
## 0..1 UV layout. `build()` remaps those UVs into the selected tile, projects
## the result onto a sphere, derives equirectangular texture coordinates, and
## creates both render geometry and matching trimesh collision.
##
## Coordinate model:
## - the seed mesh is treated as a flat tile on the unrotated FRONT face
## - `x`/`y` hold the parent tile origin in face UV space
## - `u`/`v` select the current child quadrant inside that origin
## - `lod` determines the current tile width as `1.0 / 2^lod`
## - `face` selects the cube face orientation used by the caller
##
## The generated mesh remains authored around local +Z. `Patch` stores the
## selected cube-face rotation on its own transform and creates a local +Z
## offset child so the same mesh-generation logic can serve every cube face.
##
## Seed mesh contract:
## - surface 0 must exist
## - surface 0 must contain vertex, index, normal, and UV arrays
## - UVs are expected to cover the 0..1 tile domain
## - the seed resource is read as input; generated arrays are assigned to a new
##   `ArrayMesh` rather than written back into the seed mesh
class_name Patch

extends Node3D

## Cube-map faces that make up the globe.
##
## `FRONT` is the unrotated seed orientation. All other faces are described as
## rotations from that local +Z-facing tile. The explicit integer values keep
## serialized scenes stable if entries are reordered later.
enum Face {
	## Unrotated +Z cube face.
	FRONT = 0,
	## +X cube face, reached by rotating the front face around global Y.
	RIGHT = 1,
	## +Y cube face, reached by rotating the front face around global X.
	UP = 2,
	## -Z cube face, opposite the front face.
	BACK = 3,
	## -X cube face, reached by rotating the front face around global Y.
	LEFT = 4,
	## -Y cube face, reached by rotating the front face around global X.
	BOTTOM = 5,
	## Number of concrete faces. Kept in the enum for bounds/iteration helpers.
	COUNT = 6,
}

## Button to trigger subdivision in the editor.
@export_tool_button("Subdivide", "Callable") var subdivide_button = subdivide
@export_tool_button("Join", "Callable") var join_button = join

## Source tessellation used to build the generated patch mesh.
##
## The seed mesh is not displayed directly. Its surface-0 arrays are copied,
## remapped, and installed on a new `ArrayMesh` whenever this patch rebuilds.
## Reassigning the seed in the editor updates warnings and immediately attempts
## a rebuild so authoring feedback stays visible.
@export var seed_mesh: Mesh = null:
	set(p_seed_mesh):
		seed_mesh = p_seed_mesh
		update_configuration_warnings()
		build()

## Cube face this patch belongs to.
##
## The value affects two things during `build()`:
## - texture UVs are derived from the face-rotated direction, so an
##   equirectangular material samples the correct planet longitude/latitude
## - this node's transform basis rotates the front-face patch into final globe
##   placement
@export var face: Face = Face.FRONT:
	set(p_face):
		face = p_face
		build()

## Quadtree level for this tile.
##
## Level 0 covers an entire cube face. Each higher level halves the tile width
## in both axes. The exported range is an editor/authoring limit for this
## prototype; `get_face_width()` is the source of truth used by the build math.
@export_range(0, 3, 1) var lod: int = 0:
	set(p_lod):
		lod = p_lod
		build()

## Parent tile origin on the cube face's U axis, expressed in 0..1 face space.
##
## `Globe._instantiate_face()` accumulates this while walking the quadtree. The
## local `u` quadrant offset is applied in addition to this value.
@export var x: float = 0.0

## Parent tile origin on the cube face's V axis, expressed in 0..1 face space.
##
## This mirrors `x` for the vertical face coordinate. The build step flips V
## later when converting from UV-space convention to sphere-space orientation.
@export var y: float = 0.0

## Horizontal child quadrant inside the current parent tile.
##
## Only 0 and 1 are valid because each quadtree step splits a parent tile into
## four children. Changing this in the editor rebuilds the generated mesh.
@export_range(0, 1, 1) var u: int = 0:
	set(p_u):
		u = p_u
		build()

## Vertical child quadrant inside the current parent tile.
##
## Only 0 and 1 are valid because each quadtree step splits a parent tile into
## four children. Changing this in the editor rebuilds the generated mesh.
@export_range(0, 1, 1) var v: int = 0:
	set(p_v):
		v = p_v
		build()


## Optional material override applied to the generated mesh surface.
##
## `Globe` forwards its material into each patch instance before building. The
## material is not duplicated here; all patches can share the same resource.
@export var material: Material


## Whether this patch evaluates camera-dependent LOD changes every frame.
@export var process: bool = true:
	set(p_process):
		process = p_process
		set_process(p_process)


## Minimum time between split/join decisions for this patch.
##
## The cooldown prevents a patch near the distance threshold from repeatedly
## rebuilding its subtree in consecutive frames.
@export var lod_decision_cooldown := 0.25


## Deepest dynamic LOD this patch can create.
##
## Code-created children may exceed the editor range on `lod`; this value is the
## runtime guard used by `_process()` before calling `subdivide()`.
@export_range(0, 10, 1) var max_lod := 10


## Optional debug scene used to draw this patch's radial center direction.
@export var debug_vector: PackedScene = null


## Whether generated terrain triangles should collide from their back side too.
##
## A globe patch is a zero-thickness concave trimesh. Enabling backfaces does
## not replace continuous collision detection on fast bodies, but it makes a
## missed terrain contact less likely to become an unrecoverable fall through
## the hollow surface.
@export var collision_backface_enabled: bool = true


## Local radius multiplier for generated geometry.
##
## Vertex normals and texture lookup stay in unit-sphere space. Only final
## vertex positions and the matching +Z offset are scaled.
@export_range(1.0, 1000.0, 1.0) var geometry_scale: float = 1.0:
	set(p_geometry_scale):
		geometry_scale = p_geometry_scale
		build()


## Remaining time before this patch can change LOD again.
var _lod_cooldown_left := 0.0

## True while this patch owns generated mesh/collision children directly.
##
## A non-leaf patch has replaced its own mesh with four child `Patch` nodes.
var _is_leaf: bool = true


func _ready() -> void:
	set_process(process)
	update_configuration_warnings()


## Reports editor warnings for missing authoring inputs.
##
## The build path also guards against a missing seed mesh, but surfacing the
## problem as a configuration warning makes broken patch scenes obvious in the
## inspector before play mode or a parent `Globe` tries to instantiate them.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if seed_mesh == null:
		warnings.append("Seed mesh is not assigned. Set 'seed_mesh' property to a Mesh.")

	return warnings


## Sets the cube face for callers that configure packed scene instances in code.
##
## This assigns through the exported property, so it may rebuild immediately.
## Callers that set several patch properties should still perform one explicit
## `build()` after all values are in place.
func set_face(p_face: Face) -> void:
	face = p_face


## Sets the quadtree level for callers that configure packed scene instances.
##
## Assigning through the exported property setter may rebuild immediately,
## depending on call context. Callers that set several properties should still
## perform one explicit `build()` after all values are in place.
func set_lod(p_lod: int) -> void:
	lod = p_lod


## Returns this tile's width in normalized cube-face UV space.
##
## A full face at LOD 0 has width 1.0. Each additional LOD doubles the number
## of tiles along an axis, so the width becomes 1/2, 1/4, 1/8, and so on.
func get_face_width() -> float:
	return 1.0 / pow(2, lod)


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()


## Rebuilds render and collision geometry for the current tile configuration.
##
## The method reads the seed mesh, transforms its UVs into this patch's face
## region, projects the resulting square tile onto the unit sphere, scales the
## final vertex positions by `geometry_scale`, and stores the generated data on
## a fresh `ArrayMesh`.
##
## Side effects:
## - updates this node's transform basis for the selected cube face
## - schedules existing generated child nodes for deletion
## - creates a +Z offset child containing a new `MeshInstance3D`
## - creates a new `StaticBody3D` with a trimesh collision shape below the mesh
## - applies `material` as a surface override when present
func build():
	if not is_inside_tree():
		return

	if seed_mesh == null:
		push_error("Seed mesh is not assigned. Cannot build patch.")
		return Basis()

	# Children are generated output for this node. A rebuild discards the
	# previous output so the render mesh and physics shape stay in sync.
	_clear_children()

	# Pull the seed arrays that define topology and per-vertex attributes. The
	# seed mesh supplies topology; this method owns the generated positions,
	# normals, and texture coordinates.
	var vertices = seed_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var indices = seed_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var normals = seed_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var uvs = seed_mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]

	# Move seed UVs from local 0..1 tile space into this tile's location on the
	# current cube face. `x`/`y` are the accumulated parent origin and `u`/`v`
	# choose the child quadrant at this LOD.
	for i in range(uvs.size()):
		uvs[i] = _transform_uv_to_patch_uv(uvs[i])

	# Project face-space UVs onto the unit sphere. The algebraic sigmoid term
	# softens the otherwise dense clustering caused by normalizing cube-face
	# coordinates directly, giving a more even vertex distribution.
	for i in range(vertices.size()):
		# Flip V so increasing face-space Y maps to the intended sphere-space
		# orientation before the equirectangular conversion runs.
		vertices[i] = _vertex_from_uv(uvs[i])

	# Rotate from the canonical front face to the requested cube face. The mesh
	# is not rotated directly; this node's basis provides final placement and is
	# also used immediately below for texture-coordinate lookup.
	match face:
		Patch.Face.FRONT:
			transform.basis = Basis()
		Patch.Face.RIGHT:
			transform.basis = Basis(Vector3(0, 1, 0), PI / 2.0)
		Patch.Face.UP:
			transform.basis = Basis(Vector3(1, 0, 0), -PI / 2.0)
		Patch.Face.BACK:
			transform.basis = Basis(Vector3(0, 1, 0), PI)
		Patch.Face.LEFT:
			transform.basis = Basis(Vector3(0, 1, 0), -PI / 2.0)
		Patch.Face.BOTTOM:
			transform.basis = Basis(Vector3(1, 0, 0), PI / 2.0)

	# Recompute material UVs from the final globe direction so one
	# equirectangular texture can wrap across all six cube faces.
	for i in range(vertices.size()):
		uvs[i] = _direction_to_equirectangular_uv(transform.basis * vertices[i])

	var arrays = seed_mesh.surface_get_arrays(0)

	# Normals remain radial unit directions. Vertex positions are scaled into
	# local globe units, then shifted back by the same radius because the
	# generated offset child translates the mesh forward before this patch root's
	# face rotation is applied.
	for i in range(vertices.size()):
		normals[i] = vertices[i]
		vertices[i] *= geometry_scale
		vertices[i].z -= geometry_scale
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var instance = MeshInstance3D.new()
	instance.mesh = mesh

	if material != null:
		instance.set_surface_override_material(0, material)

	# Create physics from the generated render mesh so collision matches the
	# current LOD, tile location, and projection exactly.
	var static_body = StaticBody3D.new()
	instance.add_child(static_body)

	var collision_shape = CollisionShape3D.new()
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape.backface_collision = collision_backface_enabled
	collision_shape.shape = shape
	static_body.add_child(collision_shape)

	# Translating by the same amount used for the local Z shift restores the
	# scaled front-face placement before this patch root rotates it into the
	# selected cube-face orientation.
	var offset_node = Node3D.new()
	offset_node.position = Vector3(0.0, 0.0, geometry_scale)
	offset_node.add_child(instance)
	add_child(offset_node)

	var debug_instance = null
	if debug_vector != null:
		debug_instance = debug_vector.instantiate() as VectorMesh
		debug_instance.vector = get_patch_center()
		add_child(debug_instance)

	# Generated editor children need ownership assigned or they will be visible
	# in the scene tree but not saved with the edited scene.
	if Engine.is_editor_hint():
		offset_node.owner = get_tree().edited_scene_root
		instance.owner = get_tree().edited_scene_root
		static_body.owner = get_tree().edited_scene_root
		collision_shape.owner = get_tree().edited_scene_root
		if debug_instance != null:
			debug_instance.owner = get_tree().edited_scene_root


func _transform_uv_to_patch_uv(uv: Vector2) -> Vector2:
	# The seed mesh is authored in 0..1 UV space. The build step transforms
	# those UVs into the appropriate face tile, but the original UVs are still
	# needed to calculate the vertex positions from the face-space coordinates.
	# This method reverses the face tile transform so the same UVs can be used
	# for both purposes without storing two separate arrays.
	var face_width = get_face_width()
	var patch_uv = Vector2()
	patch_uv.x = face_width * uv.x + float(u) * face_width + x
	patch_uv.y = face_width * uv.y + float(v) * face_width + y
	return patch_uv


func _vertex_from_uv(uv: Vector2) -> Vector3:
	var flipped_uv = Vector2(uv.x, 1.0 - uv.y)
	var vertex = Vector3()
	var sigma = 0.87 * 0.87
	vertex.x = (2 * flipped_uv.x - 1) / sqrt(1.0 - 4 * sigma * flipped_uv.x * (flipped_uv.x - 1.0))
	vertex.y = (2 * flipped_uv.y - 1) / sqrt(1.0 - 4 * sigma * flipped_uv.y * (flipped_uv.y - 1.0))
	vertex.z = 1.0
	return vertex.normalized()


## Converts a unit globe direction to equirectangular texture coordinates.
##
## `direction.x/z` determine longitude and `direction.y` determines latitude.
## Callers should pass normalized directions; the build path does this by
## normalizing each projected vertex before applying the face basis.
func _direction_to_equirectangular_uv(direction: Vector3) -> Vector2:
	if direction.is_zero_approx():
		return Vector2.ZERO
	var l_x = atan2(direction.x, direction.z) / (2.0 * PI) + 0.5
	var l_y = 0.5 - asin(clampf(direction.y, -1.0, 1.0)) / PI
	return Vector2(l_x, l_y)


## Replaces this leaf patch's generated mesh with four child patches.
##
## Children inherit the same face, material, debug-vector scene, and geometry
## scale. Each child receives an accumulated face-space origin plus its own
## quadrant selector.
func subdivide() -> void:
	_clear_children()

	var next_level = lod + 1
	var face_width = get_face_width()

	# Subdivision is a simple recursive instantiation of four child patches with
	# the next LOD and the appropriate tile coordinates for each quadrant.
	var next_x = x + float(u) * face_width
	var next_y = y + float(v) * face_width

	# Instantiate the four child patches for the next LOD level. The parent
	# tile's origin and quadrant offset are accumulated into the child tile's
	# origin before the recursive call applies the child's own quadrant offset.
	Patch.new()._init_face(self, seed_mesh, face, next_level, next_x, next_y, 0, 0, material, debug_vector, geometry_scale)
	Patch.new()._init_face(self, seed_mesh, face, next_level, next_x, next_y, 0, 1, material, debug_vector, geometry_scale)
	Patch.new()._init_face(self, seed_mesh, face, next_level, next_x, next_y, 1, 0, material, debug_vector, geometry_scale)
	Patch.new()._init_face(self, seed_mesh, face, next_level, next_x, next_y, 1, 1, material, debug_vector, geometry_scale)
	_is_leaf = false


## Configures and attaches a patch created by `Globe` or by parent subdivision.
##
## Property setters may try to build before the node enters the tree; the final
## explicit `build()` call below is the one that creates render and collision
## children after all inputs are assigned.
func _init_face(p_parent: Node, p_seed_mesh: Mesh, p_face: Patch.Face, p_level: int = 0, p_x: float = 0.0, p_y: float = 0.0, p_u: int = 0, p_v: int = 0, p_material: Material = null, p_debug_vector: PackedScene = null, p_geometry_scale: float = 1.0) -> void:
	seed_mesh = p_seed_mesh
	set_face(p_face)
	set_lod(p_level)
	x = p_x
	y = p_y
	u = p_u
	v = p_v
	material = p_material
	if p_debug_vector != null:
		debug_vector = p_debug_vector.duplicate(true)
	geometry_scale = p_geometry_scale
	p_parent.add_child(self)

	var parent_patch := p_parent as Patch
	if parent_patch != null:
		# Once a patch becomes a branch, its children carry the cube-face basis.
		# Resetting the branch basis avoids applying that face rotation twice.
		parent_patch.basis = Basis()

	if Engine.is_editor_hint():
		owner = p_parent.get_tree().edited_scene_root
	build()


## Collapses a branch patch back into one generated mesh/collision leaf.
func join() -> void:
	_clear_children()
	build()
	_is_leaf = true


func get_editor_camera(viewport_index: int = 0) -> Camera3D:
	if not Engine.is_editor_hint():
		return null
	if not Engine.has_singleton("EditorInterface"):
		return null

	var editor_interface := Engine.get_singleton("EditorInterface")
	var viewport := editor_interface.get_editor_viewport_3d(viewport_index) as SubViewport
	if viewport == null:
		return null

	return viewport.get_camera_3d()


## Returns the cube-face basis that positions this tile's unit-sphere direction.
func get_leaf_basis() -> Basis:
	var face_basis = Basis()
	match face:
		Patch.Face.FRONT:
			face_basis = Basis()
		Patch.Face.RIGHT:
			face_basis = Basis(Vector3(0, 1, 0), PI / 2.0)
		Patch.Face.UP:
			face_basis = Basis(Vector3(1, 0, 0), -PI / 2.0)
		Patch.Face.BACK:
			face_basis = Basis(Vector3(0, 1, 0), PI)
		Patch.Face.LEFT:
			face_basis = Basis(Vector3(0, 1, 0), -PI / 2.0)
		Patch.Face.BOTTOM:
			face_basis = Basis(Vector3(1, 0, 0), PI / 2.0)
	return face_basis


## Returns this tile's radial center direction in globe-local space.
func get_patch_center() -> Vector3:
	var center_direction = _vertex_from_uv(_transform_uv_to_patch_uv(Vector2(0.5, 0.5)))
	return get_leaf_basis() * center_direction


## Returns true only when every direct child patch has collapsed to a leaf.
##
## Non-patch children can remain queued for deletion immediately after a split,
## so the check filters them out instead of relying on child order.
func _direct_child_patches_are_leaves() -> bool:
	var child_patch_count := 0
	for child in get_children():
		var child_patch := child as Patch
		if child_patch == null:
			continue
		child_patch_count += 1
		if not child_patch._is_leaf:
			return false

	return child_patch_count > 0


func _process(delta: float) -> void:
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		camera = get_editor_camera()
		if camera == null:
			return

	_lod_cooldown_left = maxf(0.0, _lod_cooldown_left - delta)
	if _lod_cooldown_left > 0.0:
		return

	# Convert unit-sphere face width into world units. `geometry_scale` is baked
	# into vertices rather than the node basis, so it is applied explicitly here.
	var world_scale = global_transform.basis.get_scale().x * geometry_scale
	var patch_center = global_transform.origin + get_patch_center() * world_scale
	var distance = patch_center.distance_to(camera.global_position)
	var split_threshold = get_face_width() * world_scale * 1.1

	if lod < max_lod and _is_leaf:
		if distance < split_threshold:
			print("Subdividing patch at center ", patch_center, " LOD ", lod, " with distance ", distance)
			subdivide()
			_lod_cooldown_left = lod_decision_cooldown

	if not _is_leaf:
		if _direct_child_patches_are_leaves():
			# Hysteresis keeps the patch from joining immediately after a split.
			var join_threshold = split_threshold * 1.25
			if distance >= join_threshold:
				print("Joining patch at LOD ", lod, " with distance ", distance)
				join()
				_lod_cooldown_left = lod_decision_cooldown
