extends GdUnitTestSuite


func test_camera_orbit_registers_relative_floating_origin_path() -> void:
	var root := auto_free(BigSpaceRoot3D.new()) as BigSpaceRoot3D
	root.name = "Root"

	var grid := BigGrid3D.new()
	grid.name = "Grid"
	root.add_child(grid)

	var camera_scene := load("res://scene/test/camera_orbit.tscn") as PackedScene
	var camera_orbit := camera_scene.instantiate() as CameraOrbit
	grid.add_child(camera_orbit)
	add_child(root)

	assert_object(camera_orbit).is_not_null()
	assert_that(root.floating_origin_path).is_equal(NodePath("Grid/CameraOrbitRoot"))
	assert_object(root.get_node_or_null(root.floating_origin_path)).is_same(camera_orbit)
