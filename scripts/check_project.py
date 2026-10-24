#!/usr/bin/env python3
"""Read-only checks available on Windows; this does not compile iOS Swift."""
from __future__ import annotations

import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from generate_project import ROOT, render


def check() -> list[str]:
    errors = []
    for path, expected in render().items():
        if not path.exists() or path.read_text(encoding="utf-8") != expected:
            errors.append(f"Stale or missing generated file: {path.relative_to(ROOT)}")
    sources = sorted((ROOT / "DuoCue").rglob("*.swift"))
    if not sources:
        errors.append("No Swift app sources found")
    elif sum(bool(re.search(r"@main\b", x.read_text(encoding="utf-8"))) for x in sources) != 1:
        errors.append("The app must have exactly one @main entry point")
    for relative in ["DuoCue/Info.plist", "DuoCue/PrivacyInfo.xcprivacy"]:
        try:
            with (ROOT / relative).open("rb") as stream:
                plistlib.load(stream)
        except (OSError, plistlib.InvalidFileException, ValueError) as exc:
            errors.append(f"Invalid {relative}: {exc}")
    try:
        with (ROOT / "DuoCue/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription"]:
            if not info.get(key):
                errors.append(f"Missing permission text: {key}")
        display_name = info.get("CFBundleDisplayName", "")
        if not display_name.isascii() or not display_name:
            errors.append("CFBundleDisplayName must be non-empty ASCII for SideStore App ID registration")
    except Exception:
        pass
    for path in (ROOT / "DuoCue/Assets.xcassets").rglob("Contents.json"):
        try:
            asset = json.loads(path.read_text(encoding="utf-8"))
            for image in asset.get("images", []):
                if image.get("filename") and not (path.parent / image["filename"]).is_file():
                    errors.append(f"Missing asset: {image['filename']}")
        except (OSError, ValueError) as exc:
            errors.append(f"Invalid asset catalog: {path}: {exc}")
    for path in (ROOT / "DuoCue.xcodeproj").rglob("*.xcscheme"):
        try:
            ET.parse(path)
        except ET.ParseError as exc:
            errors.append(f"Invalid scheme: {exc}")
    workflow_path = ROOT / ".github/workflows/build-ios.yml"
    if workflow_path.exists():
        workflow = workflow_path.read_text(encoding="utf-8")
        if "workflow_dispatch:" not in workflow or "DEVELOPER_DIR: /Applications/Xcode_27.1.app/Contents/Developer" not in workflow:
            errors.append("Workflow must be manual and pin Xcode 27.1")
        for action in re.findall(r"uses:\s*(\S+)", workflow):
            if not re.fullmatch(r"[\w.-]+/[\w.-]+@[a-f0-9]{40}", action):
                errors.append(f"Action is not pinned to a full commit: {action}")
        if re.search(r"^\s+(push|pull_request|schedule):", workflow, re.MULTILINE):
            errors.append("Workflow must not run on automatic events")
    else:
        errors.append("Missing iOS workflow")
    for pattern in ["*.p12", "*.p8", "*.mobileprovision", "*.pem", "*.key"]:
        for path in ROOT.rglob(pattern):
            if not any(part in {".git", "build", "artifacts", ".venv"} for part in path.parts):
                errors.append(f"Signing material must not be in source: {path.relative_to(ROOT)}")
    return errors


if __name__ == "__main__":
    problems = check()
    for problem in problems:
        print("ERROR:", problem)
    if problems:
        raise SystemExit(1)
    print("PASS: project references, app metadata, asset paths, permissions, and manual workflow.")
    print("NOT VERIFIED: Swift compilation, signing, iPhone Duo camera or outer-display behavior.")
