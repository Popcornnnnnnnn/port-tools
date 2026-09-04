#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import time


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = Path(__file__).resolve().parent
RUNTIME_ROOT = FIXTURE_ROOT / ".runtime"
MANAGER = FIXTURE_ROOT / "manage.py"
CLI = REPO_ROOT / "bin" / "port-tools"
FIXTURES = {"static-http": 51739, "shell-wrapper": 51743}


def run(command, check=True):
    return subprocess.run(
        [str(part) for part in command],
        cwd=str(REPO_ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=check,
    )


def port_listening(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.15):
            return True
    except OSError:
        return False


def wait_for_port(port: int, expected: bool, timeout: float = 5.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if port_listening(port) == expected:
            return True
        time.sleep(0.1)
    return False


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def fixture_pid(fixture_id: str):
    path = RUNTIME_ROOT / "{}.pid".format(fixture_id)
    if not path.exists():
        return None
    try:
        return int(path.read_text(encoding="utf-8"))
    except ValueError:
        return None


def scan_service(port: int) -> dict:
    completed = run([CLI, "scan", "--json", "--all"])
    document = json.loads(completed.stdout)
    matches = [service for service in document["services"] if service["listener"]["port"] == port]
    if len(matches) != 1:
        raise RuntimeError("expected exactly one service on port {}".format(port))
    service = matches[0]
    if (service.get("project") or {}).get("root") != str(REPO_ROOT):
        raise RuntimeError("fixture service did not resolve to the port-tools project")
    return service


def graceful_stop_fixture(port: int) -> dict:
    service = scan_service(port)
    completed = run(
        [CLI, "stop", service["id"], "--graceful", "--timeout", "5", "--json"],
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stdout or completed.stderr)
    result = json.loads(completed.stdout)
    if not result["success"] or not result["signalSent"] or not result["listenersReleased"]:
        raise RuntimeError("graceful stop did not prove success: {}".format(result))
    if result["forceStopPerformed"]:
        raise RuntimeError("force stop must never run in this verification")
    if not wait_for_port(port, False):
        raise RuntimeError("port {} remained reachable after success".format(port))
    return result


def cleanup_with_sigterm_only(started_pids) -> None:
    for pid in started_pids:
        if process_alive(pid):
            try:
                os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + 5
    while any(process_alive(pid) for pid in started_pids) and time.monotonic() < deadline:
        time.sleep(0.1)


def main() -> None:
    occupied = [port for port in FIXTURES.values() if port_listening(port)]
    if occupied:
        raise SystemExit("fixture ports already occupied: {}".format(occupied))
    if RUNTIME_ROOT.exists():
        raise SystemExit("fixture runtime already exists; clean it before safe-stop verification")

    started_pids = []
    completed = False
    results = {}
    try:
        for fixture_id in FIXTURES:
            started = json.loads(run(["python3", MANAGER, "start", fixture_id]).stdout)[0]
            started_pids.append(int(started["pid"]))

        shell_parent_pid = fixture_pid("shell-wrapper")
        results["static"] = graceful_stop_fixture(FIXTURES["static-http"])
        results["unrelatedFixturePreserved"] = (
            shell_parent_pid is not None
            and process_alive(shell_parent_pid)
            and port_listening(FIXTURES["shell-wrapper"])
        )
        if not results["unrelatedFixturePreserved"]:
            raise RuntimeError("stopping static fixture affected the unrelated shell fixture")

        results["shellWrapper"] = graceful_stop_fixture(FIXTURES["shell-wrapper"])
        results["allFixturePortsReleased"] = all(
            wait_for_port(port, False) for port in FIXTURES.values()
        )
        results["forceStopPerformed"] = any(
            result["forceStopPerformed"]
            for result in (results["static"], results["shellWrapper"])
        )
        completed = results["allFixturePortsReleased"] and not results["forceStopPerformed"]
        print(json.dumps({"passed": completed, "results": results}, indent=2))
        if not completed:
            raise SystemExit(1)
    finally:
        cleanup_with_sigterm_only(started_pids)
        still_alive = [pid for pid in started_pids if process_alive(pid)]
        ports_left = [port for port in FIXTURES.values() if port_listening(port)]
        if completed and not still_alive and not ports_left:
            shutil.rmtree(RUNTIME_ROOT, ignore_errors=True)
        else:
            print(
                json.dumps(
                    {
                        "cleanup": "SIGTERM only",
                        "stillAlive": still_alive,
                        "portsLeft": ports_left,
                        "runtimeRetained": str(RUNTIME_ROOT),
                    }
                )
            )


if __name__ == "__main__":
    main()
