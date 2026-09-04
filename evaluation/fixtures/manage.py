#!/usr/bin/env python3

import argparse
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
from typing import Dict, List, Optional


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = Path(__file__).resolve().parent
RUNTIME_ROOT = FIXTURE_ROOT / ".runtime"
MANIFEST_PATH = FIXTURE_ROOT / "manifest.json"


def load_manifest() -> Dict[str, object]:
    with MANIFEST_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def fixtures_by_id() -> Dict[str, Dict[str, object]]:
    manifest = load_manifest()
    return {fixture["id"]: fixture for fixture in manifest["fixtures"]}


def selected_fixtures(fixture_id: Optional[str]) -> List[Dict[str, object]]:
    fixtures = fixtures_by_id()
    if fixture_id is None or fixture_id == "all":
        return list(fixtures.values())
    if fixture_id not in fixtures:
        raise SystemExit("unknown fixture: {}".format(fixture_id))
    return [fixtures[fixture_id]]


def pid_path(fixture_id: str) -> Path:
    return RUNTIME_ROOT / "{}.pid".format(fixture_id)


def read_pid(fixture_id: str) -> Optional[int]:
    path = pid_path(fixture_id)
    if not path.exists():
        return None
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None


def process_alive(pid: Optional[int]) -> bool:
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def ensure_certificate() -> None:
    certificate = RUNTIME_ROOT / "localhost.crt"
    private_key = RUNTIME_ROOT / "localhost.key"
    if certificate.exists() and private_key.exists():
        return
    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-days",
            "1",
            "-subj",
            "/CN=localhost",
            "-addext",
            "subjectAltName=DNS:localhost,IP:127.0.0.1",
            "-keyout",
            str(private_key),
            "-out",
            str(certificate),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def render_command(fixture: Dict[str, object]) -> List[str]:
    return [part.replace("{runtime}", str(RUNTIME_ROOT)) for part in fixture["command"]]


def wait_for_listener(port: int, timeout: float = 8.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.15):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def start_fixture(fixture: Dict[str, object]) -> Dict[str, object]:
    fixture_id = fixture["id"]
    existing_pid = read_pid(fixture_id)
    if process_alive(existing_pid):
        return {"id": fixture_id, "status": "already-running", "pid": existing_pid}

    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
    if fixture.get("prepare") == "self-signed-certificate":
        ensure_certificate()

    command = render_command(fixture)
    cwd = REPO_ROOT / fixture.get("cwd", ".")
    log_path = RUNTIME_ROOT / "{}.log".format(fixture_id)
    log_handle = log_path.open("ab", buffering=0)
    process = subprocess.Popen(
        command,
        cwd=str(cwd),
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    pid_path(fixture_id).write_text(str(process.pid), encoding="utf-8")
    if not wait_for_listener(int(fixture["port"])):
        stop_fixture(fixture)
        raise RuntimeError("{} did not listen; inspect {}".format(fixture_id, log_path))
    return {
        "id": fixture_id,
        "status": "started",
        "pid": process.pid,
        "port": fixture["port"],
        "log": str(log_path),
    }


def stop_fixture(fixture: Dict[str, object]) -> Dict[str, object]:
    fixture_id = fixture["id"]
    path = pid_path(fixture_id)
    pid = read_pid(fixture_id)
    if not process_alive(pid):
        path.unlink(missing_ok=True)
        return {"id": fixture_id, "status": "not-running"}

    os.killpg(pid, signal.SIGTERM)
    deadline = time.monotonic() + 4.0
    while process_alive(pid) and time.monotonic() < deadline:
        time.sleep(0.1)
    if process_alive(pid):
        os.killpg(pid, signal.SIGKILL)
    path.unlink(missing_ok=True)
    released = not wait_for_listener(int(fixture["port"]), timeout=0.4)
    return {"id": fixture_id, "status": "stopped", "listenerReleased": released}


def status_fixture(fixture: Dict[str, object]) -> Dict[str, object]:
    pid = read_pid(fixture["id"])
    return {
        "id": fixture["id"],
        "status": "running" if process_alive(pid) else "stopped",
        "pid": pid,
        "port": fixture["port"],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage disposable port-tools fixtures")
    parser.add_argument("action", choices=("start", "stop", "status"))
    parser.add_argument("fixture", nargs="?", default="all")
    args = parser.parse_args()

    results = []
    for fixture in selected_fixtures(args.fixture):
        if args.action == "start":
            results.append(start_fixture(fixture))
        elif args.action == "stop":
            results.append(stop_fixture(fixture))
        else:
            results.append(status_fixture(fixture))
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        raise SystemExit(1)
