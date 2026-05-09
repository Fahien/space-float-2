## Core design

Use a **single solar-system physics service** as an Autoload, but do **not** make it a god object that manually teleports bodies. Let it centralize **gravity-field logic, source registration, body registration, source caching, orbit utilities, and debug tools**, while each `RigidBody3D` still interacts with Godot/Jolt through the normal physics integration path.

The best pattern is:

```text
SolarSystemPhysics          Autoload singleton
 ├─ knows all celestial gravity sources
 ├─ computes acceleration at any world position
 ├─ updates on-rails or n-body celestial states
 ├─ exposes helper methods for orbit prediction, local down, primary body, etc.
 └─ applies gravity through a thin RigidBody3D adapter

CelestialBody3D             Node3D / AnimatableBody3D / StaticBody3D
 ├─ position, velocity, rotation
 ├─ gravitational parameter μ = G * M
 ├─ radius, atmosphere, gravity model, source priority
 └─ registers itself with SolarSystemPhysics

GravityRigidBody3D          RigidBody3D subclass
 ├─ disables Godot’s default world-down gravity
 ├─ calls SolarSystemPhysics from _integrate_forces()
 ├─ receives central gravity force, optional tidal torque, drag, etc.
 └─ remains a normal Jolt rigid body for collisions
```

Godot Autoloads are suitable for this because an autoloaded script becomes a globally available node that is added before normal scenes load. Physics-related logic should run on physics ticks, not render frames, and Godot’s `RigidBody3D` API is designed around applying forces instead of directly controlling transforms every frame. ([Godot Engine documentation][1])

---

## The most important architectural decision

Do **not** simulate planets, moons, and stars as ordinary `RigidBody3D` objects and expect Jolt to solve the whole solar system by collisions and body forces. Treat major celestial bodies as **gravitational sources** and usually as **kinematic/on-rails physical scenery**.

That gives you three clean tiers:

### Tier 1: Major celestial bodies

The Sun, planets, and major moons are `CelestialBody3D` sources. Their transforms come from either:

```text
ephemeris / Kepler orbit / scripted orbit / custom n-body integrator
```

They provide gravity to rigid bodies, but normal crates, ships, landers, rocks, and players do not significantly pull the planets back.

This is the right default for a game-scale solar system.

### Tier 2: Important dynamic massive objects

Large asteroids, stations, comets, or artificial megastructures may be both:

```text
gravity source + affected dynamic object
```

For these, register them as sources, but be careful to exclude self-gravity.

### Tier 3: Normal rigid bodies

Vehicles, debris, cargo, landers, characters, projectiles, and props are ordinary `RigidBody3D` objects affected by the celestial gravity field.

They should usually **not** be gravity sources unless the gameplay specifically requires it.

---

## Use gravitational parameter, not raw mass, for sources

For a source at position `S`, and a body at position `P`:

```text
r = S - P
a = μ * r / |r|^3
```

Where:

```text
μ = G * M
```

`a` is acceleration in world-units per second squared. If you use `1 Godot unit = 1 meter`, then `μ` should be in `m^3 / s^2`.

For a target rigid body of mass `m`:

```text
F = m * a
```

The target mass cancels out physically in acceleration, but Godot/Jolt expects a force, so you multiply by the rigid body’s mass before applying it.

Store `μ` directly on each celestial source. It avoids repeated `G * M` multiplication, makes save data cleaner, and lets you use real-world gravitational parameters without caring whether the displayed mass is rounded. If you do use `G`, the CODATA/NIST value commonly used is `6.67430e-11 m^3 kg^-1 s^-2`. ([NIST][2])

---

## Why the force should be applied from `_integrate_forces`

A central Autoload can loop through bodies in `_physics_process()` and call `body.apply_central_force(...)`. That works and is simple. However, the cleaner high-precision pattern is this:

```text
GravityRigidBody3D._integrate_forces(state)
    → SolarSystemPhysics.apply_gravity_to_state(self, state)
```

