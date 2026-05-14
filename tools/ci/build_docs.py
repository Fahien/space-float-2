#!/usr/bin/env python3
"""Build the static documentation website used locally and by CI."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import sys

import generate_gdscript_docs


DEFAULT_LOCAL_GODOT = Path("/Users/fahien/Workspace/godot/engine/bin/godot.macos.editor.double.arm64")


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Build the static GDScript API documentation website.",
    )
    parser.add_argument(
        "--godot",
        default=os.environ.get("GODOT_BIN", ""),
        help="Godot editor binary. Defaults to GODOT_BIN, then the project-local macOS editor when present.",
    )
    parser.add_argument(
        "--install-godot",
        action="store_true",
        help="Run tools/ci/install_godot.py first and build with the installed CI binary.",
    )
    parser.add_argument(
        "--bootstrap-gdunit4",
        action="store_true",
        help="Run tools/bootstrap-gdunit4.py before generating docs.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=project_root,
        help=f"Godot project root. Defaults to {project_root}.",
    )
    parser.add_argument(
        "--source",
        default="res://scene",
        help="GDScript docs source path passed to --gdscript-docs.",
    )
    parser.add_argument(
        "--xml-dir",
        type=Path,
        default=project_root / "target" / "docs" / "xml",
        help="Directory for Godot doctool XML output.",
    )
    parser.add_argument(
        "--site-dir",
        type=Path,
        default=project_root / "target" / "docs" / "site",
        help="Directory for generated static HTML.",
    )
    parser.add_argument(
        "--reports-dir",
        type=Path,
        default=project_root / "target" / "reports",
        help="Directory for Godot logs.",
    )
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def run_checked(command: list[str], cwd: Path) -> str:
    print("+ " + shlex.join(command))
    result = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.returncode != 0:
        fail(f"{command[0]} failed with exit code {result.returncode}")
    return result.stdout


def install_godot(project_root: Path) -> str:
    output = run_checked([sys.executable, "tools/ci/install_godot.py"], project_root)
    for line in output.splitlines():
        if line.startswith("GODOT_BIN="):
            return line.split("=", 1)[1].strip()
    fail("tools/ci/install_godot.py did not report GODOT_BIN")


def bootstrap_gdunit4(project_root: Path) -> None:
    run_checked([sys.executable, "tools/bootstrap-gdunit4.py"], project_root)


def resolve_godot(args: argparse.Namespace, project_root: Path) -> str:
    if args.install_godot:
        return install_godot(project_root)

    if args.godot:
        return args.godot

    if DEFAULT_LOCAL_GODOT.is_file():
        return str(DEFAULT_LOCAL_GODOT)

    fail("GODOT_BIN is required, pass --godot, or use --install-godot")


def main() -> None:
    args = parse_args()
    project_root = args.project_root.resolve()
    if not (project_root / "project.godot").is_file():
        fail(f"{project_root} does not contain project.godot")

    godot = resolve_godot(args, project_root)
    if args.bootstrap_gdunit4:
        bootstrap_gdunit4(project_root)

    xml_dir = args.xml_dir.resolve()
    site_dir = args.site_dir.resolve()
    reports_dir = args.reports_dir.resolve()
    generate_gdscript_docs.run_doctool(godot, project_root, xml_dir, reports_dir, args.source)
    generate_gdscript_docs.write_site(xml_dir, site_dir, args.source)
    print(f"Generated docs at {site_dir}")


if __name__ == "__main__":
    main()
