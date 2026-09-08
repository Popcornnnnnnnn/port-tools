#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNTIME_ROOT = Path(__file__).resolve().parent / ".runtime"
MANIFEST_PATH = Path(__file__).resolve().parent / "manifest.json"
DEFAULT_CORE = REPO_ROOT / "native" / ".build" / "Port Tools.app" / "Contents" / "Helpers" / "port-tools-core"


def render(value: str) -> str:
    return value.replace("{repo}", str(REPO_ROOT)).replace("{runtime}", str(RUNTIME_ROOT))


def matches_expected(service: dict, expected: dict) -> bool:
    observation = service["observation"]
    project = service.get("project") or {}
    application = service.get("application") or {}
    management = service.get("management") or {}
    if observation["classification"] != expected["classification"]:
        return False
    if observation["protocol"] != expected["protocol"]:
        return False
    checks = (
        ("projectRoot", project.get("root")),
        ("applicationRoot", application.get("root")),
        ("applicationName", application.get("name")),
        ("branch", project.get("branch")),
        ("projectEvidence", service.get("projectEvidence")),
        ("managementSource", management.get("source")),
        ("framework", observation.get("framework")),
    )
    for key, actual in checks:
        if key in expected and actual != render(expected[key]):
            return False
    if expected.get("projectAbsent") and service.get("project") is not None:
        return False
    if "projectCandidateCount" in expected and len(service.get("projectCandidates", [])) != expected["projectCandidateCount"]:
        return False
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", type=Path, default=DEFAULT_CORE)
    args = parser.parse_args()
    completed = subprocess.run(
        [str(args.core), "scan"],
        cwd=str(REPO_ROOT),
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    )
    document = json.loads(completed.stdout)
    by_port = {}
    for service in document["services"]:
        by_port.setdefault(service["listener"]["port"], []).append(service)

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    results = []
    for fixture in manifest["fixtures"]:
        matches = by_port.get(fixture["port"], [])
        results.append({
            "id": fixture["id"],
            "port": fixture["port"],
            "passed": any(matches_expected(service, fixture["expected"]) for service in matches),
        })
    passed = all(result["passed"] for result in results)
    print(json.dumps({"passed": passed, "passedCount": sum(result["passed"] for result in results), "total": len(results), "fixtures": results}, indent=2))
    if not passed:
        sys.exit(1)


if __name__ == "__main__":
    main()
