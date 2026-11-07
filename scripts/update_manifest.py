#!/usr/bin/env python3
"""Generate Covio's signed automatic-update manifest."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Any

REPOSITORY = "wyz541/Covio"
CHANNEL = "internal"
UPDATER_PROTOCOL_VERSION = 1
MANIFEST_SCHEMA_VERSION = 2
SIGNATURE_SCHEMA_VERSION = 1
MAX_ARCHIVE_BYTES = 500_000_000
SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)
HEX_40 = re.compile(r"^[0-9a-f]{40}$")


class UpdateManifestError(Exception):
    pass


@dataclass(frozen=True)
class ReleaseSpec:
    product_version: str
    client_version: str
    build_number: int
    helper_protocol_version: int


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except FileNotFoundError as error:
        raise UpdateManifestError(f"missing file: {path}") from error
    return digest.hexdigest()


def load_release_spec(path: pathlib.Path) -> ReleaseSpec:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise UpdateManifestError(f"missing release manifest: {path}") from error
    except json.JSONDecodeError as error:
        raise UpdateManifestError("release manifest is not valid JSON") from error

    if raw.get("schemaVersion") != 3:
        raise UpdateManifestError("release manifest schemaVersion must be 3")
    channel = raw.get("channel")
    if channel != CHANNEL:
        raise UpdateManifestError(f"update channel must be {CHANNEL}")
    client_version = raw.get("clientVersion")
    fields = semver_fields(client_version)
    if fields is None or fields[2]:
        raise UpdateManifestError("clientVersion is invalid")
    build_number = raw.get("buildNumber")
    if isinstance(build_number, bool) or not isinstance(build_number, int):
        raise UpdateManifestError("buildNumber is invalid")
    if not 1 <= build_number <= 9_999:
        raise UpdateManifestError("buildNumber must be between 1 and 9999")
    product_version = raw.get("productVersion")
    if not isinstance(product_version, str):
        raise UpdateManifestError("productVersion is invalid")
    product_fields = semver_fields(product_version)
    if product_fields is None or product_fields[1] or product_fields[2]:
        raise UpdateManifestError("productVersion is invalid")
    if fields[0] != product_version:
        raise UpdateManifestError("clientVersion must use productVersion as its base")
    if fields[1] != ["internal", str(build_number)]:
        raise UpdateManifestError("internal clientVersion must end with internal.buildNumber")
    helper_protocol = raw.get("helperProtocolVersion")
    if isinstance(helper_protocol, bool) or not isinstance(helper_protocol, int):
        raise UpdateManifestError("helperProtocolVersion is invalid")
    if helper_protocol < 1:
        raise UpdateManifestError("helperProtocolVersion must be positive")
    return ReleaseSpec(
        product_version=product_version,
        client_version=client_version,
        build_number=build_number,
        helper_protocol_version=helper_protocol,
    )


def semver_fields(value: Any) -> tuple[str, list[str], list[str]] | None:
    if not isinstance(value, str):
        return None
    match = SEMVER.fullmatch(value)
    if match is None:
        return None
    prerelease = match.group(4).split(".") if match.group(4) else []
    if any(
        identifier.isdigit() and len(identifier) > 1 and identifier.startswith("0")
        for identifier in prerelease
    ):
        return None
    build_metadata = match.group(5).split(".") if match.group(5) else []
    return f"{match.group(1)}.{match.group(2)}.{match.group(3)}", prerelease, build_metadata


def client_version_for_build(product_version: str, build_number: int) -> str:
    if not 1 <= build_number <= 9_999:
        raise UpdateManifestError("buildNumber must be between 1 and 9999")
    fields = semver_fields(product_version)
    if fields is None or fields[1] or fields[2]:
        raise UpdateManifestError("productVersion is invalid")
    return f"{product_version}-internal.{build_number}"


def generate_manifest(
    *,
    release_manifest: pathlib.Path,
    archive: pathlib.Path,
    app_executable: pathlib.Path,
    helper: pathlib.Path,
    updater: pathlib.Path,
    git_commit: str,
    key_id: str,
    signer: pathlib.Path,
    private_key: pathlib.Path | None = None,
    keychain_service: str | None = None,
    output_dir: pathlib.Path,
    minimum_macos_version: str = "26.0",
    published_at: str | None = None,
) -> tuple[pathlib.Path, pathlib.Path]:
    spec = load_release_spec(release_manifest)
    if not HEX_40.fullmatch(git_commit):
        raise UpdateManifestError("git commit must be 40 lowercase hex characters")
    if not key_id or len(key_id) > 64:
        raise UpdateManifestError("key ID is invalid")
    if not signer.is_file():
        raise UpdateManifestError(f"missing signer: {signer}")
    if (private_key is None) == (keychain_service is None):
        raise UpdateManifestError("provide exactly one update signing key source")
    if private_key is not None and not private_key.is_file():
        raise UpdateManifestError(f"missing private key: {private_key}")
    if keychain_service is not None and not keychain_service:
        raise UpdateManifestError("update signing keychain service is empty")

    expected_archive_name = f"CovioUpdate-{spec.client_version}.zip"
    if archive.name != expected_archive_name:
        raise UpdateManifestError(f"archive name must be {expected_archive_name}")
    archive_size = archive.stat().st_size
    if not 0 < archive_size <= MAX_ARCHIVE_BYTES:
        raise UpdateManifestError("archive size is outside the allowed range")
    if published_at is None:
        published_timestamp = dt.datetime.now(dt.timezone.utc)
    else:
        try:
            published_timestamp = dt.datetime.fromisoformat(
                published_at.replace("Z", "+00:00")
            )
        except ValueError as error:
            raise UpdateManifestError("publishedAt is invalid") from error
        if published_timestamp.tzinfo is None:
            raise UpdateManifestError("publishedAt must include a time zone")
    published_at = (
        published_timestamp.astimezone(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )

    release_id = f"{spec.client_version}-g{git_commit}"
    archive_url = (
        f"https://github.com/{REPOSITORY}/releases/download/"
        f"v{spec.client_version}/{expected_archive_name}"
    )
    manifest: dict[str, Any] = {
        "schemaVersion": MANIFEST_SCHEMA_VERSION,
        "keyId": key_id,
        "channel": CHANNEL,
        "productVersion": spec.product_version,
        "clientVersion": spec.client_version,
        "buildNumber": spec.build_number,
        "gitCommit": git_commit,
        "releaseId": release_id,
        "helperProtocolVersion": spec.helper_protocol_version,
        "updaterProtocolVersion": UPDATER_PROTOCOL_VERSION,
        "minimumMacOSVersion": minimum_macos_version,
        "archiveURL": archive_url,
        "archiveSHA256": sha256_file(archive),
        "archiveSize": archive_size,
        "componentHashes": {
            "app": sha256_file(app_executable),
            "helper": sha256_file(helper),
            "updater": sha256_file(updater),
        },
        "publishedAt": published_at,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / f"CovioUpdate-{spec.client_version}.json"
    signature_path = output_dir / f"CovioUpdate-{spec.client_version}.sig.json"
    manifest_bytes = (
        json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")
    temporary_manifest = manifest_path.with_name(manifest_path.name + ".tmp")
    temporary_manifest.write_bytes(manifest_bytes)
    os.chmod(temporary_manifest, 0o644)
    os.replace(temporary_manifest, manifest_path)

    if private_key is not None:
        command = [
            str(signer),
            "sign",
            "--private-key",
            str(private_key),
        ]
        command.extend(
            [
                "--manifest",
                str(manifest_path),
                "--output",
                str(signature_path),
            ]
        )
        input_value = None
    else:
        key_result = subprocess.run(
            [
                "/usr/bin/security",
                "find-generic-password",
                "-s",
                str(keychain_service),
                "-a",
                key_id,
                "-w",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if key_result.returncode != 0:
            raise UpdateManifestError("cannot read update signing key from Keychain")
        command = [
            str(signer),
            "sign-stdin",
            "--manifest",
            str(manifest_path),
            "--output",
            str(signature_path),
        ]
        input_value = key_result.stdout
    result = subprocess.run(
        command,
        input=input_value,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise UpdateManifestError(result.stderr.strip() or "manifest signing failed")
    signature_envelope = json.loads(signature_path.read_text(encoding="utf-8"))
    if signature_envelope.get("schemaVersion") != SIGNATURE_SCHEMA_VERSION:
        raise UpdateManifestError("signature envelope schemaVersion is invalid")
    if signature_envelope.get("manifestSHA256") != hashlib.sha256(manifest_bytes).hexdigest():
        raise UpdateManifestError("signature envelope digest does not match manifest")
    records = signature_envelope.get("signatures")
    if not isinstance(records, list) or not records:
        raise UpdateManifestError("signature envelope has no signatures")
    if not any(
        isinstance(record, dict) and record.get("keyId") == key_id
        for record in records
    ):
        raise UpdateManifestError("signature envelope does not use the requested key ID")
    return manifest_path, signature_path


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    generate = commands.add_parser("generate")
    generate.add_argument("--release-manifest", required=True, type=pathlib.Path)
    generate.add_argument("--archive", required=True, type=pathlib.Path)
    generate.add_argument("--app-executable", required=True, type=pathlib.Path)
    generate.add_argument("--helper", required=True, type=pathlib.Path)
    generate.add_argument("--updater", required=True, type=pathlib.Path)
    generate.add_argument("--commit", required=True)
    generate.add_argument("--key-id", required=True)
    generate.add_argument("--signer", required=True, type=pathlib.Path)
    key_source = generate.add_mutually_exclusive_group(required=True)
    key_source.add_argument("--private-key", type=pathlib.Path)
    key_source.add_argument("--keychain-service")
    generate.add_argument("--output-dir", required=True, type=pathlib.Path)
    generate.add_argument("--minimum-macos-version", default="26.0")
    generate.add_argument("--published-at")
    return parser


def main() -> int:
    arguments = _parser().parse_args()
    try:
        if arguments.command == "generate":
            manifest, signature = generate_manifest(
                release_manifest=arguments.release_manifest,
                archive=arguments.archive,
                app_executable=arguments.app_executable,
                helper=arguments.helper,
                updater=arguments.updater,
                git_commit=arguments.commit,
                key_id=arguments.key_id,
                signer=arguments.signer,
                private_key=arguments.private_key,
                keychain_service=arguments.keychain_service,
                output_dir=arguments.output_dir,
                minimum_macos_version=arguments.minimum_macos_version,
                published_at=arguments.published_at,
            )
            print(manifest)
            print(signature)
            return 0
    except (OSError, UpdateManifestError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