The gravity logic is still centralized in the Autoload, but the force application happens inside the body’s physics integration callback. Godot documents `_integrate_forces(state)` as the place where you can safely read and modify a rigid body’s direct physics state, and `custom_integrator` can be used when you want to replace Godot’s normal force integration for that body. ([Godot Engine documentation][3])

Use `apply_central_force()` for ordinary gravity because it applies a directional force at the center of mass and does not create torque. Use `apply_force(force, offset)` only when you intentionally want off-center force or tidal torque. Godot’s force methods are meant to be applied every physics update; impulses are time-independent and should not be applied every frame as a substitute for force. ([Godot Engine documentation][3])

---

# Implementation

## `CelestialBody3D.gd`

This is a gravity source. It may be attached to a visual planet node, an `AnimatableBody3D` planet collider, or a plain `Node3D`.

```gdscript
class_name CelestialBody3D
extends Node3D

@export var enabled: bool = true

# μ = G * M, in world_units^3 / s^2.
# If 1 Godot unit = 1 meter, Earth is about 3.986004418e14.
@export var gravitational_parameter: float = 0.0

# Physical radius in world units.
@export var radius: float = 1.0

# Optional numerical softening. Keep this 0 for most planet-scale gameplay.
# Use only to avoid singularities for point-like sources.
@export var softening_length: float = 0.0

# If true, gravity inside the radius behaves like a uniform-density sphere:
# a ∝ r instead of becoming singular.
@export var use_uniform_sphere_inside: bool = false

# Inertial velocity of this celestial body.
# Important when spawning rigid bodies near or on this body.
@export var linear_velocity: Vector3 = Vector3.ZERO

# Angular velocity in radians per second, in world coordinates.
# Useful for rotating planets and atmosphere-relative velocity.
@export var angular_velocity: Vector3 = Vector3.ZERO


func _enter_tree() -> void:
    SolarSystemPhysics.register_source(self)


func _exit_tree() -> void:
    SolarSystemPhysics.unregister_source(self)


func acceleration_at(world_position: Vector3) -> Vector3:
    if not enabled or gravitational_parameter == 0.0:
        return Vector3.ZERO

    var r: Vector3 = global_position - world_position
    var r2: float = r.length_squared()

    if r2 <= 0.0:
        return Vector3.ZERO

    if use_uniform_sphere_inside and radius > 0.0 and r2 < radius * radius:
        # Inside a uniform sphere:
        # a = μ * r / R^3
        return r * (gravitational_parameter / (radius * radius * radius))

    var e2: float = softening_length * softening_length
    var softened_r2: float = r2 + e2
    var softened_r: float = sqrt(softened_r2)

    # μ * r / |r|^3
    return r * (gravitational_parameter / (softened_r2 * softened_r))


func surface_velocity_at(world_position: Vector3) -> Vector3:
    var r: Vector3 = world_position - global_position
    return linear_velocity + angular_velocity.cross(r)
```

For a real planet surface, I would usually keep `softening_length = 0`. Collision prevents ordinary bodies from entering the planet. Softening is more useful for point-like stars, asteroids, or simplified sources where an object might pass through the mathematical center.

---

## `GravityRigidBody3D.gd`

This is the rigid body adapter. It stays a real `RigidBody3D`, so Jolt handles collision response, stacking, bouncing, friction, impulses, constraints, and contact resolution.

