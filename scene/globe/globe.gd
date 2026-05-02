@tool
extends Node3D

## Cube-sphere globe assembly node.
##
## `Globe` owns the scene-level structure for a planet mesh, but deliberately
## leaves the per-tile mesh generation to `Patch`. Its job is to:
## - instantiate one `Patch` scene for each visible cube-face tile
## - walk a fixed quadtree from LOD 0 down to the requested leaf `lod`
## - pass face, tile-origin, quadrant, LOD, and material inputs into each patch
## - let each patch generate its local render/collision children and apply its
##   own cube-face transform
## - keep editor-generated children owned by the edited scene so the globe can
##   be previewed and saved from the inspector
##
## Coordinate contract:
## - every cube face is addressed in normalized 0..1 UV space
## - LOD 0 is a single tile covering the whole face
## - each deeper LOD splits a tile into four quadrants
## - `x`/`y` passed to `Patch` are the accumulated parent-tile origin
## - `u`/`v` passed to `Patch` select the child quadrant inside that origin
##
## Generated subtree:
## - all generated face content lives below the authored `Faces` child node
## - branch nodes named `Level_*` exist only to group quadtree levels
## - leaf nodes are `Patch` roots with generated mesh/collision children
## - rebuilding clears and recreates this generated subtree
class_name Globe

## Packed scene used for each generated globe tile.
##
## The scene is expected to instantiate as `Patch`. `Globe` configures each
## instance through `Patch._init_face()`, so the packed scene should provide the
## seed mesh and any patch-local authoring defaults. Reassigning this value
## updates editor warnings and attempts a rebuild when this node is already in
## the scene tree.
@export
var patch: PackedScene = null:
	set(p_patch):
		patch = p_patch
		update_configuration_warnings()
		_build()

## Target quadtree leaf level for every cube face.
##
## LOD 0 creates six leaf patches, one for each cube face. Each increment
## subdivides every face tile into four children, producing `6 * 4^lod` leaf
## patches. This node currently builds a uniform LOD across the whole globe;
## there is no camera-dependent or per-face refinement here.
@export
var lod := 0:
	set(p_lod):
		lod = p_lod
		_build()

## Shared material applied to generated patch meshes.
##
## New patch instances receive this value before `Patch.build()` runs. Existing
## generated `MeshInstance3D` descendants are updated in place by the setter so
## material edits in the inspector do not require a full rebuild.
@export
var material: StandardMaterial3D = null:
	set(p_material):
		material = p_material
		_apply_material()

## Authored container for generated face nodes.
##
## Keeping generated content under a stable child makes rebuilds simple and
## prevents editor-time output from being mixed with other authored children of
## the `Globe` node.
@onready
var faces := $Faces


## Reports missing authoring inputs in the editor inspector.
##
## The build path can safely return without a patch scene, but a configuration
## warning makes an incomplete globe scene obvious while authoring.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if patch == null:
		warnings.append("Patch is not assigned. Set 'patch' property to a Patch scene.")
		
	return warnings


## Finalizes editor/runtime setup once child paths are available.
##
## The material pass covers any generated children that were serialized in the
## scene file or created by editor-time property setters before `_ready()`.
func _ready() -> void:
	_apply_material()
	update_configuration_warnings()


## Removes all generated face content from the `Faces` container.
##
## Rebuilds are destructive by design: the quadtree shape, tile coordinates,
## face transforms, and patch meshes are all derived output from the current
## exported properties. Detaching children immediately keeps the editor tree in
## sync, while `queue_free()` lets Godot dispose of them safely.
func _clear_faces() -> void:
	for child in faces.get_children():
		faces.remove_child(child)
		child.queue_free()


## Rebuilds the entire globe from the current exported properties.
##
## This method is called from property setters in tool mode, so it must tolerate
## being invoked before the node is ready. Once inside the tree, it clears stale
## generated output first, then creates all six cube faces at the requested LOD.
##
## `Patch.build()` owns mesh and collision generation. `Globe` only owns the
## scene hierarchy and the high-level face/quadtree traversal.
func _build() -> void:
	if not is_inside_tree():
		return

	_clear_faces()

	if patch == null:
		return

	if faces == null:
		return

	var instances = []

	# Build order is kept explicit so the six serialized face values are easy
	# to compare with `Patch.Face` and with generated scene output.
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


## Creates one quadtree branch or one leaf patch for a cube face.
##
## Parameters:
## - `parent`: node that receives the branch node or leaf patch generated here
## - `face`: cube face being populated
## - `level`: current quadtree depth, where 0 covers a whole face
## - `x`/`y`: accumulated parent-tile origin in normalized face UV space
## - `u`/`v`: quadrant of the current tile inside its parent, each 0 or 1
##
## Branch behavior:
## - when `level` is lower than `lod`, this creates a grouping node and recurses
##   into the four child quadrants
## - child origins are advanced by this level's tile width before the next
##   recursive step
##
## Leaf behavior:
## - when `level` equals `lod`, this instantiates `patch` as `Patch`
## - all patch inputs are passed to `Patch._init_face()`, which applies the
##   face transform and rebuilds the patch-local generated children
func _instantiate_face(parent: Node3D, face: Patch.Face, level: int = 0, x: float = 0.0, y: float = 0.0, u: int = 0, v: int = 0) -> void:
	if patch == null:
		push_error("Patch is not assigned. Cannot instantiate face.")
		return

	if level < 0:
		push_error("Invalid LOD level. Cannot instantiate face.")
		return

	# At each level, `face_width` describes the current tile size in normalized
	# face space. Child tile origins advance by this amount before their own
	# next-level width is computed.
	var face_width = 1.0 / pow(2, level)
	
	if level != lod:
		var level_node = Node3D.new()
		level_node.name = "Level_%d_%d_%d" % [level, u, v]
		parent.add_child(level_node)
		if Engine.is_editor_hint():
			level_node.owner = get_tree().edited_scene_root
		
		var next_level = level + 1

		# `x`/`y` are the parent origin. `u`/`v` select which quadrant this node
		# represents at the current level, so the child origin is offset before
		# the recursion chooses each child's own quadrant.
		var next_x = x + u * face_width
		var next_y = y + v * face_width

		_instantiate_face(level_node, face, next_level, next_x, next_y, 0, 0)
		_instantiate_face(level_node, face, next_level, next_x, next_y, 0, 1)
		_instantiate_face(level_node, face, next_level, next_x, next_y, 1, 0)
		_instantiate_face(level_node, face, next_level, next_x, next_y, 1, 1)

		return

	var instance = patch.instantiate() as Patch
	assert(instance != null)
	instance._init_face(parent, instance.seed_mesh, face, level, x, y, u, v, material)


## Applies the current material to every generated mesh instance.
##
## This is intentionally a traversal instead of a rebuild. Material changes are
## render-state updates; regenerating every patch mesh and collision shape would
## add editor churn without changing geometry.
func _apply_material() -> void:
	if faces == null:
		return

	# Generated mesh instances are nested below patch and offset nodes, so walk
	# the whole subtree instead of assuming a fixed child depth.
	var nodes = [faces]
	while !nodes.is_empty():
		var node = nodes.pop_front()
		for child in node.get_children():
			if child is MeshInstance3D:
				child.set_surface_override_material(0, material)
			elif child is Node:
				nodes.append(child)
