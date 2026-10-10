#!/usr/bin/env python3
"""Reject helpers that are sealed as resources instead of nested code."""

import argparse
from pathlib import Path
import plistlib
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    app = parser.parse_args().app
    envelope = plistlib.loads((app / "Contents/_CodeSignature/CodeResources").read_bytes())
    entries = envelope.get("files2", {})
    for name in ("port-tools-core", "port-tools-portless-helper"):
        relative_path = f"Helpers/{name}"
        entry = entries.get(relative_path, {})
        signature = subprocess.run(
            ["codesign", "-d", "--verbose=4", str(app / "Contents" / relative_path)],
            capture_output=True, text=True, check=True,
        )
        match = re.search(r"^CDHash=([0-9a-f]+)$", signature.stderr, re.MULTILINE)
        if (
            not match
            or entry.get("cdhash") != bytes.fromhex(match.group(1))
            or not entry.get("requirement")
        ):
            raise SystemExit(f"{relative_path} is not sealed as matching nested code")
    legacy_path = app / "Contents/Library/LaunchServices/port-tools-portless-helper"
    if legacy_path.exists():
        raise SystemExit("The legacy portless-helper resource must not be packaged")
    print("Both helpers are sealed as matching nested code.")


if __name__ == "__main__":
    main()
