@tool
extends Node3D

## Cube-sphere globe assembly node.
##
## `Globe` owns the scene-level structure for a planet mesh, but deliberately
## leaves the per-tile mesh generation to `Patch`. Its job is to:
## - instantiate one root `Patch` scene for each cube face
## - pass face, tile-origin, quadrant, material, and scale inputs into each patch
## - let each patch generate its local render/collision children and apply its
##   own cube-face transform
## - let patches split and join their own runtime quadtree nodes
## - keep editor-generated children owned by the edited scene so the globe can
##   be previewed and saved from the inspector
##
## Coordinate contract:
## - every cube face is addressed in normalized 0..1 UV space
## - each root patch starts at LOD 0 and covers one whole cube face
## - child patches accumulate `x`/`y` origins and `u`/`v` quadrants while
##   subdividing from their parent patch
## - `geometry_scale` scales patch-local sphere geometry before any parent
##   scene transform is applied
##
## Generated subtree:
## - all generated face content lives below the authored `Faces` child node
## - root face nodes are `Patch` instances
## - leaf patches own generated mesh/collision children
## - branch patches own four child patches instead of generated mesh
## - rebuilding clears and recreates the root face nodes
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


## Multiplier applied to generated patch geometry before parent transforms.
##
## This keeps the surrounding scene free to use coarse origin/grid scale while
## `Patch` still builds meshes around a stable local sphere radius.
@export_range(1.0, 10000.0, 10.0)
var geometry_scale := 1.0:
	set(p_geometry_scale):
		geometry_scale = p_geometry_scale
		_build()


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
## The initial build is delayed until `_ready()` because the authored `Faces`
## child is resolved with `@onready`. The material pass covers any generated
## children serialized in the scene file or created by editor-time setters.
func _ready() -> void:
	_build()
	set_process(true)
	_apply_material()
	update_configuration_warnings()


## Removes all generated face content from the `Faces` container.
##
## Rebuilds are destructive by design: the root face nodes and their patch-local
## descendants are derived output from the current exported properties.
## Detaching children immediately keeps the editor tree in sync, while
## `queue_free()` lets Godot dispose of them safely.
func _clear_faces() -> void:
	for child in faces.get_children():
		faces.remove_child(child)
		child.queue_free()


## Rebuilds the entire globe from the current exported properties.
##
## This method is called from property setters in tool mode, so it must tolerate
## being invoked before the node is ready. Once inside the tree, it clears stale
## generated output first, then creates the six root cube-face patches.
##
## `Patch.build()` owns mesh and collision generation. `Globe` only owns the
## root face hierarchy and scene-level configuration shared by every patch.
func _build() -> void:
	if not is_inside_tree():
		return

	if faces == null:
		return

	_clear_faces()

	if patch == null:
		return

	# Build order is kept explicit so the six serialized face values are easy
	# to compare with `Patch.Face` and with generated scene output.
	_instantiate_face(faces, Patch.Face.FRONT)
	_instantiate_face(faces, Patch.Face.RIGHT)
	_instantiate_face(faces, Patch.Face.UP)
	_instantiate_face(faces, Patch.Face.BACK)
	_instantiate_face(faces, Patch.Face.LEFT)
	_instantiate_face(faces, Patch.Face.BOTTOM)
	

## Creates one root patch for a cube face.
##
## Parameters:
## - `parent`: node that receives the patch generated here
## - `face`: cube face being populated
## - `level`: quadtree depth, where 0 covers a whole face
## - `x`/`y`: accumulated parent-tile origin in normalized face UV space
## - `u`/`v`: quadrant of the current tile inside its parent, each 0 or 1
##
## `Globe` only creates LOD 0 roots. Runtime quadtree refinement happens inside
## each `Patch`, which calls `_init_face()` directly for its child patches.
func _instantiate_face(parent: Node3D, face: Patch.Face, level: int = 0, x: float = 0.0, y: float = 0.0, u: int = 0, v: int = 0) -> void:
	if patch == null:
		push_error("Patch is not assigned. Cannot instantiate face.")
		return

	if level < 0:
		push_error("Invalid LOD level. Cannot instantiate face.")
		return

	var instance = patch.instantiate() as Patch
	assert(instance != null)
	instance._init_face(parent, instance.seed_mesh, face, level, x, y, u, v, material, null, geometry_scale)


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
