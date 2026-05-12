#!/usr/bin/env python3
"""Install the pinned GdUnit4 addon into this Godot project.

The repository ignores addons/, so this script recreates addons/gdUnit4 from
the upstream release zip needed by project.godot.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tempfile
from typing import Optional
import urllib.error
import urllib.request
import zipfile


VERSION = "6.1.3"
RELEASE_URL = f"https://github.com/godot-gdunit-labs/gdUnit4/archive/refs/tags/v{VERSION}.zip"
ADDON_PREFIX = ("addons", "gdUnit4")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download GdUnit4 and install addons/gdUnit4 for this project.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Godot project root. Defaults to this repository root.",
    )
    parser.add_argument(
        "--url",
        default=RELEASE_URL,
        help=f"GdUnit4 release zip URL. Defaults to v{VERSION}.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace an existing addons/gdUnit4 directory.",
    )
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def download_release(url: str, archive_path: Path) -> None:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "space-float-2-gdunit-bootstrap"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            with archive_path.open("wb") as archive:
                shutil.copyfileobj(response, archive)
    except urllib.error.URLError as exc:
        fail(f"failed to download {url}: {exc}")


def addon_relative_path(member_name: str) -> Optional[Path]:
    parts = PurePosixPath(member_name).parts
    for index in range(0, len(parts) - len(ADDON_PREFIX) + 1):
        if parts[index : index + len(ADDON_PREFIX)] == ADDON_PREFIX:
            relative_parts = parts[index + len(ADDON_PREFIX) :]
            if not relative_parts or any(part in ("", ".", "..") for part in relative_parts):
                return None
            return Path(*relative_parts)
    return None


def verify_inside(path: Path, root: Path) -> None:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        fail(f"archive member escapes target directory: {path}")


def extract_addon(archive_path: Path, destination: Path) -> int:
    extracted_files = 0
    with zipfile.ZipFile(archive_path) as archive:
        for member in archive.infolist():
            relative_path = addon_relative_path(member.filename)
            if relative_path is None:
                continue

            target_path = destination / relative_path
            verify_inside(target_path, destination)

            if member.is_dir():
                target_path.mkdir(parents=True, exist_ok=True)
                continue

            target_path.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member) as source:
                with target_path.open("wb") as target:
                    shutil.copyfileobj(source, target)

            mode = member.external_attr >> 16
            if mode:
                os.chmod(target_path, mode & 0o777)
            extracted_files += 1

    return extracted_files


def install_addon(project_root: Path, url: str, force: bool) -> None:
    project_file = project_root / "project.godot"
    if not project_file.is_file():
        fail(f"{project_root} does not look like a Godot project root")

    addons_dir = project_root / "addons"
    target_dir = addons_dir / "gdUnit4"
    plugin_cfg = target_dir / "plugin.cfg"
    if target_dir.exists() and not force:
        if plugin_cfg.is_file():
            print(f"GdUnit4 already installed at {target_dir}")
            return
        fail(f"{target_dir} exists but plugin.cfg is missing; rerun with --force")

    with tempfile.TemporaryDirectory(prefix="gdunit4-bootstrap-") as temp_root:
        temp_root_path = Path(temp_root)
        archive_path = temp_root_path / "gdUnit4.zip"
        extract_dir = temp_root_path / "gdUnit4"

        print(f"Downloading {url}")
        download_release(url, archive_path)
        extracted_files = extract_addon(archive_path, extract_dir)
        if extracted_files == 0:
            fail("release archive did not contain addons/gdUnit4")

        if force and target_dir.exists():
            shutil.rmtree(target_dir)
        addons_dir.mkdir(parents=True, exist_ok=True)
        shutil.move(str(extract_dir), str(target_dir))

    print(f"Installed GdUnit4 v{VERSION} at {target_dir}")


def main() -> None:
    args = parse_args()
    install_addon(args.project_root.resolve(), args.url, args.force)


if __name__ == "__main__":
    main()
