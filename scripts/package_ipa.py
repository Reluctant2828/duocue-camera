#!/usr/bin/env python3
"""Package an unsigned .app without losing executable bits or framework symlinks."""
from __future__ import annotations

import argparse
import json
import os
import plistlib
import stat
import zipfile
from pathlib import Path


def package_app(app: Path, output: Path) -> None:
    app = app.resolve()
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("Expected an existing .app directory")
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    executable = app / info["CFBundleExecutable"]
    if not executable.is_file():
        raise ValueError("The app executable is missing")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for base, dirs, files in os.walk(app, followlinks=False):
            for name in sorted(dirs + files):
                path = Path(base) / name
                entry_name = "Payload/" + path.relative_to(app.parent).as_posix()
                details = path.lstat()
                if stat.S_ISLNK(details.st_mode):
                    entry = zipfile.ZipInfo(entry_name)
                    entry.create_system = 3
                    entry.external_attr = details.st_mode << 16
                    archive.writestr(entry, os.readlink(path).encode("utf-8"))
                elif path.is_file():
                    archive.write(path, entry_name)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("IPA archive failed integrity validation")
    print(json.dumps({"file": str(output), "bundle_id": info["CFBundleIdentifier"], "version": info.get("CFBundleShortVersionString"), "signed": False}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package_app(args.app, args.output)