```gdscript
class_name GravityRigidBody3D
extends RigidBody3D

enum GravityMode {
    FORCE,             # Recommended default.
    CUSTOM_VELOCITY    # For more controlled orbital bodies.
}

enum SleepPolicy {
    NORMAL,
    ALWAYS_AWAKE,
    SKIP_WHILE_SLEEPING
}

@export var affected_by_celestial_gravity: bool = true
@export var gravity_mode: GravityMode = GravityMode.FORCE
@export var sleep_policy: SleepPolicy = SleepPolicy.NORMAL

# Optional: for debug/UI/orbit prediction.
var current_primary: CelestialBody3D = null


func _enter_tree() -> void:
    SolarSystemPhysics.register_body(self)


func _exit_tree() -> void:
    SolarSystemPhysics.unregister_body(self)


func _ready() -> void:
    # Disable Godot's default project gravity for this body.
    # The solar-system manager owns gravity now.
    gravity_scale = 0.0

    # In FORCE mode, let Godot/Jolt do normal force integration.
    # In CUSTOM_VELOCITY mode, we manually add gravity acceleration to velocity.
    custom_integrator = gravity_mode == GravityMode.CUSTOM_VELOCITY

    if sleep_policy == SleepPolicy.ALWAYS_AWAKE:
        can_sleep = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    if not affected_by_celestial_gravity:
        return

    if sleep_policy == SleepPolicy.SKIP_WHILE_SLEEPING and state.sleeping:
        return

    match gravity_mode:
        GravityMode.FORCE:
            SolarSystemPhysics.apply_gravity_force_to_state(self, state)

        GravityMode.CUSTOM_VELOCITY:
            SolarSystemPhysics.custom_integrate_gravity_velocity(self, state)
```

Set `gravity_scale = 0` because `RigidBody3D.gravity_scale` multiplies Godot’s default project gravity; otherwise you would get both the global down gravity and your solar-system gravity. Sleeping also matters: a sleeping `RigidBody3D` does not move or calculate forces until woken by collision or force/impulse application, so you should choose an explicit sleep policy for orbital bodies versus surface props. ([Godot Engine documentation][3])

---

## `SolarSystemPhysics.gd`

Add this as an Autoload named `SolarSystemPhysics`.

```gdscript
extends Node

const G: float = 6.67430e-11

var _sources: Array[CelestialBody3D] = []
var _bodies: Array[GravityRigidBody3D] = []


func register_source(source: CelestialBody3D) -> void:
    if source != null and not _sources.has(source):
        _sources.append(source)


func unregister_source(source: CelestialBody3D) -> void:
    _sources.erase(source)


func register_body(body: GravityRigidBody3D) -> void:
    if body != null and not _bodies.has(body):
        _bodies.append(body)


func unregister_body(body: GravityRigidBody3D) -> void:
    _bodies.erase(body)


func gravity_acceleration_at(world_position: Vector3) -> Vector3:
    # Kahan-style compensated summation helps when combining very large and small
    # accelerations, e.g. Sun + planet + moon.
    var sum: Vector3 = Vector3.ZERO
    var compensation: Vector3 = Vector3.ZERO

    for source in _sources:
        if not is_instance_valid(source):
            continue

        var contribution: Vector3 = source.acceleration_at(world_position)

        var y: Vector3 = contribution - compensation
        var t: Vector3 = sum + y
        compensation = (t - sum) - y
        sum = t

    return sum


func strongest_source_at(world_position: Vector3) -> CelestialBody3D:
    var best: CelestialBody3D = null
    var best_a2: float = 0.0

    for source in _sources:
        if not is_instance_valid(source):
            continue

        var a: Vector3 = source.acceleration_at(world_position)
        var a2: float = a.length_squared()

        if best == null or a2 > best_a2:
            best = source
            best_a2 = a2

    return best


func local_down_at(world_position: Vector3) -> Vector3:
    var a: Vector3 = gravity_acceleration_at(world_position)
    if a.length_squared() == 0.0:
        return Vector3.DOWN
    return a.normalized()


func apply_gravity_force_to_state(
    body: GravityRigidBody3D,
    state: PhysicsDirectBodyState3D
) -> void:
    var inverse_mass: float = state.inverse_mass
    if inverse_mass <= 0.0:
        return

    var mass: float = 1.0 / inverse_mass
    var position: Vector3 = state.transform.origin
    var acceleration: Vector3 = gravity_acceleration_at(position)

    body.current_primary = strongest_source_at(position)

    if acceleration.length_squared() == 0.0:
        return

    # Force = mass * acceleration.
    # Let Godot/Jolt integrate the body and handle collisions.
    state.apply_central_force(acceleration * mass)


func custom_integrate_gravity_velocity(
    body: GravityRigidBody3D,
    state: PhysicsDirectBodyState3D
) -> void:
    var position: Vector3 = state.transform.origin
    var acceleration: Vector3 = gravity_acceleration_at(position)

    body.current_primary = strongest_source_at(position)

    # Semi-implicit Euler style:
    # v(t + dt) = v(t) + a(x) * dt
    #
    # This is acceptable for many gameplay orbital bodies, but for long-term
    # celestial mechanics use a dedicated symplectic solver for the major bodies.
    state.linear_velocity += acceleration * state.step
```

