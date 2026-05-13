---
name: godot
description: Godot project development workflow for this repository. Use when Codex needs to edit, inspect, run, validate, test, export, or debug Godot scenes, GDScript, resources, project.godot settings, or command-line Godot tasks in this project.
---

# Godot Best Practices Skill

Use this skill when creating, editing, reviewing, or refactoring Godot projects. It is based on the Godot Engine stable documentation, especially the “Best practices” manual section for Godot 4.6.

Primary source: https://docs.godotengine.org/en/stable/tutorials/best_practices/index.html

## Engine Binary

Use this Godot executable for this project:

```bash
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64
```

Prefer the absolute path above over `godot` from `PATH`, Homebrew Godot, or any other editor binary. Before using it in a new environment, check that it exists and is executable:

```bash
test -x /Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64
```

If that check fails, report the missing binary and ask before substituting another Godot executable.

## Workflow

Start from the project root, the directory containing `project.godot`.

When changing scenes, resources, or scripts:

- Inspect `project.godot`, relevant `.tscn` files, and attached `.gd` scripts before editing.
- Preserve Godot resource IDs, node paths, exported property names, and signal method names unless the task explicitly requires changing them.
- Prefer repo-local patterns for autoloads, scene ownership, typed GDScript, and command/test scripts.
- Use the editor binary in headless mode for validation whenever the change can be checked without opening the GUI.

Use this smoke check after meaningful Godot edits:

```bash
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --headless --path . --quit
```

For project scripts, use `-s` with a `res://` script path from the project root:

```bash
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --headless --path . -s res://path/to/script.gd
```

If a task requires opening the editor UI, request approval before launching the GUI app.

## GdUnit4 Tests

Use GdUnit4 as the first automated validation tier when touched logic can be tested without bespoke rendering, input, or scene-runtime setup. Tests live under `res://test/unit`.

If `addons/gdUnit4` is missing, install the pinned addon before running tests:

```bash
python3 tools/bootstrap_gdunit4.py
```

Run the project unit tests with:

```bash
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit
```

Include `--ignoreHeadlessMode` and `-a res://test/unit`; without them the command may only print GdUnit help. Run this command after logic changes that have test coverage, and add or update focused GdUnit4 tests for deterministic script/resource behavior.

Use lightweight harness scenes under `scene/test/` only when the behavior is difficult to validate through GdUnit4, such as camera setup, rendering, input, or complex scene interactions.

## Reporting

In final responses, include the exact Godot command run and summarize any load, parse, or test failures. If validation is skipped, state why.

## Core operating principles

- Treat Godot projects as scene- and node-composition projects, not as ordinary application codebases.
- Prefer small, focused, reusable scenes and scripts with clear ownership.
- Preserve the user’s existing project structure unless there is a clear reason to change it.
- Avoid large architectural rewrites unless requested; propose incremental, testable changes.
- When changing code, keep behavior local, explicit, and easy to debug in the editor.
- Favor code and scene organization that works well with designers and non-programmers using the Godot editor.
- Assume Godot 4.x conventions unless project files indicate otherwise. Check `project.godot`, script syntax, and API names before editing.
- Be careful with advice for Godot 3.x projects: version-control ignore rules and many APIs differ from Godot 4.x.

## Before editing a Godot project

1. Inspect `project.godot` to identify the Godot version and project settings.
2. Identify the relevant scene files (`.tscn`, `.scn`) and scripts (`.gd`, `.cs`, GDExtension files) before making changes.
3. Determine whether the requested behavior belongs in:
   - a self-contained scene,
   - a script class or custom node type,
   - a resource,
   - an autoload,
   - or a lightweight data object.
4. Prefer editing the smallest responsible unit.
5. Preserve exported variables, signal connections, node names, groups, input action names, and resource paths unless intentionally changing them.
6. After changes, recommend or run appropriate checks when available, for example:
   - opening the project in the Godot editor,
   - running the main scene,
   - running headless tests if the project has them,
   - checking the debugger output for missing node paths, signal errors, and resource load failures.

