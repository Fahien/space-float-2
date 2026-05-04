class_name EngineModel

extends RigidBody3D

@export_range(0.0, 1000000.0, 1.0, "suffix:N")
var thrust : float = 16000.0

@export_range(0.0, 1000.0, 0.1, "suffix:s")
var specific_impulse: float = 311.0

@export_range(0.0, 1000.0, 0.01, "suffix:kg/s")
var mass_flow_rate: float = 5.25

@export
var plume: MeshInstance3D = null

var throttle: float = 0.0

func _process(_delta: float) -> void:
	if plume != null:
		plume.visible = throttle > 0.0
