extends BigNode3D

var acc := 0.0

func _process(delta: float) -> void:
	acc += delta
	if acc > 2.0 * PI:
		acc -= 2.0 * PI
	var new_pos = Vector3.ZERO
	new_pos.x = sin(acc * 2.0) * delta * 1000.0
	set_big_position_in_parent_grid_space(new_pos, cell_x, cell_y, cell_z)
