#!/usr/bin/env python3

import json
from pathlib import Path
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = Path(__file__).resolve().parent
RUNTIME_ROOT = FIXTURE_ROOT / ".runtime"
MANIFEST_PATH = FIXTURE_ROOT / "manifest.json"


def render(value: str) -> str:
    return value.replace("{repo}", str(REPO_ROOT)).replace("{runtime}", str(RUNTIME_ROOT))


def matches_expected(service: dict, expected: dict) -> bool:
    if service["observation"]["classification"] != expected["classification"]:
        return False
    if service["observation"]["protocol"] != expected["protocol"]:
        return False
    project = service.get("project") or {}
    if "projectRoot" in expected and project.get("root") != render(expected["projectRoot"]):
        return False
    if "branch" in expected and project.get("branch") != expected["branch"]:
        return False
    if "projectEvidence" in expected and service.get("projectEvidence") != expected["projectEvidence"]:
        return False
    if "managementSource" in expected and service.get("management", {}).get("source") != expected["managementSource"]:
        return False
    if "framework" in expected and service.get("observation", {}).get("framework") != expected["framework"]:
        return False
    return True


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
        passed = any(matches_expected(service, expected) for service in matches)
        actual = [
            {
                "classification": service["observation"]["classification"],
                "protocol": service["observation"]["protocol"],
                "projectRoot": (service.get("project") or {}).get("root"),
                "branch": (service.get("project") or {}).get("branch"),
                "projectEvidence": service.get("projectEvidence"),
                "managementSource": service.get("management", {}).get("source"),
                "framework": service.get("observation", {}).get("framework"),
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
