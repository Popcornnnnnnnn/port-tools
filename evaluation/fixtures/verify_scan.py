#!/usr/bin/env python3

import json
from pathlib import Path
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = Path(__file__).resolve().parent / "manifest.json"


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    completed = subprocess.run(
        [str(REPO_ROOT / "bin" / "port-tools"), "scan", "--json", "--all"],
        cwd=str(REPO_ROOT),
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    )
    scan = json.loads(completed.stdout)
    by_port = {}
    for service in scan["services"]:
        by_port.setdefault(service["listener"]["port"], []).append(service)

    results = []
    failed = False
    for fixture in manifest["fixtures"]:
        matches = by_port.get(fixture["port"], [])
        expected = fixture["expected"]
        passed = any(
            service["observation"]["classification"] == expected["classification"]
            and service["observation"]["protocol"] == expected["protocol"]
            for service in matches
        )
        actual = [
            {
                "classification": service["observation"]["classification"],
                "protocol": service["observation"]["protocol"],
            }
            for service in matches
        ]
        results.append(
            {
                "id": fixture["id"],
                "port": fixture["port"],
                "passed": passed,
                "expected": {
                    "classification": expected["classification"],
                    "protocol": expected["protocol"],
                },
                "actual": actual,
            }
        )
        failed = failed or not passed

    print(json.dumps({"passed": not failed, "fixtures": results}, indent=2))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
