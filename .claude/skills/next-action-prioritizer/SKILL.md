---
name: next-action-prioritizer
description: Use when the user asks what to do next in this Godot space-float-2 project, asks for a ranked roadmap, asks what to focus on now, or wants review-mode prioritization of next coding tasks. Produces ranked next actions from repository evidence, current diffs, Godot scene/script load risk, project plans, TODOs, and simulation/gameplay correctness risk. Do not use for general code review unless the user asks for prioritization or next steps.
---

# Next Action Prioritizer

## Purpose

Help the user decide the next most valuable thing to do in this Godot project. Work like a planning-oriented review mode: inspect the repository, identify multiple plausible next actions when appropriate, rank them by importance, and explain the evidence behind the ranking.

The output should help the user choose what to work on immediately, not produce a broad generic roadmap.

## Project profile

This repository is `space-float-2`, a Godot 4.7 double-precision project.

- `project.godot` defines the main scene and autoloads. Treat it as the source of truth for runtime entry points, input actions, physics settings, and singleton names.
- The active main scene is `scene/test/test.tscn`; `scene/sim/physics-harness.tscn` is a secondary harness.
- Core gameplay/simulation code lives under `scene/vessel/`, `scene/engine/`, `scene/sim/`, `scene/globe/`, `scene/system/solar/`, `scene/command/`, `scene/selection/`, and `scene/ui/`.
- Planning notes live under `doc/plan/`. They may be ignored by Git, but they are important evidence when present.
- `model/` and `texture/` may be ignored locally. Still inspect them when scene resources reference `res://model/...` or `res://texture/...`; distinguish "needed at runtime" from "safe to commit".
- Use the project Godot binary unless intentionally testing another editor:
  `/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64`

## Operating principles

- Evidence first. Base recommendations on observable repository signals: current diff, failing tests, TODO/FIXME comments, recent commits, issue/PR context if available, build configuration, docs, dependency files, and obvious architectural seams.
- No destructive actions. Do not modify files, reformat the codebase, install dependencies, or run long-running commands unless the user explicitly asks.
- Prefer concrete next actions over vague advice.
- Rank more than one item when there are multiple credible priorities.
- Make uncertainty explicit. If evidence is thin, say so and describe what would reduce uncertainty.
- Keep scope local to the current project unless the user asks for broader product or business planning.
- Treat broken correctness, build, tests, security, data loss, and release blockers as higher priority than style, cleanup, or speculative refactors.
- Treat active scene/script breakage and simulation correctness bugs as higher priority than cleanup in unattached prototypes.
- Do not treat stray OS files such as `.DS_Store` as a top priority unless the user is specifically asking about repository hygiene.

## Workflow

### 1. Establish the project state

Inspect the current repository and working tree before recommending work.

Start with the bundled helper when available:

```bash
bash .codex/skills/next-action-prioritizer/scripts/collect_signals.sh
```

Then follow up with targeted commands as needed:

```bash
pwd
git status --short --branch
git diff --stat
git diff --name-only
git log --oneline -n 10
rg --files --hidden --no-ignore AGENTS.md project.godot scene doc/plan .codex/skills/next-action-prioritizer 2>/dev/null
rg -n "TODO|FIXME|HACK|XXX" AGENTS.md project.godot scene doc/plan .codex 2>/dev/null
```

Use `rg` and `fd`/`fdfind`; do not use `grep`, `find`, or `ls -R` for repo-wide discovery.

### 2. Read the project instructions

Look for and follow local instructions before analyzing priorities:

- `AGENTS.md`
- `project.godot`
- `doc/plan/*.md` if present
- scene/script files near current diffs or recent plan findings
- `export_presets.cfg` only when export or Android packaging is relevant

### 3. Gather priority signals

Look for these signals, in roughly this order:

1. **Broken Godot load/runtime path**: parser errors, missing scene resources, missing node paths, broken autoloads, invalid UIDs, invalid exported resources, or main-scene startup failures.
2. **Current user intent**: files already modified, branch name, recent commits, TODOs introduced in the diff, unfinished plan notes, or open harness work.
3. **Simulation/gameplay correctness**: vessel control, gimbal/thrust vectoring, mass/propellant state, physics integration, camera behavior, selection/command routing, globe/solar scene consistency.
4. **Reproducibility and export blockers**: scene references to ignored/missing assets, missing `.import` metadata, export preset drift, project settings that make a fresh clone fail.
5. **Test/validation gaps**: no scene-load check for changed scenes, harness mismatch, behavior hard to verify manually, lack of regression coverage around fixed physics or command behavior.
6. **Maintainability leverage**: duplicated model state, unclear node ownership, dead/unattached prototype scripts, confusing scene hierarchy, stale docs.
7. **Low-value cleanup**: style-only changes, broad refactors without a concrete unblocker. These should usually rank lower.

Useful searches for this project:

