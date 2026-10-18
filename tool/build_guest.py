#!/usr/bin/env python3
"""Build the Pages preview without mobile plugins or photo model assets.

Usage: python tool/build_guest.py --base-href /Thread_Outfit_Wardrobe_stylists/
The Flutter SDK must be on PATH, or supplied with --flutter. The full app's
pubspec and lockfile are never modified. Only build/guest is published.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Iterator


DEFAULT_BASE_HREF = "/Thread_Outfit_Wardrobe_stylists/"
EXCLUDED_PACKAGES = ("image_picker", "shared_preferences", "tflite_flutter")


def validate_base_href(value: str) -> str:
    """Accept an absolute URL path, never a URL or shell-sensitive argument."""
    if (
        not re.fullmatch(r"/(?:[A-Za-z0-9._~-]+/)*", value)
        or any(segment in (".", "..") for segment in value.split("/"))
    ):
        raise argparse.ArgumentTypeError(
            "Base href must start and end with '/', with ordinary path segments "
            "only (for example /Thread_Outfit_Wardrobe_stylists/)."
        )
    return value


def reduced_pubspec(source: str) -> str:
    """Remove known mobile dependency blocks and model assets, preserving fonts.

    This intentionally handles this repository's ordinary indented pubspec
    format without adding a YAML tool dependency to the publishing workflow.
    Unexpected appearances of excluded packages fail closed below.
    """
    lines = source.splitlines()
    result: list[str] = []
    skipping_dependency = False
    for line in lines:
        if skipping_dependency:
            if not line.strip() or line.startswith("    "):
                continue
            skipping_dependency = False
        package = re.match(r"^  ([a-z_]+):", line)
        if package and package.group(1) in EXCLUDED_PACKAGES:
            skipping_dependency = True
            continue
        if re.match(r"^\s+-\s+['\"]?assets/models(?:/|['\"]?\s*$)", line):
            continue
        if line.startswith("description:"):
            line = "description: Session-only public Thread outfit preview."
        result.append(line)
    reduced = "\n".join(result) + "\n"
    for name in EXCLUDED_PACKAGES:
        if re.search(rf"^\s*{re.escape(name)}\s*:", reduced, re.MULTILINE):
            raise ValueError(f"Could not safely remove dependency {name}.")
    if "assets/models" in reduced:
        raise ValueError("The guest manifest must not reference model assets.")
    for required in ("name: thread_style", "assets/fonts/LICENSE.txt", "fonts:"):
        if required not in reduced:
            raise ValueError(f"Unexpected pubspec format: missing {required}.")
    return reduced


def guest_html(source: str) -> str:
    result = re.sub(
        r"\s*<script\b[^>]*\bsrc\s*=\s*['\"]vision/[^'\"]*['\"][^>]*>\s*</script>",
        "",
        source,
        flags=re.IGNORECASE,
    )
    result = re.sub(
        r'<meta name="description" content="[^"]*">',
        '<meta name="description" content="Try Thread: shirt color, pants, shoes '
        'and layering suggestions for your plans. No account or saved profile.">',
        result,
    )
    result = re.sub(r"<title>.*?</title>", "<title>Try Thread · Outfit ideas</title>", result)
    result = result.replace(
        "Putting your style studio together…", "Finding your next outfit…"
    )
    if "vision/" in result or "$FLUTTER_BASE_HREF" not in result:
        raise ValueError("Unexpected web index: vision loader or base placeholder remains invalid.")
    return result


def _is_link(path: Path) -> bool:
    return path.is_symlink() or getattr(path, "is_junction", lambda: False)()


def build_root(repo: Path) -> Path:
    repo = repo.resolve(strict=True)
    directory = repo / "build"
    if _is_link(directory) or directory.resolve() != directory:
        raise ValueError("Refusing a redirected build directory.")
    directory.mkdir(exist_ok=True)
    return directory


def checked_build_child(repo: Path, path: Path) -> Path:
    """Restrict mutations to real direct children of this project's build/."""
    root = build_root(repo)
    target = path.absolute()
    if (
        target.parent != root
        or target.name in ("", ".", "..")
        or _is_link(target)
        or target.resolve().parent != root
    ):
        raise ValueError(f"Refusing unsafe build target: {path}")
    return target


def remove_build_tree(repo: Path, path: Path) -> None:
    target = checked_build_child(repo, path)
    if target.exists():
        if not target.is_dir():
            raise ValueError(f"Expected a build directory: {target}")
        shutil.rmtree(target)


@contextlib.contextmanager
def temporary_build_directory(repo: Path, prefix: str) -> Iterator[Path]:
    directory = Path(tempfile.mkdtemp(prefix=prefix, dir=build_root(repo)))
    try:
        yield checked_build_child(repo, directory)
    finally:
        remove_build_tree(repo, directory)


def _check_no_links(directory: Path, *, exclude_vision: bool = False) -> None:
    if _is_link(directory) or not directory.is_dir():
        raise ValueError(f"Expected a regular source directory: {directory}")
    for current, dirs, files in os.walk(directory, followlinks=False):
        if exclude_vision and Path(current) == directory:
            dirs[:] = [item for item in dirs if item != "vision"]
        for name in dirs + files:
            path = Path(current) / name
            if _is_link(path):
                raise ValueError(f"Refusing a linked build input or artifact: {path}")


