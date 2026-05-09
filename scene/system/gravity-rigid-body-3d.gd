class_name GravityRigidBody3D

extends RigidBody3D


func _enter_tree() -> void:
	CelestialBodySystem.register_body(self)


func _exit_tree() -> void:
	CelestialBodySystem.unregister_body(self)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	CelestialBodySystem.apply_gravity(state)