```bash
rg -n "res://(model|texture)|run/main_scene|autoload|script =" project.godot scene
rg -n "ship_|zoom_|exit" project.godot scene
rg -n "\\$[A-Za-z0-9_/]+|get_node|NodePath" scene
rg -n "class_name|@export|@onready|_ready|_physics_process|_integrate_forces" scene
git ls-files scene project.godot export_presets.cfg
```

If a plan file names a likely issue, re-check the referenced code before repeating it. Mark it as stale if the code has changed.

### 4. Run cheap verification only

Run only fast, non-destructive checks when they are clearly relevant and likely to complete quickly.

Primary Godot load check:

```bash
test -x /Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --headless --path . --quit
```

Manual checks to recommend, not run automatically:

- Run the main scene with the project Godot binary.
- Exercise `scene/test/test.tscn` for main gameplay/simulation behavior.
- Exercise `scene/sim/physics-harness.tscn` when the change touches that harness.
- Export Android only when export settings or packaging are part of the priority question.

If a command may be slow, invasive, require network access, or install dependencies, do not run it automatically. List it as a recommended verification step.

### 5. Rank candidate next actions

Score each candidate from 1 to 5 in these dimensions:

- **Blocker impact**: does this block project load, scene startup, fresh clone reproducibility, export, or use of the active harness?
- **Correctness/user impact**: does this affect flight control, simulation state, camera/selection/command behavior, rendering of required bodies/assets, or player-visible UI?
- **Risk reduction**: does it reduce uncertainty, prevent regressions, or clarify an unsafe area?
- **Dependency order**: does other work depend on this being done first?
- **Effort efficiency**: can it produce meaningful progress relative to effort?

Use the ranking rule:

```text
priority_score = blocker_impact + correctness_user_impact + risk_reduction + dependency_order + effort_efficiency
```

Tie-breakers:

1. Fix known failures before speculative improvements.
2. Finish coherent in-progress work before starting unrelated work.
3. Prefer active main-scene and harness breakage over stale unattached prototypes.
4. Prefer small, reversible steps over large uncertain rewrites.
5. Add focused validation around changed behavior before broad refactors.

Do not show the numeric score unless it helps. The final ranking should be human-readable.

## Output format

Use this structure unless the user requested another format:

```markdown
## Recommended next focus

1. **<next action>**
   - **Why this is #1:** <short evidence-based rationale>
   - **Evidence:** <files, diffs, test output, TODOs, issue/PR signals>
   - **Concrete next step:** <one command or one small code/doc/test task>
   - **Confidence:** High/Medium/Low

2. **<next action>**
   - **Why this is next:** <rationale>
   - **Evidence:** <evidence>
   - **Concrete next step:** <task>
   - **Confidence:** High/Medium/Low

## Suggested order of work

<1-5 sentence explanation of the sequence.>

## Checks to run before moving on

- `<command>` — <why>
- `<command>` — <why>

## What I would not prioritize yet

- <lower-priority item and why>
```

When there is only one meaningful next action, say so, but still include any secondary checks or follow-up work.

For this project, the first check is usually:

```bash
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --headless --path . --quit
```

## Evidence standards

For each recommendation, cite specific repository evidence in plain text:

- file paths
- changed files
- function/class/module names
- command output summaries
- TODO/FIXME lines
- failing test names
- issue/PR titles or numbers if available
- scene node paths, `ext_resource` paths, autoload names, and input action names when relevant

Avoid unsupported claims like “the architecture is bad” or “tests are weak” unless you can point to concrete evidence.

## Behavior when evidence is limited

If there is no current diff, no test framework, or sparse documentation:

1. Say that the ranking has limited confidence.
2. Prioritize the minimal feedback loop: confirm the project loads with the project Godot binary.
3. Read `doc/plan/*.md` and re-validate any prior findings before ranking them.
4. Recommend one exploratory task that produces evidence, such as a minimal scene-load check, a harness repair, or a focused manual test note.

Example:

```markdown
1. **Establish a reliable Godot load check**
   - **Why this is #1:** There is no dedicated unit-test framework, so scene/script load is the fastest shared safety check.
   - **Evidence:** `AGENTS.md` lists the headless Godot load command; no dedicated test framework is checked in.
   - **Concrete next step:** Run `/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --headless --path . --quit` and capture any parser or missing-resource errors.
   - **Confidence:** Medium
```

## Guardrails

- Do not invent project goals, deadlines, or issue context.
- Do not recommend large rewrites unless there is strong evidence they unblock important work.
- Do not produce a long backlog unless asked. Focus on the next 3-5 actions.
- Do not change code as part of this skill unless the user explicitly asks to implement one of the ranked actions.
- If the user asks to implement after prioritization, switch from analysis to execution and work on the selected item only.
- Do not rewrite `.tscn` UIDs, exported property names, input action names, signal method names, or node paths unless the priority is explicitly to migrate them.
- Do not recommend committing ignored generated directories such as `.godot/`, `android/`, or `target/`.
