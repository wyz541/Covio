#!/usr/bin/env python3
"""Build fail-closed evidence for a Covio release directory."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable


ROOT = pathlib.Path(__file__).resolve().parent.parent
RELEASE_SCRIPT = ROOT / "scripts" / "release_manifest.py"
SPEC = importlib.util.spec_from_file_location("release_manifest", RELEASE_SCRIPT)
assert SPEC and SPEC.loader
release = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release
SPEC.loader.exec_module(release)

SHA256 = re.compile(r"^[0-9a-f]{64}$")
CHECKSUM_LINE = re.compile(r"^([0-9a-f]{64})  ([^/\n]+)$")
PAYLOAD_SUFFIXES = (".app.zip", ".dmg", ".pkg")


class ReleaseVerificationError(Exception):
    pass


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    output: str


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ReleaseVerificationError(f"missing file: {path.name}") from error
    except json.JSONDecodeError as error:
        raise ReleaseVerificationError(f"invalid JSON in {path.name}: {error}") from error
    if not isinstance(value, dict):
        raise ReleaseVerificationError(f"{path.name} must contain a JSON object")
    return value


def read_plist(path: pathlib.Path) -> dict[str, Any]:
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
    except FileNotFoundError as error:
        raise ReleaseVerificationError(f"missing plist: {path}") from error
    except plistlib.InvalidFileException as error:
        raise ReleaseVerificationError(f"invalid plist: {path}") from error
    if not isinstance(value, dict):
        raise ReleaseVerificationError(f"plist must contain a dictionary: {path}")
    return value


def expected_asset_names(version: str) -> tuple[str, ...]:
    return (
        f"Covio-{version}.app.zip",
        f"Covio-{version}.dmg",
        f"Covio-{version}.pkg",
    )


def release_asset_names(directory: pathlib.Path, version: str) -> tuple[str, ...]:
    artifact = read_json(directory / "release-manifest.json")
    if artifact.get("schemaVersion") != release.ARTIFACT_SCHEMA_VERSION:
        raise ReleaseVerificationError(
            f"artifact manifest schemaVersion must be {release.ARTIFACT_SCHEMA_VERSION}"
        )
    default_name, offline_name = release.installer_names(artifact, version)
    names = [f"Covio-{version}.app.zip", default_name]
    if offline_name is not None:
        names.append(offline_name)
    names.extend((f"Covio-{version}.pkg", "release-manifest.json"))
    return tuple(names)


def release_tag(spec: release.ReleaseSpec) -> str:
    if spec.channel == "internal":
        return f"v{spec.client_version}-internal"
    return f"v{spec.client_version}"


def identity_errors(
    source: release.ReleaseSpec,
    artifact: dict[str, Any],
    app_info: dict[str, Any],
    helper: dict[str, Any],
    actual_helper_hash: str,
) -> list[str]:
    errors: list[str] = []
    commit = artifact.get("gitCommit")
    expected_release_id = None
    try:
        expected_release_id = release.release_id(source, commit) if isinstance(commit, str) else None
    except release.ManifestError:
        errors.append("artifact gitCommit is not a full lowercase SHA")

    expected = {
        "releaseId": expected_release_id,
        "productVersion": source.product_version,
        "clientVersion": source.client_version,
        "buildNumber": source.build_number,
        "gitCommit": commit,
        "helperProtocolVersion": source.helper_protocol_version,
        "channel": source.channel,
        "helperSHA256": actual_helper_hash,
    }
    artifact_fields = {
        "releaseId": artifact.get("releaseId"),
        "productVersion": artifact.get("productVersion"),
        "clientVersion": artifact.get("clientVersion"),
        "buildNumber": artifact.get("buildNumber"),
        "gitCommit": artifact.get("gitCommit"),
        "helperProtocolVersion": artifact.get("helperProtocolVersion"),
        "channel": artifact.get("channel"),
        "helperSHA256": artifact.get("helperSHA256"),
    }
    for key, value in expected.items():
        if artifact_fields[key] != value:
            errors.append(f"artifact {key} mismatch: {artifact_fields[key]!r} != {value!r}")

    app_expected = {
        "CFBundleShortVersionString": source.client_version,
        "CFBundleVersion": str(source.build_number),
        "CovioClientVersion": source.client_version,
        "CovioProductVersion": source.product_version,
        "CovioReleaseId": expected_release_id,
        "CovioGitCommit": commit,
        "CovioHelperProtocolVersion": str(source.helper_protocol_version),
        "CovioReleaseChannel": source.channel,
    }
    for key, value in app_expected.items():
        if app_info.get(key) != value:
            errors.append(f"app {key} mismatch: {app_info.get(key)!r} != {value!r}")

    helper_expected = {
        "releaseId": expected_release_id,
        "productVersion": source.product_version,
        "clientVersion": source.client_version,
        "buildNumber": str(source.build_number),
        "gitCommit": commit,
        "protocolVersion": str(source.helper_protocol_version),
        "channel": source.channel,
        "helperSHA256": actual_helper_hash,
    }
    for key, value in helper_expected.items():
        if helper.get(key) != value:
            errors.append(f"helper {key} mismatch: {helper.get(key)!r} != {value!r}")
    return errors


def architecture_errors(app_binary: str, helper_binary: str) -> list[str]:
    errors: list[str] = []
    if app_binary != "arm64":
        errors.append(f"app architecture must be arm64, got {app_binary!r}")
    if helper_binary != "arm64":
        errors.append(f"helper architecture must be arm64, got {helper_binary!r}")
    return errors


def model_weight_paths(app: pathlib.Path) -> tuple[pathlib.Path, ...]:
    root = app / "Contents" / "Resources" / "Models"
    if not root.is_dir():
        return ()
    return tuple(sorted(path for path in root.rglob("*.safetensors") if path.is_file()))


def model_metadata_errors(
    model_manifest: dict[str, Any],
    expected_model: dict[str, Any],
) -> list[str]:
    errors: list[str] = []
    for key in (
        "tier",
        "modelID",
        "revision",
        "runtimeDirectory",
        "license",
        "totalBytes",
    ):
        if model_manifest.get(key) != expected_model.get(key):
            errors.append(
                f"offline model {key} mismatch: "
                f"{model_manifest.get(key)!r} != {expected_model.get(key)!r}"
            )
    return errors


def signature_errors(
    app: str,
    helper: str,
    package: str,
    disk_image: str,
    channel: str,
    require_stable_signing: bool = False,
) -> list[str]:
    if channel == "internal":
        if not require_stable_signing:
            return []
        errors: list[str] = []
        authorities: dict[str, str | None] = {}
        for name, report in (("app", app), ("helper", helper)):
            authority = _signature_authority(report)
            authorities[name] = authority
            if re.search(r"^Signature=adhoc$", report, re.MULTILINE):
                errors.append(f"{name} is signed ad-hoc")
            elif authority is None:
                errors.append(f"{name} has no signing Authority")
        if authorities["app"] and authorities["app"] == authorities["helper"]:
            return errors
        if authorities["app"] and authorities["helper"]:
            errors.append("app and helper use different signing identities")
        return errors
    errors: list[str] = []
    for name, report in (("app", app), ("helper", helper)):
        if "Authority=Developer ID Application:" not in report:
            errors.append(f"{name} is not signed with Developer ID Application")
        if re.search(r"^TeamIdentifier=not set$", report, re.MULTILINE):
            errors.append(f"{name} has no TeamIdentifier")
        if "runtime" not in report:
            errors.append(f"{name} does not enable hardened runtime")
    if "Authority=Developer ID Application:" not in disk_image:
        errors.append("dmg is not signed with Developer ID Application")
    if re.search(r"^TeamIdentifier=not set$", disk_image, re.MULTILINE):
        errors.append("dmg has no TeamIdentifier")
    if "Developer ID Installer:" not in package or "Status: signed" not in package:
        errors.append("pkg is not signed with Developer ID Installer")
    return errors


def _signature_authority(report: str) -> str | None:
    match = re.search(r"^Authority=(.+)$", report, re.MULTILINE)
    return match.group(1).strip() if match else None


def notarization_errors(
    channel: str,
    app_staple: CommandResult,
    dmg_staple: CommandResult,
    pkg_staple: CommandResult,
    app_gatekeeper: CommandResult,
    pkg_gatekeeper: CommandResult,
) -> list[str]:
    if channel == "internal":
        return []
    errors: list[str] = []
    for name, result in (
        ("app staple", app_staple),
        ("dmg staple", dmg_staple),
        ("pkg staple", pkg_staple),
        ("app Gatekeeper", app_gatekeeper),
        ("pkg Gatekeeper", pkg_gatekeeper),
    ):
        if result.returncode != 0:
            errors.append(f"{name} failed: {result.output.strip()}")
    return errors


def checksum_text(directory: pathlib.Path, version: str) -> str:
    names = release_asset_names(directory, version)
    lines: list[str] = []
    for name in names:
        path = directory / name
        if not path.is_file():
            raise ReleaseVerificationError(f"missing release asset: {name}")
        lines.append(f"{sha256_file(path)}  {name}\n")
    return "".join(lines)


def write_checksums(directory: pathlib.Path, version: str) -> pathlib.Path:
    output = directory / "checksums.txt"
    output.write_text(checksum_text(directory, version), encoding="utf-8")
    return output


def verify_checksums(directory: pathlib.Path, version: str) -> pathlib.Path:
    path = directory / "checksums.txt"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError as error:
        raise ReleaseVerificationError("missing checksums.txt") from error
    expected_names = release_asset_names(directory, version)
    actual: dict[str, str] = {}
    for line in lines:
        match = CHECKSUM_LINE.fullmatch(line)
        if not match:
            raise ReleaseVerificationError(f"invalid checksum line: {line!r}")
        digest, name = match.groups()
        if name in actual:
            raise ReleaseVerificationError(f"duplicate checksum entry: {name}")
        actual[name] = digest
    if set(actual) != set(expected_names):
        missing = sorted(set(expected_names) - set(actual))
        extra = sorted(set(actual) - set(expected_names))
        raise ReleaseVerificationError(f"checksum asset set mismatch: missing={missing} extra={extra}")
    for name, digest in actual.items():
        artifact_path = directory / name
        if not artifact_path.is_file():
            raise ReleaseVerificationError(f"missing release asset: {name}")
        if sha256_file(artifact_path) != digest:
            raise ReleaseVerificationError(f"checksum mismatch: {name}")
    return path


def asset_size_errors(directory: pathlib.Path, limit: int = 2_000_000_000) -> list[str]:
    errors: list[str] = []
    for path in directory.iterdir():
        if path.is_file() and path.stat().st_size > limit:
            errors.append(f"asset exceeds GitHub limit: {path.name}")
    return errors


def evidence_for(
    directory: pathlib.Path,
    source: release.ReleaseSpec,
    artifact: dict[str, Any],
    app_info: dict[str, Any],
    helper_identity: dict[str, Any],
    helper_sha256: str,
    app_arch: str,
    helper_arch: str,
    signature_kind: str,
    notarized: bool,
) -> dict[str, Any]:
    checksum_path = directory / "checksums.txt"
    assets: dict[str, dict[str, Any]] = {}
    for name in (*release_asset_names(directory, source.client_version), "checksums.txt"):
        path = directory / name
        if not path.is_file():
            raise ReleaseVerificationError(f"missing evidence asset: {name}")
        assets[name] = {
            "sha256": sha256_file(path),
            "size": path.stat().st_size,
        }
    return {
        "schemaVersion": 1,
        "channel": source.channel,
        "releaseId": artifact["releaseId"],
        "productVersion": source.product_version,
        "clientVersion": source.client_version,
        "buildNumber": source.build_number,
        "gitCommit": artifact["gitCommit"],
        "helperProtocolVersion": source.helper_protocol_version,
        "helperSHA256": helper_sha256,
        "installers": artifact["installers"],
        "model": artifact["model"],
        "tag": release_tag(source),
        "assets": assets,
        "verification": {
            "appHelperPaired": True,
            "identity": "MATCH",
            "architecture": [app_arch, helper_arch],
            "signatureKind": signature_kind,
            "notarized": notarized,
        },
    }


def write_evidence(path: pathlib.Path, evidence: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(evidence, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def compare_evidence(expected: dict[str, Any], actual: dict[str, Any]) -> None:
    if expected != actual:
        raise ReleaseVerificationError("downloaded release evidence does not match recomputed evidence")


def run_command(args: list[str], timeout: float = 120) -> CommandResult:
    result = subprocess.run(
        args,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )
    return CommandResult(result.returncode, result.stdout)


def require_command(args: list[str], timeout: float = 120) -> str:
    result = run_command(args, timeout=timeout)
    if result.returncode != 0:
        raise ReleaseVerificationError(f"command failed: {' '.join(args)}\n{result.output}")
    return result.output


def _updater_files(app: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path]:
    engine = app / "Contents" / "MacOS" / "CovioUpdater"
    launcher = app / "Contents" / "MacOS" / "CovioUpdaterLauncher"
    daemon = app / "Contents" / "Library" / "LaunchDaemons" / "com.wyz.covio.updater.plist"
    return engine, launcher, daemon


def _verify_updater_files(app: pathlib.Path) -> None:
    engine, launcher, daemon = _updater_files(app)
    if not engine.is_file() or not launcher.is_file() or not daemon.is_file():
        raise ReleaseVerificationError(
            "app bundle must contain updater engine, launcher and LaunchDaemon"
        )
    for binary, identifier in (
        (engine, "com.wyz.covio.updater"),
        (launcher, "com.wyz.covio.updater.launcher"),
    ):
        require_command(["/usr/bin/codesign", "--verify", "--strict", str(binary)])
        arches = require_command(["/usr/bin/lipo", "-archs", str(binary)]).strip()
        if arches != "arm64":
            raise ReleaseVerificationError(f"updater binary is not arm64: {binary.name}")
        report = _signature_report(binary)
        if f"Identifier={identifier}" not in report:
            raise ReleaseVerificationError(
                f"updater binary identifier mismatch: {binary.name}"
            )


def _extract_app_zip(archive: pathlib.Path, destination: pathlib.Path) -> pathlib.Path:
    require_command(["/usr/bin/ditto", "-x", "-k", str(archive), str(destination)])
    app = destination / "Covio.app"
    if not app.is_dir():
        raise ReleaseVerificationError("app archive does not contain Covio.app")
    return app


def _mount_dmg(path: pathlib.Path, mount: pathlib.Path) -> None:
    mount.mkdir(parents=True)
    require_command([
        "/usr/bin/hdiutil",
        "attach",
        "-readonly",
        "-nobrowse",
        "-mountpoint",
        str(mount),
        str(path),
    ])


def _detach_dmg(mount: pathlib.Path) -> None:
    subprocess.run(
        ["/usr/bin/hdiutil", "detach", str(mount)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def _signature_report(path: pathlib.Path) -> str:
    return require_command(["/usr/bin/codesign", "-dv", "--verbose=4", str(path)])


def _helper_identity(helper: pathlib.Path) -> dict[str, Any]:
    result = require_command([str(helper), "--print-release-identity"])
    try:
        value = json.loads(result)
    except json.JSONDecodeError as error:
        raise ReleaseVerificationError(f"helper identity is not valid JSON: {error}") from error
    if not isinstance(value, dict):
        raise ReleaseVerificationError("helper identity must be a JSON object")
    return value


def _signature_kind(app_report: str) -> str:
    if "Authority=Developer ID Application:" in app_report:
        return "developer-id-application"
    if re.search(r"^Signature=adhoc$", app_report, re.MULTILINE):
        return "adhoc"
    if "Authority=" in app_report:
        return "local-certificate"
    return "unknown"


def verify_release(
    directory: pathlib.Path,
    channel: str,
    root: pathlib.Path = ROOT,
    source_manifest: pathlib.Path | None = None,
    expected_commit: str | None = None,
    evidence_output: pathlib.Path | None = None,
    compare_path: pathlib.Path | None = None,
    require_stable_signing: bool = False,
) -> dict[str, Any]:
    if source_manifest is None:
        source = release.load_spec(root)
    else:
        source = release.validate_spec(read_json(source_manifest))
    if source.channel != channel:
        raise ReleaseVerificationError(
            f"source channel is {source.channel}, requested verification channel is {channel}"
        )

    names = expected_asset_names(source.client_version)
    for name in names:
        if not (directory / name).is_file():
            raise ReleaseVerificationError(f"missing release asset: {name}")
    verify_checksums(directory, source.client_version)
    size_errors = asset_size_errors(directory)
    if size_errors:
        raise ReleaseVerificationError("\n".join(size_errors))

    with tempfile.TemporaryDirectory(prefix="covio-release-verify-") as temporary:
        temp = pathlib.Path(temporary)
        app = _extract_app_zip(directory / names[0], temp / "app")
        app_plist_path = app / "Contents" / "Info.plist"
        helper = app / "Contents" / "MacOS" / "CovioHelper"
        app_binary = app / "Contents" / "MacOS" / "Covio"
        if not helper.is_file() or not app_binary.is_file():
            raise ReleaseVerificationError("app archive must contain both Covio and CovioHelper")

        actual_helper_hash = sha256_file(helper)
        artifact_path = directory / "release-manifest.json"
        artifact = release.verify_artifact(artifact_path, helper, root, source)
        bundled_manifest = release.verify_bundle_manifest(
            app / "Contents" / "Resources" / "release-manifest.json",
            helper,
            source,
        )
        for field in release.BUNDLE_IDENTITY_FIELDS:
            if bundled_manifest.get(field) != artifact.get(field):
                raise ReleaseVerificationError(
                    f"bundle manifest {field} differs from the artifact manifest"
                )
        if expected_commit and artifact["gitCommit"] != expected_commit:
            raise ReleaseVerificationError(
                f"artifact commit {artifact['gitCommit']} != expected commit {expected_commit}"
            )
        if model_weight_paths(app):
            raise ReleaseVerificationError("default app archive must not contain model weights")

        app_info = read_plist(app_plist_path)
        helper_identity = _helper_identity(helper)
        errors = identity_errors(source, artifact, app_info, helper_identity, actual_helper_hash)
        if errors:
            raise ReleaseVerificationError("\n".join(errors))

        app_arch = require_command(["/usr/bin/lipo", "-archs", str(app_binary)]).strip()
        helper_arch = require_command(["/usr/bin/lipo", "-archs", str(helper)]).strip()
        errors = architecture_errors(app_arch, helper_arch)
        if errors:
            raise ReleaseVerificationError("\n".join(errors))

        require_command(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
        require_command(["/usr/bin/codesign", "--verify", "--strict", str(helper)])
        _verify_updater_files(app)
        app_signature = _signature_report(app)
        helper_signature = _signature_report(helper)
        package_signature = run_command(["/usr/sbin/pkgutil", "--check-signature", str(directory / names[2])])
        disk_image_signature = run_command(["/usr/bin/codesign", "-dv", "--verbose=4", str(directory / names[1])])
        errors = signature_errors(
            app_signature,
            helper_signature,
            package_signature.output,
            disk_image_signature.output,
            channel,
            require_stable_signing,
        )
        if errors:
            raise ReleaseVerificationError("\n".join(errors))

        app_staple = run_command(["/usr/bin/xcrun", "stapler", "validate", str(app)])
        dmg_staple = run_command(["/usr/bin/xcrun", "stapler", "validate", str(directory / names[1])])
        pkg_staple = run_command(["/usr/bin/xcrun", "stapler", "validate", str(directory / names[2])])
        app_gatekeeper = run_command(["/usr/sbin/spctl", "-a", "-vv", "--type", "execute", str(app)])
        pkg_gatekeeper = run_command(["/usr/sbin/spctl", "-a", "-vv", "--type", "install", str(directory / names[2])])
        errors = notarization_errors(
            channel,
            app_staple,
            dmg_staple,
            pkg_staple,
            app_gatekeeper,
            pkg_gatekeeper,
        )
        if errors:
            raise ReleaseVerificationError("\n".join(errors))

        mount = temp / "dmg"
        try:
            _mount_dmg(directory / names[1], mount)
            mounted_app = mount / "Covio.app"
            mounted_info = read_plist(mounted_app / "Contents" / "Info.plist")
            mounted_helper = mounted_app / "Contents" / "MacOS" / "CovioHelper"
            if not mounted_helper.is_file():
                raise ReleaseVerificationError("DMG app is missing CovioHelper")
            _verify_updater_files(mounted_app)
            mounted_errors = identity_errors(
                source,
                artifact,
                mounted_info,
                helper_identity,
                sha256_file(mounted_helper),
            )
            if mounted_errors:
                raise ReleaseVerificationError("DMG app identity mismatch:\n" + "\n".join(mounted_errors))
        finally:
            _detach_dmg(mount)

        _, offline_name = release.installer_names(artifact, source.client_version)
        if offline_name is not None:
            offline_mount = temp / "offline-dmg"
            try:
                _mount_dmg(directory / offline_name, offline_mount)
                offline_app = offline_mount / "Covio.app"
                if not offline_app.is_dir():
                    raise ReleaseVerificationError("offline DMG is missing Covio.app")
                offline_info = read_plist(offline_app / "Contents" / "Info.plist")
                offline_helper = offline_app / "Contents" / "MacOS" / "CovioHelper"
                if not offline_helper.is_file():
                    raise ReleaseVerificationError("offline DMG app is missing CovioHelper")
                _verify_updater_files(offline_app)
                offline_bundle_manifest = release.verify_bundle_manifest(
                    offline_app / "Contents" / "Resources" / "release-manifest.json",
                    offline_helper,
                    source,
                )
                for field in release.BUNDLE_IDENTITY_FIELDS:
                    if offline_bundle_manifest.get(field) != artifact.get(field):
                        raise ReleaseVerificationError(
                            f"offline bundle manifest {field} differs from the artifact manifest"
                        )
                offline_errors = identity_errors(
                    source,
                    artifact,
                    offline_info,
                    helper_identity,
                    sha256_file(offline_helper),
                )
                if offline_errors:
                    raise ReleaseVerificationError(
                        "offline DMG identity mismatch:\n" + "\n".join(offline_errors)
                    )
                if not model_weight_paths(offline_app):
                    raise ReleaseVerificationError("offline DMG must contain model weights")

                expected_model = artifact["model"]
                model_manifest_path = (
                    offline_app / "Contents" / "Resources" / "FileNamingModelManifest.json"
                )
                if not model_manifest_path.is_file():
                    raise ReleaseVerificationError("offline app is missing the model manifest")
                if sha256_file(model_manifest_path) != expected_model["manifestSHA256"]:
                    raise ReleaseVerificationError("offline model manifest SHA-256 mismatch")
                model_manifest = read_json(model_manifest_path)
                metadata_errors = model_metadata_errors(model_manifest, expected_model)
                if metadata_errors:
                    raise ReleaseVerificationError("\n".join(metadata_errors))
                model_directory = (
                    offline_app / "Contents" / "Resources" / expected_model["runtimeDirectory"]
                )
                require_command(
                    [
                        sys.executable,
                        "-I",
                        str(root / "scripts" / "file_naming_model.py"),
                        "--manifest",
                        str(model_manifest_path),
                        "verify-directory",
                        str(model_directory),
                    ],
                    timeout=900,
                )
                require_command(
                    ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(offline_app)]
                )

                if channel == "internal" and require_stable_signing:
                    offline_app_signature = _signature_report(offline_app)
                    offline_helper_signature = _signature_report(offline_helper)
                    errors = signature_errors(
                        offline_app_signature,
                        offline_helper_signature,
                        "",
                        "",
                        channel,
                        require_stable_signing=True,
                    )
                    if errors:
                        raise ReleaseVerificationError(
                            "offline app signing identity is not stable:\n"
                            + "\n".join(errors)
                        )

                if channel == "public":
                    require_command(
                        ["/usr/bin/codesign", "--verify", "--strict", str(directory / offline_name)]
                    )
                    offline_app_signature = _signature_report(offline_app)
                    offline_dmg_signature = _signature_report(directory / offline_name)
                    if "Authority=Developer ID Application:" not in offline_app_signature:
                        raise ReleaseVerificationError(
                            "offline app is not signed with Developer ID Application"
                        )
                    if "Authority=Developer ID Application:" not in offline_dmg_signature:
                        raise ReleaseVerificationError(
                            "offline DMG is not signed with Developer ID Application"
                        )
                    for label, target in (
                        ("offline app", offline_app),
                        ("offline DMG", directory / offline_name),
                    ):
                        staple = run_command(
                            ["/usr/bin/xcrun", "stapler", "validate", str(target)]
                        )
                        if staple.returncode != 0:
                            raise ReleaseVerificationError(
                                f"{label} notarization ticket is invalid"
                            )
                    gatekeeper = run_command(
                        [
                            "/usr/sbin/spctl",
                            "-a",
                            "-vv",
                            "--type",
                            "execute",
                            str(offline_app),
                        ]
                    )
                    if gatekeeper.returncode != 0:
                        raise ReleaseVerificationError("offline app failed Gatekeeper verification")
            finally:
                _detach_dmg(offline_mount)

        package_payload = require_command(["/usr/sbin/pkgutil", "--payload-files", str(directory / names[2])])
        required_package_paths = (
            "Library/Application Support/Covio/Installer/staged/Covio.app/Contents/MacOS/CovioHelper",
            "Library/Application Support/Covio/Installer/staged/Covio.app/Contents/MacOS/CovioUpdater",
            "Library/Application Support/Covio/Installer/staged/Covio.app/Contents/MacOS/CovioUpdaterLauncher",
            "Library/Application Support/Covio/Installer/bin/CovioTransaction",
            "Library/Application Support/Covio/Installer/recover.sh",
        )
        missing_package_paths = [path for path in required_package_paths if path not in package_payload]
        if missing_package_paths:
            raise ReleaseVerificationError(
                "PKG payload is missing: " + ", ".join(missing_package_paths)
            )

        evidence = evidence_for(
            directory,
            source,
            artifact,
            app_info,
            helper_identity,
            actual_helper_hash,
            app_arch,
            helper_arch,
            _signature_kind(app_signature),
            channel == "public",
        )
    if evidence_output is not None:
        write_evidence(evidence_output, evidence)
    if compare_path is not None:
        compare_evidence(read_json(compare_path), evidence)
    return evidence


def render_notes(evidence: dict[str, Any], template: str) -> str:
    rows = []
    for name, value in sorted(evidence["assets"].items()):
        rows.append(f"| `{name}` | `{value['sha256']}` | {value['size']} |")
    return "\n".join(
        [
            template.rstrip(),
            "",
            "## Release evidence",
            "",
            f"- Channel: `{evidence['channel']}`",
            f"- Client version: `{evidence['clientVersion']}`",
            f"- Product version: `{evidence['productVersion']}`",
            f"- Release ID: `{evidence['releaseId']}`",
            f"- Build: `{evidence['buildNumber']}`",
            f"- Git commit: `{evidence['gitCommit']}`",
            f"- Helper protocol: `{evidence['helperProtocolVersion']}`",
            f"- Helper SHA-256: `{evidence['helperSHA256']}`",
            f"- Verification: `{evidence['verification']['identity']}`",
            f"- Signature: `{evidence['verification']['signatureKind']}`",
            f"- Notarized: `{str(evidence['verification']['notarized']).lower()}`",
            "",
            "| Asset | SHA-256 | Bytes |",
            "| --- | --- | ---: |",
            *rows,
            "",
        ]
    )


def operation_record(
    evidence: dict[str, Any],
    action: str,
    repository: str,
    tag: str,
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "action": action,
        "repository": repository,
        "tag": tag,
        "channel": evidence["channel"],
        "releaseId": evidence["releaseId"],
        "gitCommit": evidence["gitCommit"],
        "assets": evidence["assets"],
        "verified": True,
        "recordedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def promotion_errors(channel: str, release_info: dict[str, Any], evidence: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if not release_info.get("isDraft"):
        errors.append("release is not a draft")
    if release_info.get("tagName") != evidence.get("tag"):
        errors.append("release tag differs from release evidence")
    expected_prerelease = channel == "internal"
    if bool(release_info.get("isPrerelease")) != expected_prerelease:
        errors.append("draft prerelease flag does not match release channel")
    assets = evidence.get("assets", {})
    version = evidence.get("clientVersion")
    if not isinstance(version, str):
        errors.append("release evidence has no clientVersion")
        return errors
    for name in expected_asset_names(version):
        if name not in assets:
            errors.append(f"release evidence is missing {name}")
    installers = evidence.get("installers", {})
    if not isinstance(installers, dict):
        errors.append("release evidence installers must be an object")
        return errors
    for kind, record in installers.items():
        if record is None:
            continue
        if not isinstance(record, dict) or not isinstance(record.get("name"), str):
            errors.append(f"release evidence installer {kind} is invalid")
            continue
        if record["name"] not in assets:
            errors.append(f"release evidence is missing {record['name']}")
    return errors


def public_visibility(channel: str) -> dict[str, bool]:
    return {
        "isDraft": False,
        "isPrerelease": channel == "internal",
        "isLatest": channel == "public",
    }


def _write_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    checksums = sub.add_parser("checksums")
    checksums.add_argument("--directory", required=True, type=pathlib.Path)
    checksums.add_argument("--version", required=True)

    verify = sub.add_parser("verify")
    verify.add_argument("--directory", required=True, type=pathlib.Path)
    verify.add_argument("--channel", required=True, choices=("internal", "public"))
    verify.add_argument("--root", type=pathlib.Path, default=ROOT)
    verify.add_argument("--source-manifest", type=pathlib.Path)
    verify.add_argument("--expected-commit")
    verify.add_argument("--evidence", type=pathlib.Path)
    verify.add_argument("--compare-evidence", type=pathlib.Path)
    verify.add_argument("--require-stable-signing", action="store_true")

    tag = sub.add_parser("tag")
    tag.add_argument("--root", type=pathlib.Path, default=ROOT)
    tag.add_argument("--source-manifest", type=pathlib.Path)

    notes = sub.add_parser("notes")
    notes.add_argument("--evidence", required=True, type=pathlib.Path)
    notes.add_argument("--template", required=True, type=pathlib.Path)
    notes.add_argument("--output", required=True, type=pathlib.Path)

    operation = sub.add_parser("operation")
    operation.add_argument("--evidence", required=True, type=pathlib.Path)
    operation.add_argument("--action", required=True, choices=("create-draft", "publish"))
    operation.add_argument("--repository", required=True)
    operation.add_argument("--tag", required=True)
    operation.add_argument("--output", required=True, type=pathlib.Path)

    promote = sub.add_parser("promote-check")
    promote.add_argument("--release-info", required=True, type=pathlib.Path)
    promote.add_argument("--evidence", required=True, type=pathlib.Path)
    promote.add_argument("--channel", required=True, choices=("internal", "public"))

    args = parser.parse_args(argv)
    try:
        if args.command == "checksums":
            print(write_checksums(args.directory, args.version))
            return 0
        if args.command == "verify":
            verify_release(
                args.directory,
                args.channel,
                root=args.root,
                source_manifest=args.source_manifest,
                expected_commit=args.expected_commit,
                evidence_output=args.evidence,
                compare_path=args.compare_evidence,
                require_stable_signing=args.require_stable_signing,
            )
            print("release verification passed")
            return 0
        if args.command == "tag":
            if args.source_manifest:
                source = release.validate_spec(read_json(args.source_manifest))
            else:
                source = release.load_spec(args.root)
            print(release_tag(source))
            return 0
        if args.command == "notes":
            evidence = read_json(args.evidence)
            template = args.template.read_text(encoding="utf-8")
            args.output.write_text(render_notes(evidence, template), encoding="utf-8")
            print(args.output)
            return 0
        if args.command == "operation":
            evidence = read_json(args.evidence)
            _write_json(
                args.output,
                operation_record(evidence, args.action, args.repository, args.tag),
            )
            print(args.output)
            return 0
        if args.command == "promote-check":
            errors = promotion_errors(
                args.channel,
                read_json(args.release_info),
                read_json(args.evidence),
            )
            if errors:
                raise ReleaseVerificationError("\n".join(errors))
            print("draft release can be promoted")
            return 0
    except (ReleaseVerificationError, release.ManifestError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
