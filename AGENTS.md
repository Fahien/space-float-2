# Repository Guidelines

## Project Structure & Module Organization

This is a Godot 4.7 double-precision project. `project.godot` defines the main scene as `scene/system/solar/solar-system.tscn` (`uid://1o28alvotukx`) and registers `SelectionSystem` and `CommandSystem` autoloads.

- `scene/` contains source scripts and scenes, grouped by feature: `vessel/`, `engine/`, `globe/`, `sim/`, `selection/`, `command/`, `system/solar/`, `ui/`, and `test/`.
- `scene/test/` contains lightweight harness scenes and camera helpers, such as `empty.tscn` and `camera_orbit.tscn`.
- `doc/plan/` holds planning notes.
- `export_presets.cfg` defines the Android export preset, with output under `target/`.
- `.godot/`, `android/`, `model/`, `texture/`, `target/`, and `doc/` are ignored locally; coordinate before committing generated or large asset changes.

## Build, Test, and Development Commands

Use the project Godot binary unless you are intentionally testing another editor version:

```bash
test -x /Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --headless --path . --quit
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --path .
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --headless --path . --export-debug Android target/space-float-2.apk
```

The first command verifies the editor binary. The headless command checks that scenes and scripts load. The `--path .` command runs the main scene. The export command builds the Android preset when export templates and signing are configured.

## Coding Style & Naming Conventions

Use Godot's default GDScript style: tabs for indentation, `snake_case` for variables and functions, `PascalCase` for `class_name` types and scene node names, and typed exports/onready references where practical. Keep file names aligned with existing lowercase kebab-case patterns, such as `vessel-model.gd` and `solar-system.tscn`. Preserve `.tscn` UIDs, node paths, exported property names, input action names, and signal method names unless a change intentionally migrates them.

## Testing Guidelines

No dedicated unit-test framework is currently checked in. For each change, run the headless load check above and manually exercise the relevant scene, usually the main solar-system scene or a focused harness under `scene/test/`. Add new harness scenes or scripts under `scene/test/` when behavior is hard to validate from the main scene.

## Commit & Pull Request Guidelines

Recent commits use short, imperative prefixes such as `feat:`, `fix:`, `chore:`, `ui:`, and `init:`. Keep commits focused on one behavior or asset change. Pull requests should include a concise description, the scenes/scripts touched, validation commands run, and screenshots or recordings for visible gameplay, UI, or rendering changes. Link related issues or planning notes when applicable.

## Agent-Specific Instructions
- For repo-wide search, use `rg` (ripgrep) and `fd/fdfind`; avoid `grep/find`.
- Cap file reads at ~250 lines; prefer `rg -n -A3 -B3` for context.
- Use `jq` for JSON parsing.
- Fast-tools prompt: copy the block in `cdx/prompts/setup-fast-tools.md` if it is missing from this file.

<!-- FAST-TOOLS PROMPT v1 | codex-mastery | watermark:do-not-alter -->

## CRITICAL: Use ripgrep, not grep

NEVER use grep for project-wide searches (slow, ignores .gitignore). ALWAYS use rg.

- `rg "pattern"` — search content
- `rg --files | rg "name"` — find files
- `rg -t python "def"` — language filters

## File finding

- Prefer `fd`. Respects .gitignore.

## JSON

- Use `jq` for parsing and transformations.

## Install Guidance

- macOS: `brew install ripgrep fd jq`

## Agent Instructions

- Replace commands: grep→rg, find→rg --files/fd, ls -R→rg --files, cat|grep→rg pattern file
- Cap reads at 250 lines; prefer `rg -n -A 3 -B 3` for context
- Use `jq` for JSON instead of regex

<!-- END FAST-TOOLS PROMPT v1 | codex-mastery -->