## Scene architecture

### Think of scenes as reusable objects

Godot scenes are reusable, instantiable, and inheritable groups of nodes. A scene often behaves like a class: it defines available nodes, their organization, their initial values, and signal connections. Apply object-oriented principles to scenes as well as scripts:

- single responsibility,
- encapsulation,
- loose coupling,
- SOLID where practical,
- DRY, KISS, and YAGNI.

### Make scenes self-contained

Prefer scenes that can instantiate and run without knowing details about their parent, siblings, or external environment.

Do:

- Keep required nodes, resources, and state inside the scene when possible.
- Let the parent or owning context wire dependencies into child scenes.
- Use exported properties, injected references, callables, or signals for explicit integration points.
- Add `_get_configuration_warnings()` in `@tool` scripts when a scene needs editor-time setup.

Avoid:

- Hard-coded references from a reusable child scene to a specific parent or sibling path.
- Sibling-to-sibling dependencies. Let a common ancestor mediate communication.
- Hidden assumptions that require external documentation to use a scene safely.

### Dependency direction

Parents and owning systems should know about their children more often than children know about parents. A child scene should expose an API; the parent decides how to connect it.

Recommended dependency patterns:

- Use signals for events that have already happened or for child-to-parent notification.
- Use direct method calls, injected `Callable`s, or explicit references when the parent wants to start behavior.
- Use exported `Node`, `NodePath`, `Resource`, or `PackedScene` properties for configurable dependencies.
- Validate injected dependencies before use.

Signal convention:

- Name signals as past-tense events when they represent completed events, such as `item_collected`, `entered`, or `skill_activated`.

## Choosing scenes versus scripts

Use scenes for game-specific concepts and compositions. Use scripts for reusable tools, abstract behavior, resources, and editor-facing custom types.

Prefer a scene when:

- The object has multiple nodes or editor-authored composition.
- It represents a concept specific to the game, such as a player, enemy, pickup, weapon, door, level chunk, or UI panel.
- Designers should be able to inspect, rearrange, animate, or connect parts in the editor.
- Instantiation performance matters for a complex node hierarchy.

Prefer a script when:

- The object is a reusable tool or simple custom type.
- It should appear as a named type in the node/resource creation dialog.
- It is plugin or editor tooling code.
- It is primarily behavior without meaningful node composition.
- It is a data object, helper, or namespace-like container.

Use `class_name` in GDScript when a script should be globally accessible as a named type. For scene namespacing, a `RefCounted` script class may expose a `const` `PackedScene`, for example `Game.MyScene.instantiate()`.

Performance guideline:

- Large node hierarchies are usually faster and clearer as `PackedScene`s than as script code that manually creates and configures many nodes.
- Script-created trees may be appropriate for tools or generated structures, but avoid using imperative node construction as the default for ordinary scene composition.

## Autoloads and global state

Autoloads are automatically loaded nodes at `/root`, accessible globally. They are useful but should not become default “manager” classes for everything.

Avoid autoloads when:

- A scene can own the state or behavior locally.
- The autoload would control or mutate many unrelated objects’ data.
- The only reason is convenience of access.
- Bugs would become hard to trace because any script can call the global object.
- The autoload would allocate global pools or resources that only some scenes need.

Prefer alternatives:

- Local child nodes owned by the scene, for example each scene owning its own `AudioStreamPlayer`s.
- Custom `Resource` types for shared data.
- `class_name` scripts with `static func` or `static var` for stateless helpers or shared class-level data.
- Access through the scene root or `owner` when the data belongs to a particular scene.
- Dependency injection from a parent or high-level context.

Use an autoload when:

