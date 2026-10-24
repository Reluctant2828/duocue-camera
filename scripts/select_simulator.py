#!/usr/bin/env python3
"""Read simctl JSON on stdin and select an available iPhone with iOS >=27.1."""
import json
import re
import sys

devices = json.load(sys.stdin).get("devices", {})
candidates = []
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = tuple(int(x) for x in match.groups())
    if version < (27, 1):
        continue
    for entry in entries:
        if entry.get("isAvailable") and "iPhone" in entry.get("name", ""):
            candidates.append((version != (27, 1), version, "Duo" not in entry["name"], entry["udid"]))
if not candidates:
    raise SystemExit("No available iPhone simulator with iOS 27.1 or newer")
print(sorted(candidates)[0][-1])
