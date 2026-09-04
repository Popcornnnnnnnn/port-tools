#!/usr/bin/env python3

import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = Path(__file__).resolve().parent
RUNTIME_ROOT = FIXTURE_ROOT / ".runtime"
MANAGER = FIXTURE_ROOT / "manage.py"
SCANNER = REPO_ROOT / "bin" / "port-tools"
ORIGINAL_PORT = 51744
RESTART_PORT = 51747


def run(command):
    return subprocess.run(
        [str(part) for part in command],
        cwd=str(REPO_ROOT),
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    )


def wait_for_listener(port: int, expected: bool, timeout: float = 8.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.15):
                listening = True
        except OSError:
            listening = False
        if listening == expected:
            return
        time.sleep(0.1)
    raise RuntimeError("port {} did not reach listening={}".format(port, expected))


def scan_identity(port: int) -> dict:
    document = json.loads(run([SCANNER, "scan", "--json", "--all"]).stdout)
    service = next(item for item in document["services"] if item["listener"]["port"] == port)
    group = next(item for item in document["groups"] if service["id"] in item["serviceIds"])
    return {
        "serviceId": service["id"],
        "groupId": group["id"],
        "projectRoot": service["project"]["root"],
        "repositoryName": service["project"]["repositoryName"],
        "branch": service["project"]["branch"],
    }


def main() -> None:
    run(["python3", MANAGER, "stop", "worktree-main"])
    restarted = None
    try:
        run(["python3", MANAGER, "start", "worktree-main"])
        before = scan_identity(ORIGINAL_PORT)
        run(["python3", MANAGER, "stop", "worktree-main"])

        worktree_root = RUNTIME_ROOT / "worktree-main"
        log_handle = (RUNTIME_ROOT / "worktree-restart.log").open("ab", buffering=0)
        restarted = subprocess.Popen(
            [
                "python3",
                "http_fixture.py",
                "--host",
                "127.0.0.1",
                "--port",
                str(RESTART_PORT),
            ],
            cwd=str(worktree_root),
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        wait_for_listener(RESTART_PORT, expected=True)
        after = scan_identity(RESTART_PORT)
        passed = (
            before["groupId"] == after["groupId"]
            and before["projectRoot"] == after["projectRoot"]
            and before["serviceId"] != after["serviceId"]
        )
        print(json.dumps({"passed": passed, "before": before, "after": after}, indent=2))
        if not passed:
            raise SystemExit(1)
    finally:
        if restarted and restarted.poll() is None:
            os.killpg(restarted.pid, signal.SIGTERM)
            restarted.wait(timeout=4)
        wait_for_listener(RESTART_PORT, expected=False, timeout=1.0)
        run(["python3", MANAGER, "stop", "worktree-main"])


if __name__ == "__main__":
    main()