This gives you a compact, central gravity system while still respecting Godot’s physics lifecycle.

---

# Strict Autoload-only variant

If you want the Autoload to literally apply forces to every registered body from its own `_physics_process`, you can do this:

```gdscript
func _physics_process(_delta: float) -> void:
    for body in _bodies:
        if not is_instance_valid(body):
            continue

        if not body.affected_by_celestial_gravity:
            continue

        if body.gravity_mode != GravityRigidBody3D.GravityMode.FORCE:
            continue

        if body.sleep_policy == GravityRigidBody3D.SleepPolicy.SKIP_WHILE_SLEEPING and body.sleeping:
            continue

        var acceleration: Vector3 = gravity_acceleration_at(body.global_position)

        if acceleration.length_squared() == 0.0:
            continue

        body.apply_central_force(acceleration * body.mass)
```

This is simpler, and it uses Godot’s force API correctly. But for precise state access, the `_integrate_forces` adapter is better because it works with the body’s direct physics state rather than relying on scene-node properties. Godot warns against frequently setting `RigidBody3D` transforms or velocities directly, and recommends `_integrate_forces()` for precise control. ([Godot Engine documentation][3])

---

# Celestial body motion

You have three good options.

## Option A: On-rails ephemeris

This is the best default.

```text
Sun, planets, moons → scripted/ephemeris positions
Rigid bodies        → real Jolt bodies affected by those sources
```

Your planet node exposes:

```gdscript
linear_velocity
angular_velocity
gravitational_parameter
radius
```

Then the manager uses its current transform and velocity.

This is deterministic, stable, easy to save, and avoids asking a rigid-body contact solver to handle planet-scale n-body dynamics.

## Option B: Custom n-body integrator for celestial bodies

If you want planets to pull each other, do not make them normal `RigidBody3D` objects. Keep an internal celestial state array:

```text
position[i]
velocity[i]
mass[i]
mu[i]
node[i]
```

Update them with a symplectic integrator such as velocity Verlet:

```text
a0 = gravity_accelerations(positions)

for each body:
    velocity += 0.5 * a0 * dt
    position += velocity * dt

a1 = gravity_accelerations(new_positions)

for each body:
    velocity += 0.5 * a1 * dt
```

Then write the resulting positions back to the `CelestialBody3D` nodes during the physics tick.

Use this for stars, planets, moons, and large asteroids. Do not include every crate and bullet in this solver.

## Option C: Hybrid

Use on-rails planets, but dynamically integrate asteroids, comets, or spacecraft with custom orbital code.

This is usually the most game-friendly option.

---

# Planet surfaces and rigid bodies “on” celestial bodies

A body sitting on a planet is still in the inertial solar-system world. That has consequences.

## Spawn with the planet’s inertial velocity

When you spawn a ship, crate, or player on a planet, do this:

```gdscript
func place_body_on_planet(
    body: GravityRigidBody3D,
    planet: CelestialBody3D,
    local_surface_position: Vector3,
    local_relative_velocity: Vector3 = Vector3.ZERO
) -> void:
    var world_position: Vector3 = planet.global_transform * local_surface_position

    body.global_position = world_position

    # Give the body the planet's orbital velocity plus rotational surface velocity.
    body.linear_velocity = planet.surface_velocity_at(world_position) + local_relative_velocity
```

