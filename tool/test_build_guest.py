"""Guest packaging tests use temporary projects and never run Flutter."""

import argparse
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import build_guest


PUBSPEC = """name: thread_style
description: Full mobile app.
dependencies:
  flutter:
    sdk: flutter
  image_picker: ^1.2.0
  shared_preferences:
    version: ^2.5.3
  http: ^1.6.0
  tflite_flutter: ^0.12.1
  url_launcher: ^6.3.2
flutter:
  assets:
    - assets/fonts/LICENSE.txt
    - assets/models/movenet_lightning.tflite
    - assets/models/LICENSE.txt
  fonts:
    - family: ThreadSans
      fonts:
        - asset: assets/fonts/Roboto-Regular.ttf
"""
HTML = """<html><head><base href="$FLUTTER_BASE_HREF">
<title>Thread</title><meta name="description" content="Full app">
</head><body><script src="vision/thread_pose.js"></script>
<script src="flutter_bootstrap.js" async></script></body></html>"""


class GuestBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name).resolve() / "repo"
        self.repo.mkdir()

    def _project(self):
        for relative in ("lib", "assets/fonts", "assets/models", "web/vision", "web/data"):
            (self.repo / relative).mkdir(parents=True, exist_ok=True)
        (self.repo / "pubspec.yaml").write_text(PUBSPEC, encoding="utf-8")
        (self.repo / "pubspec.lock").write_text("packages: {}\n", encoding="utf-8")
        (self.repo / "lib/main_guest.dart").write_text("void main() {}\n", encoding="utf-8")
        (self.repo / "assets/fonts/LICENSE.txt").write_text("font license", encoding="utf-8")
        (self.repo / "assets/models/model.tflite").write_bytes(b"large model")
        (self.repo / "web/index.html").write_text(HTML, encoding="utf-8")
        (self.repo / "web/vision/thread_pose.js").write_text("photo analyzer", encoding="utf-8")
        (self.repo / "web/data/trends.json").write_text("{}", encoding="utf-8")
        (self.repo / "web/manifest.json").write_text('{"name":"Thread"}', encoding="utf-8")

    def _artifact(self, directory):
        directory.mkdir(parents=True)
        (directory / "index.html").write_text('<base href="/Thread/">', encoding="utf-8")
        (directory / "main.dart.js").write_text("guest", encoding="utf-8")
        (directory / "flutter_bootstrap.js").write_text("bootstrap", encoding="utf-8")
        (directory / "data").mkdir()
        (directory / "data/trends.json").write_text("{}", encoding="utf-8")

    def test_base_href_accepts_project_paths_and_rejects_urls_traversal_and_injection(self):
        for value in ("/", "/Thread_Outfit_Wardrobe_stylists/", "/preview/v1.0/"):
            self.assertEqual(build_guest.validate_base_href(value), value)
        for value in ("https://x.test/", "/../", "/a/./", "/a//b/", "thread/", "/x", "/%2e%2e/", "/x&whoami/", "/x\"/"):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                build_guest.validate_base_href(value)

    def test_staging_excludes_models_and_plugins_without_touching_source(self):
        self._project()
        before = {path: path.read_bytes() for path in self.repo.rglob("*") if path.is_file()}
        with build_guest.temporary_build_directory(self.repo, ".guest-stage-") as stage:
            build_guest.stage_project(self.repo, stage)
            reduced = (stage / "pubspec.yaml").read_text(encoding="utf-8")
            for forbidden in (*build_guest.EXCLUDED_PACKAGES, "assets/models", "version: ^2.5.3"):
                self.assertNotIn(forbidden, reduced)
            self.assertIn("http: ^1.6.0", reduced)
            self.assertIn("Roboto-Regular.ttf", reduced)
            self.assertFalse((stage / "assets/models").exists())
            self.assertFalse((stage / "web/vision").exists())
            self.assertTrue((stage / "web/data/trends.json").is_file())
            self.assertNotIn("vision/", (stage / "web/index.html").read_text(encoding="utf-8"))
            manifest = json.loads((stage / "web/manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["start_url"], ".")
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content)

    def test_dependency_verification_rejects_transitive_storage_plugin(self):
        with build_guest.temporary_build_directory(self.repo, ".guest-stage-") as stage:
            (stage / ".dart_tool").mkdir()
            config = stage / ".dart_tool/package_config.json"
            config.write_text('{"packages":[{"name":"http"},{"name":"url_launcher_web"}]}', encoding="utf-8")
            build_guest.verify_dependencies(stage)
            config.write_text('{"packages":[{"name":"shared_preferences_web"}]}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "shared_preferences_web"):
                build_guest.verify_dependencies(stage)

    def test_safe_mutation_rejects_outside_parent_and_project_build_root(self):
        root = build_guest.build_root(self.repo)
        for path in (self.repo, root, self.repo / "outside", root / ".." / "outside", root / "guest/nested"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                build_guest.remove_build_tree(self.repo, path)

    def test_existing_preview_survives_incomplete_or_model_bearing_build(self):
        destination = build_guest.build_root(self.repo) / "guest"
        destination.mkdir()
        previous = destination / "keep.txt"
        previous.write_text("previous build", encoding="utf-8")
        artifact = self.repo / "artifact"
        artifact.mkdir()
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            build_guest.publish_artifact(self.repo, artifact, "/Thread/")
        artifact.rmdir()
        self._artifact(artifact)
        (artifact / "model.tflite").write_bytes(b"model")
        with self.assertRaisesRegex(ValueError, "Photo model"):
            build_guest.publish_artifact(self.repo, artifact, "/Thread/")
        self.assertEqual(previous.read_text(encoding="utf-8"), "previous build")

    def test_successful_publish_replaces_only_guest_directory(self):
        root = build_guest.build_root(self.repo)
        existing = root / "guest"
        existing.mkdir()
        (existing / "old.txt").touch()
        (root / "other-build").mkdir()
        (root / "other-build/keep.txt").touch()
        artifact = self.repo / "artifact"
        self._artifact(artifact)
        result = build_guest.publish_artifact(self.repo, artifact, "/Thread/")
        self.assertEqual(result, existing)
        self.assertTrue((existing / "main.dart.js").is_file())
        self.assertTrue((existing / ".nojekyll").is_file())
        self.assertFalse((existing / "old.txt").exists())
        self.assertTrue((root / "other-build/keep.txt").is_file())
        self.assertEqual({path.name for path in root.iterdir()}, {"guest", "other-build"})

    def test_failed_publish_rename_restores_previous_preview(self):
        root = build_guest.build_root(self.repo)
        existing = root / "guest"
        existing.mkdir()
        (existing / "old.txt").touch()
        artifact = self.repo / "artifact"
        self._artifact(artifact)
        original_rename = Path.rename

        def fail_replacement(path, target):
            if path.name.startswith(".guest-publish-"):
                raise OSError("simulated rename failure")
            return original_rename(path, target)

        with mock.patch.object(Path, "rename", fail_replacement):
            with self.assertRaisesRegex(OSError, "simulated"):
                build_guest.publish_artifact(self.repo, artifact, "/Thread/")
        self.assertTrue((existing / "old.txt").is_file())

    def test_linked_destination_is_rejected_before_deletion(self):
        outside = self.repo / "outside"
        outside.mkdir()
        (outside / "keep.txt").touch()
        destination = build_guest.build_root(self.repo) / "guest"
        try:
            destination.symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("Creating symlinks is unavailable for this user.")
        with self.assertRaises(ValueError):
            build_guest.remove_build_tree(self.repo, destination)
        self.assertTrue((outside / "keep.txt").is_file())

    def test_failed_rollback_preserves_backup_for_recovery(self):
        root = build_guest.build_root(self.repo)
        existing = root / "guest"
        existing.mkdir()
        (existing / "old.txt").touch()
        artifact = self.repo / "artifact"
        self._artifact(artifact)
        original_rename = Path.rename

        def fail_publish_and_restore(path, target):
            if path.name.startswith((".guest-publish-", ".guest-backup-")):
                raise OSError("simulated locked directory")
            return original_rename(path, target)

        with mock.patch.object(Path, "rename", fail_publish_and_restore):
            with self.assertRaisesRegex(OSError, "preserved at"):
                build_guest.publish_artifact(self.repo, artifact, "/Thread/")
        backups = list(root.glob(".guest-backup-*"))
        self.assertEqual(len(backups), 1)
        self.assertTrue((backups[0] / "old.txt").is_file())


if __name__ == "__main__":
    unittest.main()
