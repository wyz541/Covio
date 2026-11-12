#!/usr/bin/env python3
"""Validate the checked-in iOS project without Xcode."""

from __future__ import annotations

import pathlib
import plistlib
import re
import sys
import xml.etree.ElementTree as ET


ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS_ROOT = ROOT / "iosApp"
PROJECT = IOS_ROOT / "Covio.xcodeproj" / "project.pbxproj"
SCHEME = IOS_ROOT / "Covio.xcodeproj" / "xcshareddata" / "xcschemes" / "Covio.xcscheme"


def validate_balanced(path: pathlib.Path, text: str) -> None:
    pairs = {"}": "{", ")": "(", "]": "["}
    stack: list[str] = []
    in_string = False
    escaped = False
    index = 0
    while index < len(text):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
        elif char in "{([":
            stack.append(char)
        elif char in "})]":
            if not stack or stack.pop() != pairs[char]:
                raise ValueError(f"unbalanced delimiter in {path}")
        index += 1
    if in_string or stack:
        raise ValueError(f"unterminated token in {path}")


def validate_unique_object_ids(path: pathlib.Path, text: str) -> None:
    object_ids = re.findall(
        r"^\t\t([A-F0-9]{24})(?: /\*.*?\*/)? = \{",
        text,
        flags=re.MULTILINE,
    )
    duplicates = sorted({object_id for object_id in object_ids if object_ids.count(object_id) > 1})
    if duplicates:
        raise ValueError(f"duplicate Xcode object IDs in {path}: {', '.join(duplicates)}")


def main() -> int:
    source_files = sorted((IOS_ROOT / "Covio").glob("*.swift"))
    test_files = sorted((IOS_ROOT / "CovioTests").glob("*.swift"))
    project_text = PROJECT.read_text(encoding="utf-8")
    validate_balanced(PROJECT, project_text)
    validate_unique_object_ids(PROJECT, project_text)
    for path in [*source_files, *test_files, IOS_ROOT / "Covio" / "Info.plist"]:
        if not path.is_file():
            raise ValueError(f"missing iOS project file: {path}")
        if path.name not in project_text:
            raise ValueError(f"iOS project does not reference {path.name}")
    with (IOS_ROOT / "Covio" / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    for key in (
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "CovioClientVersion",
        "CovioProductVersion",
        "CovioReleaseChannel",
        "CovioGitCommit",
        "CovioReleaseId",
        "CovioHelperProtocolVersion",
    ):
        if key not in info:
            raise ValueError(f"iOS Info.plist is missing {key}")
    expected_substitutions = {
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "CovioClientVersion": "$(COVIO_CLIENT_VERSION)",
        "CovioProductVersion": "$(COVIO_PRODUCT_VERSION)",
        "CovioReleaseChannel": "$(COVIO_RELEASE_CHANNEL)",
        "CovioGitCommit": "$(COVIO_GIT_COMMIT)",
        "CovioReleaseId": "$(COVIO_RELEASE_ID)",
        "CovioHelperProtocolVersion": "$(COVIO_HELPER_PROTOCOL_VERSION)",
    }
    for key, value in expected_substitutions.items():
        if info[key] != value:
            raise ValueError(f"iOS Info.plist {key} must use {value}")
    ET.parse(SCHEME)
    for setting in [
        "IPHONEOS_DEPLOYMENT_TARGET = 17.0",
        "PRODUCT_BUNDLE_IDENTIFIER = com.wyz.covio.ios",
        "SWIFT_VERSION = 6.0",
        "Build Rust core",
        "scripts/build-ios-rust.sh",
    ]:
        if setting not in project_text:
            raise ValueError(f"iOS project is missing {setting!r}")
    print(f"Validated {PROJECT}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"iOS project validation failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
