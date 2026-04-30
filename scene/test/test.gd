extends Node

@onready var orbit_camera := $CameraOrbitRoot
@onready var earth_vessel := $Z1/Vessel
@onready var moon_vessel := $Z2/Vessel

var target = earth_vessel

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		if target == earth_vessel:
			target = moon_vessel
		else:
			target = earth_vessel
		orbit_camera.target = target