- The system has genuinely broad scope across the project.
- It owns and manages its own data without invading the internal state of other objects.
- It represents a durable global service such as a quest system, dialogue system, save coordinator, scene transition service, analytics adapter, or project-wide settings service.
- Global availability is more valuable than the coupling cost.

Remember that an autoload is not inherently a true singleton: it is a node loaded automatically under the root. Other instances can still be created unless the code prevents it.

## Avoid using nodes for everything

Nodes are convenient, but not every data structure or API should be a node. Excessive node counts and complex node behavior can hurt performance and maintainability.

Use lighter alternatives when the object does not need scene-tree behavior:

- `Object`: minimal but manually managed; useful for specialized low-level structures when lifetime is controlled.
- `RefCounted`: good default for custom data classes that should be freed automatically when no references remain.
- `Resource`: use for serializable, inspector-friendly data that can be saved, loaded, exported, duplicated, and reused.

Prefer `Resource` for:

- item definitions,
- ability definitions,
- enemy stats,
- configuration data,
- dialogue data,
- gameplay tuning data,
- reusable data shared by scenes.

Prefer custom `RefCounted` or `Object` classes for:

- pure runtime data structures,
- graphs, trees, heaps, lists, state containers,
- APIs used by nodes but not themselves part of the rendered or logical scene tree.

## Object references and interfaces

### Acquiring references

Reference nodes and resources intentionally. Avoid repeated dynamic lookups in performance-sensitive code.

Preferred order for node references:

1. Export a typed node reference when the dependency is editor-configurable and should not break when the node moves.
2. Cache a node reference in `_ready()` using `@onready var child: Node = $Child` when the dependency is internal and stable.
3. Use `$Child` for concise cached-path access in GDScript.
4. Use `get_node()` for dynamic paths or one-off lookups.
5. Avoid repeated `get_node("Some/Long/Path")` calls inside `_process()`, `_physics_process()`, loops, or hot paths.

When injecting references from outside:

- Document or enforce the requirement in code.
- Validate with null checks, `has_method()`, type checks, group checks, or assertions as appropriate.
- Prefer editor-visible warnings for editor-configured requirements.
- Remember that `assert()` may not run in release export templates; do not rely on it for user-facing runtime validation.

### Resource loading and references

- Use `preload()` for static, known resources that should load with the script and benefit from editor completion.
- Use `load()` or `ResourceLoader.load()` when the path is dynamic or the resource should load later.
- Avoid preloading into exported properties that scene instantiation will overwrite.
- If a loaded `Resource` must be unique per owner, duplicate or instantiate it; loading returns a cached resource instance.
- For exported scene/script references, prefer empty or invalid defaults when the editor should supply the value.

### Duck typing and interfaces

Godot’s scripting API is duck-typed: an operation succeeds if the object supports the requested property or method.

Use safe access patterns:

- `has_method()` before dynamic method calls.
- `is SomeType` for multiple calls that require the same known type.
- `is_in_group()` when the project deliberately uses groups as interface labels.
- Names and groups can imply an interface, but they are project conventions; document or enforce them.
- In C#, prefer real language interfaces where practical, but remember editor assignment does not expose C# interfaces directly.

Avoid:

- Calling methods on arbitrary nodes without validation.
- Using broad group names without documenting expected methods/properties.
- Encoding complex interfaces only in comments when editor warnings or typed references would be clearer.

## Lifecycle and notifications

Godot exposes many engine callbacks as notifications. Use the most specific lifecycle method for the job.

### `_init()`

Use `_init()` for:

- SceneTree-independent initialization.
- Script-owned data setup.
- Script-only node subtree construction when intentionally building a node tree from code.

Remember initialization order for scene instances:

1. Property default values are assigned without calling setters.
2. `_init()` runs and assignments trigger setters.
3. Exported values from the Inspector are applied and setters run again.

Therefore:

- Avoid relying on exported Inspector values inside `_init()`.
- Do not assume a setter only runs once.
- Use `_ready()` for logic that needs final exported values and child nodes.