If you forget this, an object spawned on Earth will not share Earth’s orbital or rotational motion. It may appear to fall, skid, or collide violently because the planet and object have inconsistent inertial velocities.

## Moving planet colliders

For a moving or rotating planet surface, use moving/animatable collision rather than ordinary dynamic rigid bodies. `AnimatableBody3D` is intended for bodies that cannot be moved by external forces but can be moved manually; when moved, Godot estimates velocity and uses it to affect other physics bodies, which is exactly the behavior you want for moving terrain, rotating stations, or planet surface chunks. ([Godot Engine documentation][4])

Avoid parenting dynamic `RigidBody3D` objects under a moving planet node. Godot warns that frequently changing a `RigidBody3D` transform, or making it a descendant of a constantly moving node, can cause unpredictable behavior. Keep dynamic rigid bodies in an inertial world branch, and use helper functions to convert between planet-local and world coordinates. ([Godot Engine documentation][3])

---

# Gravity model choices

## Full superposition

For every affected body:

```text
a_total = a_sun + a_planet + a_moon + ...
```

This is the physically cleanest approach.

Use the strongest source only for:

```text
local down
UI
camera alignment
orbit prediction frame
sphere-of-influence display
terrain streaming
```

Do not use sphere-of-influence switching as your actual physics unless you smooth transitions. Hard-switching gravity from Earth to Sun, for example, creates discontinuities.

## Dominant-source approximation

For many surface props, you may use only the dominant planet’s gravity:

```text
a ≈ μ_planet * r / |r|^3
```

This is good for crates, vehicles, characters, and debris on a planet.

However, for spacecraft, satellites, long-range projectiles, orbital mechanics, or anything leaving a planet, use full superposition.

## Tidal torque and gravity gradients

For small objects, central gravity is enough.

For very large objects, long ships, tethers, stations, or rubble piles, gravity varies across the body. Then sample multiple points and apply forces at offsets:

```gdscript
func apply_sampled_gravity(
    state: PhysicsDirectBodyState3D,
    body_mass: float,
    local_points: Array[Vector3],
    mass_fractions: Array[float]
) -> void:
    for i in local_points.size():
        var local_point: Vector3 = local_points[i]
        var world_point: Vector3 = state.transform * local_point

        var acceleration: Vector3 = gravity_acceleration_at(world_point)
        var force: Vector3 = acceleration * body_mass * mass_fractions[i]

        # Godot expects the position as an offset from the body origin
        # in global coordinates.
        var global_offset: Vector3 = world_point - state.transform.origin

        state.apply_force(force, global_offset)
```

Use this sparingly. It is more expensive, and most gameplay objects do not need it.

---

# Time step and time warp

Godot physics runs at a fixed physics tick rate, defaulting to 60 physics iterations per second. You can increase the physics tick rate for more responsive or more stable physics, but it costs CPU. ([Godot Engine documentation][5])

For real-time gameplay:

```text
Engine time scale = 1
normal force mode
normal collision
normal Jolt solving
```

For moderate time acceleration:

```text
increase Engine.time_scale carefully
increase physics_ticks_per_second if needed
keep active collision complexity low
```

Godot’s `Engine.time_scale` affects simulations that use delta time, but it does not automatically increase the physics tick rate; Godot’s docs explicitly warn that high `time_scale` values stretch each physics tick over a larger period of engine time and reduce physics precision unless you also raise the physics tick rate. ([Godot Engine documentation][6])

For high time warp:

```text
disable active rigid-body collision
freeze or pack landed props
put spacecraft into orbital propagation mode
integrate orbits with substeps
restore Jolt rigid bodies when returning to real time
```

Do not try to run a fully colliding solar-system rigid-body scene at `1000x` time scale. Time warp should become an orbital simulation mode, not just “bigger delta”.

