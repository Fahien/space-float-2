#!/usr/bin/env python3
"""Install the pinned Godot editor binary for CI."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tarfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile


DEFAULT_CACHE_DIR = Path.home() / ".cache" / "space-float-2" / "godot"
DOWNLOAD_NAME = "godot-download"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download, verify, cache, and expose a Godot editor binary.",
    )
    parser.add_argument(
        "--url",
        default=os.environ.get("GODOT_LINUX_URL", ""),
        help="Godot Linux editor archive URL. Defaults to GODOT_LINUX_URL.",
    )
    parser.add_argument(
        "--sha256",
        default=os.environ.get("GODOT_LINUX_SHA256", ""),
        help="Expected archive SHA-256. Defaults to GODOT_LINUX_SHA256.",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path(os.environ.get("GODOT_CACHE_DIR", DEFAULT_CACHE_DIR)),
        help=f"Cache directory. Defaults to {DEFAULT_CACHE_DIR}.",
    )
    parser.add_argument(
        "--version-token",
        default="4.7",
        help="Version token required in `godot --version` output.",
    )
    parser.add_argument(
        "--precision-token",
        default="double",
        help="Precision token required in `godot --version` output.",
    )
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalized_sha256(value: str) -> str:
    digest = value.strip().lower()
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        fail("GODOT_LINUX_SHA256 must be a 64-character hexadecimal SHA-256 digest")
    return digest


def download_file(url: str, destination: Path) -> None:
    if not url.strip():
        fail("GODOT_LINUX_URL is required")

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "space-float-2-ci-godot-installer"},
    )
    temp_destination = destination.with_suffix(".tmp")
    temp_destination.parent.mkdir(parents=True, exist_ok=True)

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            with temp_destination.open("wb") as output:
                shutil.copyfileobj(response, output)
    except urllib.error.URLError as exc:
        fail(f"failed to download Godot from {url}: {exc}")

    temp_destination.replace(destination)


def file_sha256(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def verify_sha256(path: Path, expected: str) -> None:
    actual = file_sha256(path)
    if actual != expected:
        fail(f"SHA-256 mismatch for {path}: expected {expected}, got {actual}")


def verify_inside(path: Path, root: Path) -> None:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        fail(f"archive member escapes extraction directory: {path}")


def extract_zip(archive_path: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive_path) as archive:
        for member in archive.infolist():
            relative_path = Path(*PurePosixPath(member.filename).parts)
            if not relative_path.parts:
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


def extract_tar(archive_path: Path, destination: Path) -> None:
    with tarfile.open(archive_path) as archive:
        for member in archive.getmembers():
            relative_path = Path(*PurePosixPath(member.name).parts)
            if not relative_path.parts:
                continue

            target_path = destination / relative_path
            verify_inside(target_path, destination)

            if member.isdir():
                target_path.mkdir(parents=True, exist_ok=True)
                continue

            if not member.isfile():
                continue

            source = archive.extractfile(member)
            if source is None:
                continue

            target_path.parent.mkdir(parents=True, exist_ok=True)
            with source:
                with target_path.open("wb") as target:
                    shutil.copyfileobj(source, target)

            if member.mode:
                os.chmod(target_path, member.mode & 0o777)


def install_archive(archive_path: Path, install_dir: Path) -> None:
    if install_dir.exists():
        shutil.rmtree(install_dir)
    install_dir.mkdir(parents=True)

    if zipfile.is_zipfile(archive_path):
        extract_zip(archive_path, install_dir)
        return

    if tarfile.is_tarfile(archive_path):
        extract_tar(archive_path, install_dir)
        return

    binary_path = install_dir / "godot"
    shutil.copy2(archive_path, binary_path)
    binary_path.chmod(binary_path.stat().st_mode | stat.S_IXUSR)


def candidate_score(path: Path) -> tuple[int, str]:
    name = path.name.lower()
    score = 0
    for token, value in (
        ("godot", 10),
        ("linux", 5),
        ("linuxbsd", 5),
        ("editor", 4),
        ("double", 3),
        ("headless", 2),
    ):
        if token in name:
            score += value
    if path.is_file() and os.access(path, os.X_OK):
        score += 2
    return (-score, str(path))


def discover_binary(install_dir: Path) -> Path:
    candidates: list[Path] = []
    for path in install_dir.rglob("*"):
        if not path.is_file():
            continue
        if "godot" not in path.name.lower():
            continue
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        candidates.append(path)

    if not candidates:
        fail(f"could not find a Godot binary under {install_dir}")

    return sorted(candidates, key=candidate_score)[0]


def command_output(command: list[str]) -> str:
    try:
        result = subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
        )
    except OSError as exc:
        fail(f"failed to execute {command[0]}: {exc}")
    except subprocess.TimeoutExpired:
        fail(f"timed out while executing {command[0]}")

    if result.returncode != 0:
        fail(f"{' '.join(command)} failed with exit code {result.returncode}\n{result.stdout}")
    return result.stdout.strip()


def verify_godot_binary(binary_path: Path, version_token: str, precision_token: str) -> None:
    version = command_output([str(binary_path), "--version"])
    lower_version = version.lower()
    if version_token.lower() not in lower_version:
        fail(f"{binary_path} reported version {version!r}, expected token {version_token!r}")
    if precision_token.lower() not in lower_version:
        fail(f"{binary_path} reported version {version!r}, expected token {precision_token!r}")

    help_text = command_output([str(binary_path), "--headless", "--help"])
    if "--doctool" not in help_text or "--gdscript-docs" not in help_text:
        fail(f"{binary_path} is not an editor-capable build with doctool support")


def write_github_env(binary_path: Path) -> None:
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        with Path(github_env).open("a", encoding="utf-8") as env_file:
            env_file.write(f"GODOT_BIN={binary_path}\n")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with Path(github_output).open("a", encoding="utf-8") as output_file:
            output_file.write(f"godot-bin={binary_path}\n")


def main() -> None:
    args = parse_args()
    expected_sha = normalized_sha256(args.sha256)
    cache_entry = args.cache_dir.expanduser() / expected_sha
    archive_path = cache_entry / DOWNLOAD_NAME
    install_dir = cache_entry / "install"

    if not archive_path.is_file():
        parsed_url = urllib.parse.urlparse(args.url)
        if not parsed_url.scheme:
            fail("GODOT_LINUX_URL must be an absolute URL")
        print(f"Downloading Godot from {args.url}")
        download_file(args.url, archive_path)

    verify_sha256(archive_path, expected_sha)

    if not install_dir.exists():
        print(f"Extracting Godot into {install_dir}")
        install_archive(archive_path, install_dir)

    godot_bin = discover_binary(install_dir)
    verify_godot_binary(godot_bin, args.version_token, args.precision_token)
    write_github_env(godot_bin)
    print(f"GODOT_BIN={godot_bin}")


if __name__ == "__main__":
    main()