### `_enter_tree()` and `_ready()`

Use `_enter_tree()` for:

- Logic that must occur when the node enters the SceneTree.
- Registration with systems that require the node to be in the tree.

Use `_ready()` for:

- Logic that requires child nodes to be ready.
- Caching child node references.
- Connecting internal scene dependencies after children exist.

Lifecycle order:

- Nodes enter the tree top-down through `_enter_tree()`.
- `_ready()` runs bottom-up after children are ready.
- Standalone scene or script instances do not receive `_enter_tree()` or `_ready()` until added to the SceneTree.

Use `NOTIFICATION_PARENTED` and `NOTIFICATION_UNPARENTED` when behavior should respond to parenting changes even before or outside full SceneTree readiness, such as runtime-created data-centric nodes that connect to parent signals.

### `_process()`, `_physics_process()`, and input callbacks

Use `_process(delta)` for:

- frame-dependent recurring logic,
- visual interpolation,
- frequent non-physics updates,
- cached evaluations that must update as often as possible.

Use `_physics_process(delta)` for:

- frame-independent physics-tick logic,
- kinematic movement,
- transform operations that must update consistently over time.

Use `_input()`, `_unhandled_input()`, or related input callbacks for input handling:

- They trigger only when input events occur.
- Avoid polling input inside `_process()` or `_physics_process()` unless there is a clear reason.

Use `Timer` nodes or timer logic for recurring checks that do not need to run every frame.

## Data-structure choices

The Godot documentation marks its data-preferences page as work in progress for Godot 4.6; treat its guidance as useful but verify performance-sensitive claims in the actual project.

General rule:

- Choose data structures by access pattern, scale, and frequency.
- Avoid linear-time operations in large or per-frame workloads.
- Linear operations may be acceptable for small data or infrequent operations.

Use `Array` when:

- You need ordered data.
- You iterate frequently.
- You access by index.
- You append/remove mostly at the end.

Avoid `Array` when:

- You frequently insert/remove at the front or arbitrary positions in large arrays.
- You need fast lookup by semantic key.
- You frequently search for values in large arrays.

Use `Dictionary` when:

- You need fast key-based get/set/insert/erase.
- You map IDs, names, enum values, resources, or references to values.
- You do not need to search by value.

Avoid `Dictionary` when:

- Ordered index-based access is central.
- Memory overhead matters more than key lookup.
- You need frequent reverse lookup by value.

Use custom `Object`, `RefCounted`, or `Resource` data structures when:

- You need a stable API over internal data.
- You want signals or methods attached to data.
- You need specialized structures such as trees, graphs, heaps, or disjoint sets.
- `Array` or `Dictionary` would obscure the domain model.

### Enums

- Prefer integer enums for normal state machines, comparisons, and conventional enum behavior.
- Use string-style exported enum values only when usability, readability, or direct display outweighs performance concerns.
- If integer enum values need display names, map them through a dictionary or helper function.

### Animation-class selection

Use `AnimatedTexture` when:

- A simple looped texture animation is enough.
- You need many passive animated textures or tile animations with minimal logic.

Use `AnimatedSprite2D` with `SpriteFrames` when:

- You need frame-based 2D sprite animation.
- You need to switch sequences, speed, offsets, or orientation.

Use `AnimationPlayer` when:

- Animation should trigger methods, particles, sound, property changes, or non-frame effects.
- You need cut-out animation, transform animation, mesh animation, or broad property animation.

Use `AnimationTree` when:

- You need blending, smooth transitions, state machines, or hierarchical animation behavior.

## Runtime logic preferences

### Set properties before adding nodes

When creating nodes from code, set initial values before adding the node to the scene tree when possible. Some property setters trigger expensive updates once the node is in the tree, which can matter in procedural generation or bulk node creation.

Example pattern:

```gdscript
var enemy := EnemyScene.instantiate()
enemy.position = spawn_position
enemy.name = "Enemy_%d" % index
add_child(enemy)
```

