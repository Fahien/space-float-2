#!/usr/bin/env python3
"""Run Godot-native parser checks for tracked GDScript files."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


TRACKED_SCRIPT_ROOTS = ("scene/", "test/")
EXCLUDED_PREFIXES = ("addons/", ".godot/", "target/", "reports/")


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Check tracked GDScript files with Godot --check-only.",
    )
    parser.add_argument(
        "--godot",
        default=os.environ.get("GODOT_BIN", ""),
        help="Godot editor binary. Defaults to GODOT_BIN.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=project_root,
        help=f"Godot project root. Defaults to {project_root}.",
    )
    parser.add_argument(
        "--reports-dir",
        type=Path,
        default=project_root / "target" / "reports" / "gdscript-check",
        help="Directory for per-script Godot logs.",
    )
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


def tracked_gdscript_files(project_root: Path) -> list[Path]:
    result = run(["git", "ls-files", "*.gd"], project_root)
    if result.returncode != 0:
        fail(f"git ls-files failed:\n{result.stdout}")

    paths: list[Path] = []
    for line in result.stdout.splitlines():
        if not line:
            continue
        if not line.startswith(TRACKED_SCRIPT_ROOTS):
            continue
        if line.startswith(EXCLUDED_PREFIXES):
            continue
        paths.append(Path(line))
    return sorted(paths)


def res_path(path: Path) -> str:
    return "res://" + path.as_posix()


def log_path_for(reports_dir: Path, script_path: Path) -> Path:
    return reports_dir / script_path.with_suffix(".log")


def check_python_tools(project_root: Path) -> None:
    result = run([sys.executable, "-m", "compileall", "-q", "tools"], project_root)
    if result.returncode != 0:
        fail(f"Python syntax check failed:\n{result.stdout}")


def check_gdscript(godot: str, project_root: Path, reports_dir: Path, scripts: list[Path]) -> None:
    if not godot:
        fail("GODOT_BIN is required, or pass --godot")

    reports_dir.mkdir(parents=True, exist_ok=True)
    failures: list[tuple[Path, int, str, Path]] = []

    for script_path in scripts:
        output_log = log_path_for(reports_dir, script_path)
        output_log.parent.mkdir(parents=True, exist_ok=True)

        command = [
            godot,
            "--headless",
            "--log-file",
            str(output_log),
            "--path",
            str(project_root),
            "--check-only",
            "--script",
            res_path(script_path),
        ]
        result = run(command, project_root)
        if result.returncode != 0:
            failures.append((script_path, result.returncode, result.stdout, output_log))

    if failures:
        print(f"{len(failures)} GDScript parser check(s) failed:", file=sys.stderr)
        for script_path, returncode, output, output_log in failures:
            print(f"\n{script_path} failed with exit code {returncode}", file=sys.stderr)
            print(f"Log: {output_log}", file=sys.stderr)
            if output.strip():
                print(output.strip(), file=sys.stderr)
        raise SystemExit(1)


def main() -> None:
    args = parse_args()
    project_root = args.project_root.resolve()
    if not (project_root / "project.godot").is_file():
        fail(f"{project_root} does not contain project.godot")

    scripts = tracked_gdscript_files(project_root)
    if not scripts:
        fail("no tracked GDScript files found under scene/ or test/")

    check_python_tools(project_root)
    check_gdscript(args.godot, project_root, args.reports_dir.resolve(), scripts)
    print(f"Checked {len(scripts)} GDScript files and Python tools")


if __name__ == "__main__":
    main()