def stage_project(repo: Path, staging: Path) -> None:
    repo = repo.resolve(strict=True)
    staging = checked_build_child(repo, staging)
    if not staging.is_dir() or any(staging.iterdir()):
        raise ValueError("Guest staging must be an empty build directory.")
    for relative in ("lib", "assets/fonts", "web"):
        source = repo / relative
        _check_no_links(source, exclude_vision=relative == "web")
        shutil.copytree(
            source,
            staging / relative,
            ignore=(
                lambda directory, names: ["vision"]
                if Path(directory) == repo / "web" and "vision" in names
                else []
            ),
        )
    (staging / "pubspec.yaml").write_text(
        reduced_pubspec((repo / "pubspec.yaml").read_text(encoding="utf-8")),
        encoding="utf-8",
    )
    shutil.copy2(repo / "pubspec.lock", staging / "pubspec.lock")
    index = staging / "web/index.html"
    index.write_text(guest_html(index.read_text(encoding="utf-8")), encoding="utf-8")
    manifest_path = staging / "web/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest.update(
        name="Try Thread",
        short_name="Thread",
        description="Session-only outfit color and layering suggestions.",
        start_url=".",
        scope=".",
        display="browser",
    )
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def verify_dependencies(staging: Path) -> None:
    config = json.loads(
        (staging / ".dart_tool/package_config.json").read_text(encoding="utf-8")
    )
    forbidden = [
        entry["name"]
        for entry in config["packages"]
        if any(
            entry["name"] == package or entry["name"].startswith(package + "_")
            for package in EXCLUDED_PACKAGES
        )
    ]
    if forbidden:
        raise ValueError("Guest still includes mobile plugins: " + ", ".join(forbidden))


def verify_artifact(artifact: Path, base_href: str) -> None:
    _check_no_links(artifact)
    for required in ("index.html", "main.dart.js", "flutter_bootstrap.js", "data/trends.json"):
        if not (artifact / required).is_file():
            raise ValueError(f"Incomplete guest build: missing {required}.")
    for path in artifact.rglob("*"):
        relative = path.relative_to(artifact)
        if (
            "vision" in relative.parts
            or "models" in relative.parts
            or path.suffix.lower() in (".tflite", ".task")
        ):
            raise ValueError(f"Photo model unexpectedly included in guest build: {relative}")
    index = (artifact / "index.html").read_text(encoding="utf-8")
    if "vision/" in index or f'<base href="{base_href}">' not in index:
        raise ValueError("Guest index has an incorrect base href or a vision loader.")


def publish_artifact(repo: Path, artifact: Path, base_href: str) -> Path:
    """Preserve the previous guest build until its replacement is complete."""
    verify_artifact(artifact, base_href)
    destination = checked_build_child(repo, build_root(repo) / "guest")
    if destination.exists() and not destination.is_dir():
        raise ValueError("build/guest already exists and is not a directory.")
    with temporary_build_directory(repo, ".guest-publish-") as publishing:
        shutil.copytree(artifact, publishing, dirs_exist_ok=True)
        (publishing / ".nojekyll").touch()
        verify_artifact(publishing, base_href)
        backup = Path(tempfile.mkdtemp(prefix=".guest-backup-", dir=build_root(repo)))
        remove_build_tree(repo, backup)
        had_previous = destination.exists()
        if had_previous:
            destination.rename(backup)
        try:
            publishing.rename(destination)
        except OSError:
            if had_previous and not destination.exists():
                try:
                    backup.rename(destination)
                except OSError as error:
                    raise OSError(
                        f"Could not restore the previous preview; it is preserved at {backup}"
                    ) from error
            # If another process occupied the destination, retain the backup.
            raise
        else:
            remove_build_tree(repo, backup)
    return destination


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-href", type=validate_base_href, default=DEFAULT_BASE_HREF)
    parser.add_argument("--flutter", default="flutter", help="Flutter executable or path")
    args = parser.parse_args(argv)
    repo = Path(__file__).resolve().parent.parent
    flutter = shutil.which(args.flutter)
    if flutter is None:
        parser.error("Flutter was not found. Put it on PATH or pass --flutter.")
    try:
        with temporary_build_directory(repo, ".guest-stage-") as staging:
            stage_project(repo, staging)
            print("Resolving the isolated guest dependencies…", flush=True)
            subprocess.run([flutter, "pub", "get"], cwd=staging, check=True)
            verify_dependencies(staging)
            print("Building the public guest preview…", flush=True)
            subprocess.run(
                [
                    flutter,
                    "build",
                    "web",
                    "--target=lib/main_guest.dart",
                    "--release",
                    "--no-pub",
                    "--no-web-resources-cdn",
                    "--pwa-strategy=none",
                    f"--base-href={args.base_href}",
                ],
                cwd=staging,
                check=True,
            )
            destination = publish_artifact(repo, staging / "build/web", args.base_href)
            print(f"Guest preview ready: {destination}", flush=True)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Guest build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
