import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("release_manifest.py")
SPEC = importlib.util.spec_from_file_location("release_manifest", SCRIPT)
assert SPEC and SPEC.loader
release = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release
SPEC.loader.exec_module(release)


class ReleaseManifestTests(unittest.TestCase):
    def test_release_id_is_deterministic(self):
        spec = release.ReleaseSpec(3, "1.2.3", "1.2.3-internal.4", 4, "internal", 8)
        commit = "a" * 40
        self.assertEqual(release.release_id(spec, commit), f"1.2.3-internal.4-g{commit}")
        self.assertEqual(release.release_id(spec, commit), release.release_id(spec, commit))

    def test_internal_versions_follow_semantic_versioning(self):
        self.assertEqual(
            release.client_version_for_build("0.6.0", 23, "internal"),
            "0.6.0-internal.23",
        )
        self.assertEqual(
            release.client_version_for_build("0.6.0", 23, "public"),
            "0.6.0",
        )
        for build in (0, 10_000):
            with self.subTest(build=build):
                with self.assertRaises(release.ManifestError):
                    release.client_version_for_build("0.6.0", build, "internal")
        for version in ("0.06.0", "0.6", "v0.6.0"):
            with self.subTest(version=version):
                with self.assertRaises(release.ManifestError):
                    release.client_version_for_build(version, 1, "internal")

    def test_bump_increments_build_and_can_change_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / release.SOURCE_MANIFEST).parent.mkdir(parents=True)
            (root / release.SOURCE_MANIFEST).write_text(
                json.dumps(
                    {
                        "schemaVersion": 3,
                        "productVersion": "1.2.3",
                        "clientVersion": "1.2.3-internal.4",
                        "buildNumber": 4,
                        "channel": "internal",
                        "helperProtocolVersion": 8,
                    }
                ),
                encoding="utf-8",
            )
            (root / release.SIGNING_XCCONFIG).parent.mkdir(parents=True)
            (root / release.SIGNING_XCCONFIG).write_text(
                '#include "ReleaseIdentity.generated.xcconfig"\n', encoding="utf-8"
            )
            (root / release.INFO_PLIST).parent.mkdir(parents=True)
            (root / release.INFO_PLIST).write_text(
                "".join(
                    f"<key>{key}</key>\n" for key in (
                        "CFBundleVersion",
                        "CovioClientVersion",
                        "CovioProductVersion",
                        "CovioReleaseChannel",
                        "CovioGitCommit",
                        "CovioReleaseId",
                        "CovioHelperProtocolVersion",
                    )
                )
                + "<string>$(CURRENT_PROJECT_VERSION)</string>\n"
                + "<key>CovioInstallTransactionVersion</key>\n<string>1</string>\n"
                + "<key>CovioHelperInstallMode</key>\n<string>legacy</string>\n",
                encoding="utf-8",
            )
            (root / release.PBXPROJ).parent.mkdir(parents=True)
            (root / release.PBXPROJ).write_text("// clean\n", encoding="utf-8")

            spec = release.bump_build(root, "2.0.0")

            self.assertEqual(spec.product_version, "2.0.0")
            self.assertEqual(spec.client_version, "2.0.0-internal.5")
            self.assertEqual(spec.build_number, 5)
            self.assertEqual(release.load_spec(root), spec)
            self.assertEqual(release.drift_errors(root), [])

    def test_drift_detects_stale_generated_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            path = root / release.SWIFT_OUT
            path.write_text("stale\n", encoding="utf-8")
            self.assertIn(
                f"generated file is stale: {release.SWIFT_OUT}",
                release.drift_errors(root),
            )

    def test_generation_includes_kotlin_product_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            outputs = release.expected_outputs(root)
            self.assertEqual(
                set(outputs),
                {
                    root / release.SWIFT_OUT,
                    root / release.XCCONFIG_OUT,
                    root / release.KOTLIN_OUT,
                },
            )
            kotlin = outputs[root / release.KOTLIN_OUT]
            self.assertIn("package com.covio.release", kotlin)
            self.assertIn('const val clientVersion = "1.2.3-internal.4"', kotlin)
            self.assertIn("const val buildNumber = 4", kotlin)

    def test_artifact_manifest_rejects_helper_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            helper = root / "helper"
            helper.write_bytes(b"helper-v1")
            default_dmg = root / "Covio-1.2.3-internal.4.dmg"
            default_dmg.write_bytes(b"default-dmg")
            spec = release.load_spec(root)
            manifest = release.artifact_manifest(spec, "b" * 40, helper, default_dmg)
            manifest_path = root / "release-manifest.json"
            release._write_json(manifest_path, manifest)
            release.verify_artifact(manifest_path, helper, root)
            helper.write_bytes(b"helper-v2")
            with self.assertRaises(release.ManifestError):
                release.verify_artifact(manifest_path, helper, root)

    def test_bundle_manifest_carries_identity_without_installer_records(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            helper = root / "helper"
            helper.write_bytes(b"helper-v1")
            spec = release.load_spec(root)
            manifest = release.bundle_manifest(spec, "b" * 40, helper)
            manifest_path = root / "bundle-release-manifest.json"
            release._write_json(manifest_path, manifest)
            release.verify_bundle_manifest(manifest_path, helper, spec)

            self.assertEqual(manifest["schemaVersion"], release.BUNDLE_SCHEMA_VERSION)
            self.assertNotIn("installers", manifest)
            self.assertNotIn("model", manifest)
            helper.write_bytes(b"helper-v2")
            with self.assertRaises(release.ManifestError):
                release.verify_bundle_manifest(manifest_path, helper, spec)

    def test_artifact_manifest_contains_release_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            helper = root / "helper"
            helper.write_bytes(b"helper")
            default_dmg = root / "Covio-1.2.3-internal.4.dmg"
            default_dmg.write_bytes(b"default-dmg")
            manifest = release.artifact_manifest(
                release.load_spec(root),
                "c" * 40,
                helper,
                default_dmg,
            )
            self.assertEqual(manifest["schemaVersion"], release.ARTIFACT_SCHEMA_VERSION)
            self.assertEqual(manifest["releaseId"], f"1.2.3-internal.4-g{'c' * 40}")
            self.assertEqual(manifest["helperSHA256"], release.sha256_file(helper))
            self.assertEqual(manifest["installers"]["default"]["name"], "Covio-1.2.3-internal.4.dmg")
            self.assertIsNone(manifest["installers"]["offline"])
            self.assertIsNone(manifest["model"])

    def test_offline_manifest_records_model_and_both_installers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            helper = root / "helper"
            helper.write_bytes(b"helper")
            default_dmg = root / "Covio-1.2.3-internal.4.dmg"
            default_dmg.write_bytes(b"default-dmg")
            offline_dmg = root / "Covio-Offline-1.2.3-internal.4.dmg"
            offline_dmg.write_bytes(b"offline-dmg")
            model_manifest = self._write_model_manifest(root)

            manifest = release.artifact_manifest(
                release.load_spec(root),
                "d" * 40,
                helper,
                default_dmg,
                offline_dmg,
                model_manifest,
            )
            manifest_path = root / "release-manifest.json"
            release._write_json(manifest_path, manifest)
            release.verify_artifact(manifest_path, helper, root)

            self.assertEqual(
                manifest["installers"]["offline"]["sha256"],
                release.sha256_file(offline_dmg),
            )
            self.assertEqual(manifest["model"]["revision"], "e" * 40)
            self.assertEqual(
                manifest["model"]["manifestSHA256"],
                release.sha256_file(model_manifest),
            )

    def test_offline_and_model_metadata_must_appear_together(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            helper = root / "helper"
            helper.write_bytes(b"helper")
            default_dmg = root / "Covio-1.2.3-internal.4.dmg"
            default_dmg.write_bytes(b"default-dmg")
            offline_dmg = root / "Covio-Offline-1.2.3-internal.4.dmg"
            offline_dmg.write_bytes(b"offline-dmg")
            model_manifest = self._write_model_manifest(root)
            spec = release.load_spec(root)

            with self.assertRaises(release.ManifestError):
                release.artifact_manifest(
                    spec,
                    "f" * 40,
                    helper,
                    default_dmg,
                    offline_dmg,
                    None,
                )
            with self.assertRaises(release.ManifestError):
                release.artifact_manifest(
                    spec,
                    "f" * 40,
                    helper,
                    default_dmg,
                    None,
                    model_manifest,
                )

    def test_installer_hash_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            helper = root / "helper"
            helper.write_bytes(b"helper")
            default_dmg = root / "Covio-1.2.3-internal.4.dmg"
            default_dmg.write_bytes(b"default-dmg")
            manifest = release.artifact_manifest(
                release.load_spec(root),
                "a" * 40,
                helper,
                default_dmg,
            )
            manifest_path = root / "release-manifest.json"
            release._write_json(manifest_path, manifest)
            default_dmg.write_bytes(b"changed")
            with self.assertRaises(release.ManifestError):
                release.verify_artifact(manifest_path, helper, root)

    def test_clean_worktree_is_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "tracked.txt").write_text("dirty\n", encoding="utf-8")
            with self.assertRaises(release.ManifestError):
                release.ensure_clean(root)
            subprocess.run(["git", "-C", str(root), "add", "tracked.txt"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(root),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ],
                check=True,
            )
            release.ensure_clean(root)

    def _write_fixture(self, root: pathlib.Path):
        (root / release.SOURCE_MANIFEST).parent.mkdir(parents=True)
        (root / release.SOURCE_MANIFEST).write_text(
            json.dumps(
                {
                    "schemaVersion": 3,
                    "productVersion": "1.2.3",
                    "clientVersion": "1.2.3-internal.4",
                    "buildNumber": 4,
                    "channel": "internal",
                    "helperProtocolVersion": 8,
                }
            ),
            encoding="utf-8",
        )
        (root / release.SIGNING_XCCONFIG).parent.mkdir(parents=True)
        (root / release.SIGNING_XCCONFIG).write_text(
            '#include "ReleaseIdentity.generated.xcconfig"\n', encoding="utf-8"
        )
        (root / release.INFO_PLIST).parent.mkdir(parents=True)
        (root / release.INFO_PLIST).write_text(
            "".join(
                f"<key>{key}</key>\n" for key in (
                    "CFBundleVersion",
                    "CovioClientVersion",
                    "CovioProductVersion",
                    "CovioReleaseChannel",
                    "CovioGitCommit",
                    "CovioReleaseId",
                    "CovioHelperProtocolVersion",
                )
            )
            + "<string>$(CURRENT_PROJECT_VERSION)</string>\n"
            + "<key>CovioInstallTransactionVersion</key>\n<string>1</string>\n"
            + "<key>CovioHelperInstallMode</key>\n<string>legacy</string>\n",
            encoding="utf-8",
        )
        (root / release.PBXPROJ).parent.mkdir(parents=True)
        (root / release.PBXPROJ).write_text("// clean\n", encoding="utf-8")
        release.write_generated(root)

    def _write_model_manifest(self, root: pathlib.Path) -> pathlib.Path:
        path = root / "model-manifest.json"
        path.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "tier": "2b",
                    "modelID": "example/model",
                    "revision": "e" * 40,
                    "displayName": "Example",
                    "runtimeDirectory": "Models/Example",
                    "license": "Apache-2.0",
                    "licenseFile": "LICENSE",
                    "noticeFile": "NOTICE",
                    "totalBytes": 1,
                    "files": [],
                }
            ),
            encoding="utf-8",
        )
        return path


if __name__ == "__main__":
    unittest.main()
