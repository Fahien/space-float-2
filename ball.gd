extends MeshInstance3D

var acc := 0.0
var original_pos := 0.0

func _ready() -> void:
	original_pos = position.z

func _process(delta: float) -> void:
	acc += delta
	if acc > 2.0 * PI:
		acc -= 2.0 * PI
	position.z = original_pos + sin(acc) * delta * 6000.0