Exception:

- Some properties, such as global transforms or global positions, may require the node to be inside the tree.

### Loading versus preloading

Use `const SomeScene = preload("res://path/to/scene.tscn")` when:

- the path is static,
- the dependency is always needed with the script,
- editor completion is useful,
- you want loading to occur with the script.

Use `load()` or `ResourceLoader.load()` when:

- the path is dynamic,
- the resource should be loaded lazily,
- memory should be released later,
- the dependency may be replaced or configured externally.

Avoid:

- preloading many heavy dependencies into scripts that may load earlier or more often than expected,
- preloading exported properties that will be overwritten by scene data,
- using `load()` for constants in GDScript.

To unload a dynamically loaded resource, remove all references, for example by setting the property to `null`, assuming no other references remain.

### Large levels

Use static levels when:

- the game is small,
- memory usage is acceptable,
- simplicity and reliability matter more than streaming.

Use dynamic loading/unloading when:

- worlds are large,
- environments vary greatly,
- procedural generation is involved,
- loading everything would waste memory or cause crashes.

Prefer breaking large scenes into smaller reusable scenes regardless of static or dynamic strategy.

Be cautious:

- Dynamic streaming systems add complexity and technical debt.
- Build them only when performance or memory requirements justify it.
- If possible, isolate streaming into a reusable library, plugin, or well-tested manager node.

## Project organization

Godot uses the filesystem directly and does not require a fixed project layout. Prefer a layout that keeps assets close to the scenes that use them.

Recommended principles:

- Group assets near their related scenes for maintainability.
- Keep reusable project-wide assets in clear top-level folders.
- Keep levels, characters, UI, audio, and shared resources organized by domain.
- Keep third-party resources in a top-level `addons/` folder unless they clearly belong with a specific game asset.
- Use `.gdignore` in folders that should not be imported by Godot.

Example layout:

```text
/project.godot
/addons/
/characters/player/player.tscn
/characters/player/player.gd
/characters/player/player.png
/characters/enemies/goblin/goblin.tscn
/characters/enemies/goblin/goblin.png
/levels/riverdale/riverdale.tscn
/ui/hud/hud.tscn
/resources/items/
/audio/sfx/
/docs/.gdignore
```

Naming conventions:

- Use `snake_case` for folders and file names, except C# scripts.
- Use PascalCase for node names, matching built-in node naming style.
- Use PascalCase for C# script files/classes according to C# convention.
- Keep filename casing consistent because exported Godot PCK files are case-sensitive even when the development filesystem is not.
- Avoid relying on case-insensitive behavior from Windows or macOS.

`.gdignore` notes:

- An empty `.gdignore` file prevents Godot from importing files in that folder.
- Ignored folders are hidden from the FileSystem dock.
- Resources inside ignored folders cannot be loaded with `load()` or `preload()`.
- `.gdignore` does not support `.gitignore`-style patterns.

## Version control

Godot is generally friendly to version control and mostly produces readable, mergeable files.

Always commit:

- `project.godot`,
- `.tscn`, `.tres`, `.gd`, `.cs`, shader, and resource source files,
- import source assets such as textures, audio, models, fonts, and data files,
- `.gitattributes`,
- `.gitignore`,
- export preset files when appropriate for the team and Godot version.

For Godot 4.1 and later, ignore:

```gitignore
.godot/
*.translation
```

Be careful with Godot 3.x and Godot 4.0 because ignore rules and sensitive-data considerations differ.

On Windows:

- Prefer LF line endings for Godot project files.
- If needed, use `git config --global core.autocrlf input`.
- Godot’s generated `.gitattributes` can enforce LF line endings.

Use Git LFS for large binary assets when appropriate:

