import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("release_pipeline.py")
SPEC = importlib.util.spec_from_file_location("release_pipeline", SCRIPT)
assert SPEC and SPEC.loader
pipeline = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = pipeline
SPEC.loader.exec_module(pipeline)


class ReleasePipelineTests(unittest.TestCase):
    commit = "a" * 40
    helper_hash = "b" * 64

    def setUp(self):
        self.source = pipeline.release.ReleaseSpec(3, "1.2.3", "1.2.3-internal.4", 4, "internal", 8)
        self.artifact = {
            "schemaVersion": 3,
            "releaseId": f"1.2.3-internal.4-g{self.commit}",
            "productVersion": "1.2.3",
            "clientVersion": "1.2.3-internal.4",
            "buildNumber": 4,
            "gitCommit": self.commit,
            "helperProtocolVersion": 8,
            "helperSHA256": self.helper_hash,
            "channel": "internal",
        }
        self.app_info = {
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "4",
            "CovioClientVersion": "1.2.3-internal.4",
            "CovioProductVersion": "1.2.3",
            "CovioReleaseId": self.artifact["releaseId"],
            "CovioGitCommit": self.commit,
            "CovioHelperProtocolVersion": "8",
            "CovioReleaseChannel": "internal",
        }
        self.helper = {
            "releaseId": self.artifact["releaseId"],
            "clientVersion": "1.2.3-internal.4",
            "productVersion": "1.2.3",
            "buildNumber": "4",
            "gitCommit": self.commit,
            "protocolVersion": "8",
            "helperSHA256": self.helper_hash,
            "channel": "internal",
        }

    def test_matching_identity_has_no_errors(self):
        self.assertEqual(
            pipeline.identity_errors(
                self.source,
                self.artifact,
                self.app_info,
                self.helper,
                self.helper_hash,
            ),
            [],
        )

    def test_release_id_version_protocol_and_hash_mismatches_fail(self):
        cases = [
            (self.artifact | {"releaseId": "wrong"}, {}, {}, self.helper_hash),
            (self.artifact | {"productVersion": "9.9.9"}, {}, {}, self.helper_hash),
            (self.artifact | {"helperProtocolVersion": 9}, {}, {}, self.helper_hash),
            (self.artifact, {}, {}, "c" * 64),
            (self.artifact, {"CFBundleVersion": "5"}, {}, self.helper_hash),
            (self.artifact, {}, {"gitCommit": "d" * 40}, self.helper_hash),
        ]
        for artifact, app_override, helper_override, actual_hash in cases:
            app = self.app_info | app_override
            helper = self.helper | helper_override
            with self.subTest(artifact=artifact, app=app_override, helper=helper_override):
                self.assertNotEqual(
                    pipeline.identity_errors(
                        self.source,
                        artifact,
                        app,
                        helper,
                        actual_hash,
                    ),
                    [],
                )

    def test_architecture_requires_arm64_for_both_binaries(self):
        self.assertEqual(pipeline.architecture_errors("arm64", "arm64"), [])
        self.assertEqual(len(pipeline.architecture_errors("x86_64", "arm64")), 1)
        self.assertEqual(len(pipeline.architecture_errors("arm64", "x86_64")), 1)

    def test_public_signature_requires_developer_id_runtime_and_installer(self):
        app = "Authority=Developer ID Application: Covio\nTeamIdentifier=TEAM\nflags=0x10000(runtime)"
        dmg = "Authority=Developer ID Application: Covio\nTeamIdentifier=TEAM"
        pkg = "Status: signed\nDeveloper ID Installer: Covio"
        self.assertEqual(pipeline.signature_errors(app, app, pkg, dmg, "public"), [])
        self.assertNotEqual(pipeline.signature_errors("Signature=adhoc", app, pkg, dmg, "public"), [])
        self.assertNotEqual(pipeline.signature_errors(app, app, "Status: unsigned", dmg, "public"), [])
        self.assertNotEqual(pipeline.signature_errors(app.replace("(runtime)", ""), app, pkg, dmg, "public"), [])
        self.assertNotEqual(pipeline.signature_errors(app, app, pkg, "Signature=adhoc", "public"), [])

    def test_internal_package_signing_omits_hardened_runtime(self):
        for name in (
            "package-macos-swift.sh",
            "package-macos-offline-swift.sh",
        ):
            script = SCRIPT.with_name(name).read_text(encoding="utf-8")
            with self.subTest(script=name):
                self.assertEqual(script.count("--options runtime"), 1)
                self.assertIn("release_codesign()", script)
                self.assertIn('if [[ "$CHANNEL" == "public" ]]; then', script)
                self.assertNotIn("SIGN_RUNTIME_FLAGS", script)

    def test_macos_release_strips_symbols_from_the_app_target(self):
        project = (SCRIPT.parent.parent / "macosApp" / "Covio.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        marker = "C0000000000000000000001B /* Release */ = {"
        start = project.index(marker)
        end = project.index("name = Release;", start)
        target_release = project[start:end]
        self.assertIn("COPY_PHASE_STRIP = YES;", target_release)
        self.assertIn("DEPLOYMENT_POSTPROCESSING = YES;", target_release)
        self.assertIn("STRIP_INSTALLED_PRODUCT = YES;", target_release)
        self.assertIn("STRIP_STYLE = all;", target_release)
        self.assertEqual(project.count("STRIP_INSTALLED_PRODUCT = YES;"), 1)
        self.assertEqual(project.count("STRIP_STYLE = all;"), 1)

    def test_release_package_uses_shared_package_cache_without_kmp(self):
        script = SCRIPT.with_name("package-macos-swift.sh").read_text(encoding="utf-8")
        self.assertIn('source "$ROOT/scripts/release-cache.sh"', script)
        self.assertIn('DERIVED_DATA="$(release_derived_data_path "$ROOT")', script)
        self.assertIn('SOURCE_PACKAGES_DIR="$(release_source_packages_path "$ROOT")', script)
        self.assertIn('-clonedSourcePackagesDirPath', script)
        self.assertIn('-resolvePackageDependencies', script)
        self.assertIn('phase_done "package resolve"', script)
        self.assertNotIn('COVIO_RELEASE_KMP_CACHE_DIR', script)
        self.assertNotIn('build-kmp-framework', script)
        self.assertIn("find \"$APP_IMAGE\" -name 'kmpDomain.framework'", script)

    def test_release_cli_and_package_use_the_same_cache_resolver(self):
        cli = SCRIPT.with_name("covio").read_text(encoding="utf-8")
        self.assertIn('source "$ROOT/scripts/release-cache.sh"', cli)
        self.assertIn('RELEASE_DERIVED_DATA="$(release_derived_data_path "$ROOT")', cli)

    def test_internal_signature_allows_adhoc_without_stable_requirement(self):
        self.assertEqual(
            pipeline.signature_errors("Signature=adhoc", "Signature=adhoc", "", "", "internal"),
            [],
        )

    def test_internal_stable_signature_requires_matching_certificate(self):
        app = "Authority=Covio Dev\nTeamIdentifier=not set"
        other = "Authority=Another Dev Certificate\nTeamIdentifier=not set"
        self.assertEqual(
            pipeline.signature_errors(
                app,
                app,
                "",
                "",
                "internal",
                require_stable_signing=True,
            ),
            [],
        )
        self.assertIn(
            "app is signed ad-hoc",
            pipeline.signature_errors(
                "Signature=adhoc",
                app,
                "",
                "",
                "internal",
                require_stable_signing=True,
            ),
        )
        self.assertIn(
            "app and helper use different signing identities",
            pipeline.signature_errors(
                app,
                other,
                "",
                "",
                "internal",
                require_stable_signing=True,
            ),
        )

    def test_public_notarization_requires_every_ticket_and_gatekeeper_check(self):
        ok = pipeline.CommandResult(0, "accepted")
        failed = pipeline.CommandResult(1, "rejected")
        self.assertEqual(
            pipeline.notarization_errors("public", ok, ok, ok, ok, ok),
            [],
        )
        errors = pipeline.notarization_errors("public", ok, failed, ok, ok, ok)
        self.assertEqual(len(errors), 1)
        self.assertIn("dmg staple", errors[0])

    def test_checksums_are_deterministic_and_detect_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_release_assets(root)
            first = pipeline.write_checksums(root, "1.2.3-internal.4").read_text(encoding="utf-8")
            second = pipeline.write_checksums(root, "1.2.3-internal.4").read_text(encoding="utf-8")
            self.assertEqual(first, second)
            pipeline.verify_checksums(root, "1.2.3-internal.4")
            (root / "Covio-1.2.3-internal.4.dmg").write_bytes(b"changed")
            with self.assertRaises(pipeline.ReleaseVerificationError):
                pipeline.verify_checksums(root, "1.2.3-internal.4")

    def test_checksum_asset_set_is_complete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_release_assets(root)
            pipeline.write_checksums(root, "1.2.3-internal.4")
            (root / "Covio-1.2.3-internal.4.pkg").unlink()
            with self.assertRaises(pipeline.ReleaseVerificationError):
                pipeline.verify_checksums(root, "1.2.3-internal.4")

    def test_offline_installer_is_included_in_checksums(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_release_assets(root, offline=True)
            checksums = pipeline.write_checksums(root, "1.2.3-internal.4").read_text(encoding="utf-8")
            self.assertIn("Covio-Offline-1.2.3-internal.4.dmg", checksums)
            pipeline.verify_checksums(root, "1.2.3-internal.4")

    def test_unified_platform_assets_are_included_in_checksums(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_release_assets(root, unified=True)
            names = pipeline.release_asset_names(root, "1.2.3-internal.4")
            self.assertIn("ios-package.json", names)
            self.assertIn("Covio-1.2.3-internal.4-ios-arm64.ipa", names)
            self.assertIn("compose-package.json", names)
            self.assertIn("Covio-1.2.3-internal.4-windows-x64-portable.zip", names)
            self.assertIn("Covio-1.2.3-internal.4-windows-x64.msi", names)
            checksums = pipeline.write_checksums(root, "1.2.3-internal.4").read_text(encoding="utf-8")
            self.assertIn("Covio-1.2.3-internal.4-ios-arm64.ipa", checksums)
            pipeline.verify_checksums(root, "1.2.3-internal.4")

    def test_model_metadata_mismatch_is_rejected(self):
        manifest = {
            "tier": "2b",
            "modelID": "example/model",
            "revision": "a" * 40,
            "runtimeDirectory": "Models/Example",
            "license": "Apache-2.0",
            "totalBytes": 1,
        }
        self.assertEqual(pipeline.model_metadata_errors(manifest, manifest), [])
        self.assertNotEqual(
            pipeline.model_metadata_errors(manifest | {"revision": "b" * 40}, manifest),
            [],
        )

    def test_model_weights_are_detected_inside_an_app(self):
        with tempfile.TemporaryDirectory() as directory:
            app = pathlib.Path(directory) / "Covio.app"
            weights = app / "Contents" / "Resources" / "Models" / "Example" / "model.safetensors"
            weights.parent.mkdir(parents=True)
            weights.write_bytes(b"weights")
            self.assertEqual(pipeline.model_weight_paths(app), (weights,))

    def test_tags_use_the_canonical_semantic_version(self):
        public = self.source.__class__(3, "1.2.3", "1.2.3", 4, "public", 8)
        self.assertEqual(pipeline.release_tag(self.source), "v1.2.3-internal.4")
        self.assertEqual(pipeline.release_tag(public), "v1.2.3")

    def test_internal_release_never_becomes_latest(self):
        internal = pipeline.public_visibility("internal")
        public = pipeline.public_visibility("public")
        self.assertFalse(internal["isLatest"])
        self.assertTrue(internal["isPrerelease"])
        self.assertTrue(public["isLatest"])
        self.assertFalse(public["isPrerelease"])

    def test_promotion_requires_draft_and_paired_assets(self):
        evidence = {
            "tag": "v1.2.3-internal.4",
            "productVersion": "1.2.3",
            "clientVersion": "1.2.3-internal.4",
            "assets": {
                name: {"sha256": "a" * 64, "size": 1}
                for name in pipeline.expected_asset_names("1.2.3-internal.4")
            },
            "installers": {
                "default": {"name": "Covio-1.2.3-internal.4.dmg"},
                "offline": None,
            },
        }
        info = {"isDraft": True, "isPrerelease": True, "tagName": evidence["tag"]}
        self.assertEqual(pipeline.promotion_errors("internal", info, evidence), [])
        self.assertNotEqual(
            pipeline.promotion_errors("internal", info | {"isDraft": False}, evidence),
            [],
        )
        incomplete = evidence | {"assets": {"Covio-1.2.3-internal.4.dmg": {"sha256": "a" * 64, "size": 1}}}
        self.assertNotEqual(pipeline.promotion_errors("internal", info, incomplete), [])

    def test_release_notes_include_release_evidence_and_hashes(self):
        evidence = {
            "channel": "internal",
            "releaseId": f"1.2.3-internal.4-g{self.commit}",
            "productVersion": "1.2.3",
            "clientVersion": "1.2.3-internal.4",
            "buildNumber": 4,
            "gitCommit": self.commit,
            "helperProtocolVersion": 8,
            "helperSHA256": self.helper_hash,
            "tag": "v1.2.3-internal.4",
            "assets": {
                "Covio-1.2.3-internal.4.dmg": {"sha256": "c" * 64, "size": 123},
            },
            "verification": {
                "identity": "MATCH",
                "signatureKind": "adhoc",
                "notarized": False,
            },
        }
        notes = pipeline.render_notes(evidence, "# Notes")
        self.assertIn(evidence["releaseId"], notes)
        self.assertIn("c" * 64, notes)
        self.assertIn("# Notes", notes)

    def _write_release_assets(
        self,
        root: pathlib.Path,
        offline: bool = False,
        unified: bool = False,
    ) -> None:
        for name in pipeline.expected_asset_names("1.2.3-internal.4"):
            (root / name).write_bytes(name.encode("utf-8"))
        installers = {
            "default": {
                "name": "Covio-1.2.3-internal.4.dmg",
                "size": 1,
                "sha256": "1" * 64,
            },
            "offline": None,
        }
        model = None
        if offline:
            (root / "Covio-Offline-1.2.3-internal.4.dmg").write_bytes(b"offline")
            installers["offline"] = {
                "name": "Covio-Offline-1.2.3-internal.4.dmg",
                "size": 1,
                "sha256": "2" * 64,
            }
            model = {
                "tier": "2b",
                "modelID": "example/model",
                "revision": "a" * 40,
                "runtimeDirectory": "Models/Example",
                "license": "Apache-2.0",
                "totalBytes": 1,
                "manifestSHA256": "3" * 64,
            }
        manifest = {
            "schemaVersion": pipeline.release.ARTIFACT_SCHEMA_VERSION,
            "installers": installers,
            "model": model,
        }
        if unified:
            ios_name = "Covio-1.2.3-internal.4-ios-arm64.ipa"
            portable_name = "Covio-1.2.3-internal.4-windows-x64-portable.zip"
            msi_name = "Covio-1.2.3-internal.4-windows-x64.msi"
            for name in ("ios-package.json", ios_name, "compose-package.json", portable_name, msi_name):
                (root / name).write_bytes(name.encode("utf-8"))
            manifest["requiredPlatforms"] = ["macos", "windows", "ios"]
            manifest["platforms"] = {
                "ios": {"artifact": {"name": ios_name}},
                "windows": {
                    "artifacts": {
                        "portable": {"name": portable_name},
                        "msi": {"name": msi_name},
                    }
                },
            }
        (root / "release-manifest.json").write_text(
            json.dumps(manifest),
            encoding="utf-8",
        )


if __name__ == "__main__":
    unittest.main()