---

# Performance model

For a solar system with a few dozen major sources, direct summation is fine:

```text
cost = affected_body_count * source_count
```

Example:

```text
5,000 rigid bodies * 20 sources = 100,000 gravity evaluations per physics tick
```

That is usually manageable if your code avoids allocations and node lookups.

Optimizations, in order:

1. Cache source positions and `μ` values once per physics tick.
2. Use full superposition only for active/orbital objects.
3. Use dominant-source gravity for sleeping or surface-local props.
4. Skip sleeping props if their sleep policy allows it.
5. Use acceleration thresholds, not distance thresholds.
6. For many gravitational sources, use spatial partitioning or Barnes-Hut.
7. For very large body counts, apply forces through `PhysicsServer3D` RIDs instead of high-level node calls.

Godot’s server APIs are lower-level APIs that can bypass some scene-system overhead, and `PhysicsServer3D` exposes body force methods such as `body_apply_central_force`. ([Godot Engine documentation][7])

---

# Collision and scale rules

Even with double precision and solved GPU precision, collision has its own practical constraints.

Use real units if you can:

```text
1 Godot unit = 1 meter
mass = kilograms
time = seconds
force = newtons
μ = m^3 / s^2
```

But do not non-uniformly scale physics bodies. Godot warns that non-uniform scale on `PhysicsBody3D` is likely to behave unexpectedly; adjust collision shapes instead. ([Godot Engine documentation][8])

For high-speed objects:

```text
enable continuous collision detection
increase physics tick rate
use simpler collision shapes
avoid extremely thin collision geometry
```

Godot documents continuous collision detection as more precise for fast small bodies, though more expensive. ([Godot Engine documentation][3])

---

# Recommended body modes

## Surface prop

```text
gravity_mode = FORCE
sleep_policy = SKIP_WHILE_SLEEPING or NORMAL
can_sleep = true
gravity_scale = 0
```

Use for rocks, crates, barrels, debris, loose objects.

## Vehicle or player-controlled rigid body

```text
gravity_mode = FORCE
sleep_policy = ALWAYS_AWAKE while controlled
gravity_scale = 0
```

Use local gravity vector for control orientation:

```gdscript
var down: Vector3 = SolarSystemPhysics.local_down_at(global_position)
var up: Vector3 = -down
```

## Spacecraft

```text
gravity_mode = FORCE for real-time collision flight
gravity_mode = CUSTOM_VELOCITY or orbital propagator for long coasts
sleep_policy = ALWAYS_AWAKE
gravity_scale = 0
continuous_cd = true if fast and colliding
```

## Planet

```text
CelestialBody3D source
AnimatableBody3D or streamed terrain collision
not an ordinary dynamic RigidBody3D
```

## Star

```text
CelestialBody3D source
usually no collision except damage/heat trigger volumes
```

---

# Orbit spawning example

Circular orbit around a planet:

```gdscript
func put_in_circular_orbit(
    body: GravityRigidBody3D,
    planet: CelestialBody3D,
    altitude: float,
    radial_direction: Vector3,
    prograde_direction: Vector3
) -> void:
    var r_hat: Vector3 = radial_direction.normalized()
    var t_hat: Vector3 = prograde_direction.normalized()

    var orbital_radius: float = planet.radius + altitude
    var world_position: Vector3 = planet.global_position + r_hat * orbital_radius

    var circular_speed: float = sqrt(planet.gravitational_parameter / orbital_radius)

    body.global_position = world_position
    body.linear_velocity = planet.linear_velocity + t_hat * circular_speed
```

Escape speed:

```gdscript
var escape_speed := sqrt(2.0 * planet.gravitational_parameter / orbital_radius)
```

Surface gravity:

```gdscript
var g_surface := planet.gravitational_parameter / (planet.radius * planet.radius)
```

---

# Debug tools you should build early

