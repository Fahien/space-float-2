@tool
class_name Patch

extends MeshInstance3D

enum Face {
 FRONT = 0,
 RIGHT = 1,
 UP = 2,
 BACK = 3,
 LEFT = 4,
 BOTTOM = 5,
 COUNT = 6,
}


var face: Face = Face.FRONT
var lod: int = 0


func set_face(p_face: Face) -> void:
	face = p_face


func set_lod(p_lod: int) -> void:
	lod = p_lod
