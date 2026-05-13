## Chapter: The Body Beneath the Orbit
##
## Every active craft, tank, and engine eventually has to answer the same
## question: what does the sky around me pull on, and which world defines the
## local environment? `GravityRigidBody3D` is the small adapter that lets a
## scene-authored `RigidBody3D` join that larger celestial system without
## carrying its own map of planets.
##
## The class registers itself with `CelestialBodySystem` when it enters the
## scene tree and unregisters when it leaves. During physics integration it asks
## the system to apply the full gravitational acceleration from every registered
## `CelestialBody3D`. At the same time, the system records the strongest
## current source in `current_primary`, giving UI, camera, atmosphere, and later
## drag code a stable answer to the local-environment question.
##
## This base class deliberately stops at shared environment plumbing. It does
## not command engines, spend propellant, switch gravity to a sphere of
## influence, or author planet data. Subclasses remain free to add propulsion or
## vehicle behavior after this common gravity step has established the physical
## setting for the frame.
class_name GravityRigidBody3D

extends RigidBody3D

## Strongest registered celestial gravity source at the body's last gravity
## application point.
##
## Gravity itself remains a superposition of all valid sources. This cache is
## environmental context: the body most useful for local down, atmosphere,
## debug readouts, and future frame-of-reference work.
var current_primary: CelestialBody3D = null


func _enter_tree() -> void:
	CelestialBodySystem.register_body(self)


func _exit_tree() -> void:
	CelestialBodySystem.unregister_body(self)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	CelestialBodySystem.apply_gravity(self, state)