Add these to `SolarSystemPhysics` or a debug overlay:

```text
draw gravity vector at selected body
draw strongest source line
show acceleration contribution by source
show local down/up
show current primary body
show orbital speed, escape speed, apoapsis/periapsis estimate
show body velocity relative to current primary
show sleeping/awake state
show whether force mode or custom integrator is active
```

Minimum tests:

```text
Earth surface gravity test:
    a ≈ μ_earth / r_earth^2

Circular orbit test:
    v = sqrt(μ / r)
    body should remain near constant altitude

Escape test:
    v = sqrt(2μ / r)
    body should not return in a two-body setup

Superposition test:
    acceleration from Earth + Moon + Sun equals vector sum

Sleep test:
    surface props sleep correctly
    spacecraft never sleeps unexpectedly

Spawn test:
    object spawned on a moving planet receives planet linear velocity
```

---

# Common traps

## Trap 1: Applying impulses every frame

Do not use `apply_impulse()` for gravity. Gravity is continuous force. Use `apply_central_force()` or `state.apply_central_force()` every physics tick. Godot explicitly distinguishes forces, which are time-dependent and intended for physics updates, from impulses, which are time-independent. ([Godot Engine documentation][3])

## Trap 2: Leaving default gravity enabled

If you do not set `gravity_scale = 0`, your body receives both Godot’s default world gravity and solar-system gravity.

## Trap 3: Parenting rigid bodies to moving planets

A dynamic rigid body should not inherit transform motion from a moving planet node. Keep it in inertial world space and convert coordinates when needed.

## Trap 4: Hard-switching gravity by sphere of influence

Use SOI for UI and culling. For actual physics, prefer full superposition or a smoothed transition.

## Trap 5: Forgetting inherited velocity

Anything created on a moving planet must inherit:

```text
planet orbital velocity
+ planet rotational surface velocity
+ local relative velocity
```

## Trap 6: Simulating major bodies as normal rigid bodies

Planets should be gravity sources and animatable/static collision, or part of a separate celestial integrator. They should not be ordinary dynamic `RigidBody3D` objects in the same category as crates and ships.

---

## Final recommended design

Use this as your default:

```text
SolarSystemPhysics autoload
    central registry
    source cache
    gravity_acceleration_at()
    local_down_at()
    strongest_source_at()
    orbit helpers
    optional celestial n-body/on-rails update

CelestialBody3D
    Node3D/AnimatableBody3D source
    μ, radius, velocity, angular velocity
    acceleration_at(position)

GravityRigidBody3D
    RigidBody3D subclass
    gravity_scale = 0
    _integrate_forces(state)
        SolarSystemPhysics.apply_gravity_force_to_state(self, state)
```

That gives you one centralized solar-system physics brain, while still letting Godot/Jolt do what it is good at: integrating rigid bodies, resolving contacts, handling impulses, constraints, friction, sleeping, and continuous collision.

[1]: https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html "Singletons (Autoload) — Godot Engine (stable) documentation in English"
[2]: https://physics.nist.gov/cgi-bin/cuu/Value?bg=&utm_source=chatgpt.com "CODATA Value: Newtonian constant of gravitation"
[3]: https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html "RigidBody3D — Godot Engine (stable) documentation in English"
[4]: https://docs.godotengine.org/en/stable/classes/class_animatablebody3d.html?utm_source=chatgpt.com "AnimatableBody3D - Godot Docs"
[5]: https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html "Physics introduction — Godot Engine (stable) documentation in English"
[6]: https://docs.godotengine.org/en/4.4/classes/class_engine.html "Engine — Godot Engine (4.4) documentation in English"
[7]: https://docs.godotengine.org/en/4.6/tutorials/performance/using_servers.html "Optimization using Servers — Godot Engine (4.6) documentation in English"
[8]: https://docs.godotengine.org/en/stable/classes/class_physicsbody3d.html "PhysicsBody3D — Godot Engine (stable) documentation in English"
