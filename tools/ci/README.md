# Godot CI

This directory contains the helper scripts used by `.github/workflows/godot-ci.yml`.
The workflow validates GDScript parsing, runs GdUnit4, and publishes generated
GDScript API documentation as a static GitHub Pages site.

## Repository Variables

Configure these GitHub repository variables before enabling the workflow:

| Variable | Description |
| --- | --- |
| `GODOT_LINUX_URL` | Direct URL to a Linux Godot 4.7 double-precision editor archive or binary. |
| `GODOT_LINUX_SHA256` | SHA-256 digest of the file at `GODOT_LINUX_URL`. |

The binary must be an editor-capable build. Export templates do not include the
`--doctool` and `--gdscript-docs` options used by the documentation job.

The documentation job is centralized in `tools/ci/build_docs.py`. In CI, that
script installs the configured Godot binary, bootstraps the GdUnit4 addon, runs
Godot's GDScript doctool, and writes the static website to `target/docs/site/`.
The generated HTML reuses Godot's official Read-the-Docs theme CSS and
`_static/css/custom.css`, then layers a small local stylesheet for the generated
API index and member cards.

## Local Validation

From the project root, use the local double-precision Godot editor binary:

```bash
python3 tools/ci/check_gdscript.py --godot /Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64
python3 tools/bootstrap-gdunit4.py
/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --headless --log-file "$PWD/target/reports/gdunit.log" --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit
python3 tools/ci/build_docs.py --godot /Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64 --bootstrap-gdunit4
```

The scripts write logs and generated files under ignored directories:

- `target/reports/` for Godot invocation logs.
- `reports/` for GdUnit4 HTML/XML reports.
- `target/docs/xml/` and `target/docs/site/` for generated API docs.
