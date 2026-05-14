# Orbit Trajectory Prediction and Visualization

## Context

The project has Keplerian gravity (CelestialBodySystem sums N-body acceleration), vessels flying in a gravity field, and a debug VectorMesh visualizer — but no way for the player to see where their orbit goes. This plan adds a Keplerian orbit predictor that computes the two-body conic from the vessel's current state and draws it as a line mesh, plus HUD readouts for orbital parameters.

## Approach: Direct State-Vector-to-Orbit-Plane

No classical Ω/i/ω computation needed for visualization. The orbital plane is derived directly from the state vector:

1. `h = r × v` (specific angular momentum → orbit normal)
2. `e_vec = ((v² − μ/|r|) · r − (r·v) · v) / μ` (eccentricity vector → periapsis direction)
3. `e = |e_vec|`, `p = |h|²/μ`, `a = p/(1−e²)`
4. Orbital plane basis: `P̂ = ê_vec/e`, `Ŵ = ĥ`, `Q̂ = Ŵ × P̂`
5. Points: `r(θ) = p/(1 + e·cos θ)`, `pos = center + r(θ)·(cos θ · P̂ + sin θ · Q̂)`

## Work Units (3 independent, parallel)

Three units is appropriate for this feature's scope (~4 new files, ~2 modified files). Each unit is independently mergeable and contains its own orbital math. Duplication is intentional — a cleanup pass can consolidate after all three land.

---

### Unit 1: Orbital Math Resource + Unit Tests

**New files:**
- `scene/system/orbital-elements.gd` — `class_name OrbitalElements extends RefCounted`
- `test/unit/orbital-elements-test.gd` — GdUnit4 test suite

**OrbitalElements class:**
- `static func from_state_vector(r: Vector3, v: Vector3, mu: float) -> OrbitalElements`
- Stored properties: `h_vec`, `e_vec`, `eccentricity`, `semi_latus_rectum`, `semi_major_axis`, `periapsis`, `apoapsis`, `orbital_period`, `p_hat`, `q_hat`, `w_hat`
- `func get_orbit_point(true_anomaly: float) -> Vector3` — position relative to focus
- `func is_closed() -> bool` — eccentricity < 1.0
- Circular fallback: when `e < 1e-8`, use `r.normalized()` as `p_hat`
- Radial guard: when `|h| < epsilon`, return degenerate elements

**Tests:** Circular orbit, elliptical orbit, hyperbolic orbit, near-radial, orbit point consistency, Earth-ISS reference values.

---

### Unit 2: Orbit Trajectory Visualization + Vessel Integration

**New files:**
- `scene/system/orbit-trajectory-3d.gd` — `class_name OrbitTrajectory3D extends MeshInstance3D`
- `scene/system/orbit-trajectory.tscn` — scene with ImmediateMesh + StandardMaterial3D (`no_depth_test=true`)

**Modified files:**
- `scene/craft/lamae.tscn` — add OrbitTrajectory as child of Lamae with `body = NodePath("..")`

**OrbitTrajectory3D node:**
- Follows VectorMesh pattern: ImmediateMesh, PRIMITIVE_LINE_STRIP, redrawn each `_process()`
- `@export var body: GravityRigidBody3D` — vessel to track
- `@export var segment_count: int = 128`
- Inline orbital math (same as unit 1, self-contained)
- Positions itself at `body.current_primary.global_position` each frame
- Ellipse: sweep θ from −π to π; Hyperbola: clip to `±(acos(−1/e) − 0.01)`
- Guards: skip drawing when `body == null`, `current_primary == null`, or `|h| < epsilon`

---

### Unit 3: HUD Orbital Parameters

**Modified files:**
- `scene/command/vessel-command-receiver.gd` — add orbital params to `_update_info()`
- `scene/ui/ui.gd` — add formatting for new keys

**New HUD keys:**
- `eccentricity` — formatted as `"%.4f"`
- `periapsis` — altitude above surface (meters), formatted as `"%.1f m"` or `"N/A"` for escape
- `apoapsis` — altitude above surface (meters), formatted as `"%.1f m"` or `"N/A"` for escape

Inline orbital math in `_update_info()`, inside existing `if vessel.current_primary != null:` block.

---

## E2E Test Recipe

1. **Headless scene load** — verifies all scripts/scenes parse: `godot --headless --path . --quit`
2. **GdUnit4 tests** — verifies orbital math + HUD integration: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit`
3. **Skip visual e2e** — no browser/UI automation available for Godot. Workers should note that visual verification (orbit line appears, changes with thrust) requires manual play testing.

## Worker Instructions Template

```
After you finish implementing the change:
1. **Simplify** — Invoke the `Skill` tool with `skill: "simplify"` to review and clean up your changes.
2. **Run unit tests** — Run the project's test suite (check for package.json scripts, Makefile targets, or common commands like `npm test`, `bun test`, `pytest`, `go test`). If tests fail, fix them.
3. **Test end-to-end** — Follow the e2e test recipe from the coordinator's prompt (below). If the recipe says to skip e2e for this unit, skip it.
4. **Commit and push** — Commit all changes with a clear message, push the branch, and create a PR with `gh pr create`. Use a descriptive title. If `gh` is not available or the push fails, note it in your final message.
5. **Report** — End with a single line: `PR: <url>` so the coordinator can track it. If no PR was created, end with `PR: none — <reason>`.
```

## Codebase Conventions (for workers)

- File names: kebab-case (`orbital-elements.gd`)
- Class names: PascalCase (`OrbitalElements`)
- Explicit `class_name` at file top
- Chapter-style doc comments at file top explaining "why this exists"
- `@export_custom(PROPERTY_HINT_NONE, "suffix: unit")` for physics quantities
- Typed parameters/returns: `func method(p: Type) -> ReturnType`
- Tests: GdUnit4, extend `GdUnitTestSuite`, `auto_free()`, `assert_float().is_equal_approx(expected, tolerance)`
- Commit prefix: `feat:`, `fix:`, `chore:`, `ui:`
- Search: use `rg` not `grep`, `fd` not `find`
- Godot binary: `/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64`
- Test command: `<godot-binary> --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit`
