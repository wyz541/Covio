#!/usr/bin/env python3
"""Tests for signed update manifest generation."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("update_manifest.py")
SPEC = importlib.util.spec_from_file_location("update_manifest", SCRIPT)
assert SPEC and SPEC.loader
update_manifest = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = update_manifest
SPEC.loader.exec_module(update_manifest)


class UpdateManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="covio-update-manifest-")
        cls.root = pathlib.Path(cls.temporary.name)
        cls.signer_dir = cls.root / "signer"
        repo_root = pathlib.Path(__file__).resolve().parent.parent
        subprocess.run(
            [
                "bash",
                str(repo_root / "scripts/build-update-signature-tool.sh"),
                str(cls.signer_dir),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.signer = cls.signer_dir / "CovioUpdateSigner"
        cls.private_key = cls.root / "private.json"
        cls.public_key = cls.root / "public.json"
        subprocess.run(
            [
                str(cls.signer),
                "keygen",
                "--key-id",
                "covio-internal-test",
                "--private-key",
                str(cls.private_key),
                "--public-key",
                str(cls.public_key),
            ],
            check=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_build_number_mapping(self):
        self.assertEqual(update_manifest.client_version_for_build(19), "0.0.1.9")
        self.assertEqual(update_manifest.client_version_for_build(20), "0.0.2.0")

    def test_generate_and_verify_manifest(self):
        paths = self._generate()
        manifest = json.loads(paths["manifest"].read_text(encoding="utf-8"))
        signature = json.loads(paths["signature"].read_text(encoding="utf-8"))
        self.assertEqual(manifest["buildNumber"], 20)
        self.assertEqual(manifest["clientVersion"], "0.0.2.0")
        self.assertEqual(manifest["releaseId"], f"0.0.2.0-g{'a' * 40}")
        self.assertEqual(signature["schemaVersion"], 1)
        self.assertEqual(
            signature["manifestSHA256"],
            hashlib.sha256(paths["manifest"].read_bytes()).hexdigest(),
        )
        subprocess.run(
            [
                str(self.signer),
                "verify",
                "--public-key",
                str(self.public_key),
                "--manifest",
                str(paths["manifest"]),
                "--signature",
                str(paths["signature"]),
            ],
            check=True,
        )

    def test_tampered_manifest_fails_verification(self):
        paths = self._generate()
        original = paths["manifest"].read_bytes()
        paths["manifest"].write_bytes(original + b" ")
        result = subprocess.run(
            [
                str(self.signer),
                "verify",
                "--public-key",
                str(self.public_key),
                "--manifest",
                str(paths["manifest"]),
                "--signature",
                str(paths["signature"]),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)

    def test_archive_name_must_match_client_version(self):
        fixture = self._fixture("wrong.zip")
        with self.assertRaises(update_manifest.UpdateManifestError):
            update_manifest.generate_manifest(
                release_manifest=fixture["release_manifest"],
                archive=fixture["archive"],
                app_executable=fixture["app"],
                helper=fixture["helper"],
                updater=fixture["updater"],
                git_commit="a" * 40,
                key_id="covio-internal-test",
                signer=self.signer,
                private_key=self.private_key,
                output_dir=self.root / "wrong-output",
            )

    def test_public_channel_is_rejected(self):
        fixture = self._fixture("CovioUpdate-0.0.2.0.zip")
        release = json.loads(fixture["release_manifest"].read_text(encoding="utf-8"))
        release["channel"] = "public"
        fixture["release_manifest"].write_text(
            json.dumps(release),
            encoding="utf-8",
        )
        with self.assertRaises(update_manifest.UpdateManifestError):
            update_manifest.generate_manifest(
                release_manifest=fixture["release_manifest"],
                archive=fixture["archive"],
                app_executable=fixture["app"],
                helper=fixture["helper"],
                updater=fixture["updater"],
                git_commit="a" * 40,
                key_id="covio-internal-test",
                signer=self.signer,
                private_key=self.private_key,
                output_dir=self.root / "public-output",
            )

    def test_published_at_requires_a_time_zone(self):
        fixture = self._fixture("CovioUpdate-0.0.2.0.zip")
        with self.assertRaises(update_manifest.UpdateManifestError):
            update_manifest.generate_manifest(
                release_manifest=fixture["release_manifest"],
                archive=fixture["archive"],
                app_executable=fixture["app"],
                helper=fixture["helper"],
                updater=fixture["updater"],
                git_commit="a" * 40,
                key_id="covio-internal-test",
                signer=self.signer,
                private_key=self.private_key,
                output_dir=self.root / "naive-time-output",
                published_at="2026-11-04T00:00:00",
            )

    def test_private_key_is_owner_only(self):
        mode = self.private_key.stat().st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def _generate(self) -> dict[str, pathlib.Path]:
        fixture = self._fixture("CovioUpdate-0.0.2.0.zip")
        output = self.root / f"output-{self._testMethodName}"
        manifest, signature = update_manifest.generate_manifest(
            release_manifest=fixture["release_manifest"],
            archive=fixture["archive"],
            app_executable=fixture["app"],
            helper=fixture["helper"],
            updater=fixture["updater"],
            git_commit="a" * 40,
            key_id="covio-internal-test",
            signer=self.signer,
            private_key=self.private_key,
            output_dir=output,
            published_at="2026-11-04T00:00:00Z",
        )
        return {
            "manifest": manifest,
            "signature": signature,
            **fixture,
        }

    def _fixture(self, archive_name: str) -> dict[str, pathlib.Path]:
        directory = pathlib.Path(tempfile.mkdtemp(prefix="fixture-", dir=self.root))
        release_manifest = directory / "release.json"
        release_manifest.write_text(
            json.dumps(
                {
                    "schemaVersion": 2,
                    "productVersion": "0.6.0",
                    "clientVersion": "0.0.2.0",
                    "buildNumber": 20,
                    "channel": "internal",
                    "helperProtocolVersion": 10,
                }
            ),
            encoding="utf-8",
        )
        app = directory / "Covio"
        helper = directory / "CovioHelper"
        updater = directory / "CovioUpdater"
        archive = directory / archive_name
        for path, value in (
            (app, b"app"),
            (helper, b"helper"),
            (updater, b"updater"),
            (archive, b"archive"),
        ):
            path.write_bytes(value)
        return {
            "release_manifest": release_manifest,
            "app": app,
            "helper": helper,
            "updater": updater,
            "archive": archive,
        }


if __name__ == "__main__":
    unittest.main()
