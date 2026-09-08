#!/usr/bin/env python3

import json
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time


REPO_ROOT = Path(__file__).resolve().parents[2]
CORE = REPO_ROOT / "native" / ".build" / "Port Tools.app" / "Contents" / "Helpers" / "port-tools-core"


def reserve_port() -> int:
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        return reservation.getsockname()[1]


def wait_for_port(port: int, expected: bool, timeout: float = 5) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                listening = True
        except OSError:
            listening = False
        if listening == expected:
            return
        time.sleep(0.05)
    raise RuntimeError(f"port {port} did not reach listening={expected}")


def core_request(socket_path: Path, method: str, path: str, body=None, check=True):
    command = [str(CORE), "request", "--socket", str(socket_path), "--method", method, "--path", path]
    if body is not None:
        command.extend(["--body", json.dumps(body)])
    result = subprocess.run(command, cwd=REPO_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(result.stdout or result.stderr)
    return result


def main() -> None:
    if not CORE.exists():
        raise SystemExit("build the native app first: native/trial/build.sh")
    port = reserve_port()
    code = (
        "import http.server,signal;"
        "signal.signal(signal.SIGTERM,lambda *_:None);"
        f"http.server.ThreadingHTTPServer(('127.0.0.1',{port}),http.server.SimpleHTTPRequestHandler).serve_forever()"
    )
    with tempfile.TemporaryDirectory(prefix="port-tools-force-") as directory:
        root = Path(directory)
        socket_path = root / "core.sock"
        server = subprocess.Popen(
            ["python3", "-c", code], cwd=REPO_ROOT,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        core = subprocess.Popen(
            [str(CORE), "serve", "--socket", str(socket_path), "--state", str(root / "routes.json"),
             "--proxy", "127.0.0.1:0", "--instance-token", "force-verification"],
            cwd=REPO_ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            wait_for_port(port, True)
            deadline = time.monotonic() + 5
            service = None
            while time.monotonic() < deadline and service is None:
                scan = json.loads(core_request(socket_path, "GET", "/v1/services").stdout)
                service = next((item for item in scan["services"] if item["listener"]["port"] == port), None)
                if service is None:
                    time.sleep(0.1)
            if service is None:
                raise RuntimeError("force-stop fixture was not discovered")

            service_path = f"/v1/services/{service['id']}"
            plan = json.loads(core_request(socket_path, "POST", service_path + "/stop-plan").stdout)
            graceful = json.loads(core_request(
                socket_path, "POST", service_path + "/graceful-stop",
                {"planToken": plan["planToken"], "timeoutSeconds": 0.25},
            ).stdout)
            force_plan = json.loads(core_request(
                socket_path, "POST", service_path + "/force-stop-plan",
                {"gracefulAttemptToken": graceful["gracefulAttemptToken"]},
            ).stdout)
            force = json.loads(core_request(
                socket_path, "POST", service_path + "/force-stop",
                {"planToken": force_plan["planToken"]},
            ).stdout)
            server.wait(timeout=3)
            wait_for_port(port, False)
            reuse = core_request(
                socket_path, "POST", service_path + "/force-stop",
                {"planToken": force_plan["planToken"]}, check=False,
            )
            results = {
                "gracefulTimedOut": graceful.get("forceStopAvailable") is True and graceful.get("listenersReleased") is False,
                "secondPlanRequired": force_plan.get("requiresSecondConfirmation") is True,
                "forceKilled": force.get("success") is True and force.get("forceStopPerformed") is True,
                "listenerReleased": force.get("listenersReleased") is True,
                "tokenSingleUse": reuse.returncode != 0,
            }
            passed = all(results.values())
            print(json.dumps({"passed": passed, "results": results}, indent=2))
            if not passed:
                raise SystemExit(1)
        finally:
            if server.poll() is None:
                server.kill()
                server.wait(timeout=3)
            if core.poll() is None:
                core.send_signal(signal.SIGTERM)
                core.wait(timeout=3)


if __name__ == "__main__":
    main()