- 3D models: `*.fbx`, `*.gltf`, `*.glb`, `*.blend`, `*.obj`.
- Images: `*.png`, `*.svg`, `*.jpg`, `*.jpeg`, `*.gif`, `*.tga`, `*.webp`, `*.exr`, `*.hdr`, `*.dds`.
- Audio: `*.mp3`, `*.wav`, `*.ogg`.
- Fonts/icons: `*.ttf`, `*.otf`, `*.ico`.
- Godot binary/resource outputs when used: `*.scn`, `*.res`, `*.material`, `*.anim`, `*.mesh`, `*.lmbake`.

Set up Git LFS before committing large files. If files were already committed, migrating history is more complex; a clean repository with LFS configured from the start is often simpler.

## GDScript style and safety

Use Godot 4-style GDScript unless the project is Godot 3.x:

- `@export`, `@onready`, `@tool` annotations.
- `signal my_signal` and `my_signal.emit()`.
- `Callable` and typed variables where useful.
- `CharacterBody2D`/`CharacterBody3D` rather than older Godot 3 `KinematicBody` types.

Prefer typed GDScript when it improves clarity and catches mistakes:

```gdscript
@export var speed: float = 300.0
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var target: Node2D
```

Use explicit resource types:

```gdscript
@export var enemy_scene: PackedScene
@export var stats: Resource
```

Cache nodes:

```gdscript
@onready var health_bar: ProgressBar = $UI/HealthBar
```

Connect signals explicitly:

```gdscript
func _ready() -> void:
    hitbox.body_entered.connect(_on_hitbox_body_entered)
```

Validate required exported dependencies:

```gdscript
@tool
extends Node

@export var target: Node

func _get_configuration_warnings() -> PackedStringArray:
    if target == null:
        return ["Assign target before running this scene."]
    return []
```

Use assertions for programmer errors in development, but do not rely on them for release behavior:

```gdscript
assert(enemy_scene != null, "enemy_scene must be assigned")
```

## Refactoring guidance

When asked to improve Godot code:

1. Look for hidden scene dependencies and replace them with exported references, signals, callables, or parent-managed wiring.
2. Replace broad autoload usage with local ownership or resources when scope is local.
3. Cache repeated node lookups.
4. Move game-specific node compositions into scenes.
5. Move shared data into resources.
6. Move pure runtime data into `RefCounted` or `Resource` classes instead of nodes.
7. Replace per-frame polling with timers or input callbacks when possible.
8. Split large scenes into reusable sub-scenes.
9. Preserve editor usability: exported properties, clear node names, configuration warnings, and inspector-friendly resources.
10. Keep changes compatible with the project’s Godot version.

## Common anti-patterns to flag

- A reusable child scene calls `get_parent().get_parent()` or hard-codes sibling paths.
- Every system is an autoload manager.
- Scene-specific behavior is centralized in a global script.
- Repeated `get_node()` calls occur in `_process()` or tight loops.
- Input is polled every frame when event callbacks would suffice.
- Large gameplay concepts are built entirely by imperative scripts when scenes would be clearer.
- Simple data records are implemented as nodes.
- Exported properties are preloaded with values that the scene overwrites.
- Node properties are set after `add_child()` during bulk creation when they could be set before.
- Large arrays are searched linearly every frame.
- File names differ only by case or use inconsistent casing.
- `.godot/` or imported/generated files are committed unnecessarily.
- Large binary assets are committed without Git LFS in asset-heavy projects.

## Response style for Codex

When applying this skill:

- Explain Godot-specific reasoning briefly and concretely.
- Prefer project-aware recommendations over generic patterns.
- Give before/after code only when it clarifies the change.
- Do not invent node names, input actions, or resource paths without checking the project or marking them as placeholders.
- Respect the existing editor workflow; avoid turning editor-authored scene composition into code unless necessary.
- Mention tradeoffs: simplicity versus memory, local ownership versus global access, scene clarity versus script flexibility.
- For performance claims, distinguish between likely best practice and project-specific measurement.
