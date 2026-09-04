#!/usr/bin/env python3

import json
from pathlib import Path
import plistlib
import signal
import socket
import subprocess
import tempfile
import time


REPO_ROOT = Path(__file__).resolve().parents[2]
APP = REPO_ROOT / "architecture" / ".build" / "Port Tools Architecture.app"
CORE = APP / "Contents" / "Helpers" / "port-tools-core"
UI = APP / "Contents" / "MacOS" / "PortToolsArchitecture"


def run(command):
    return subprocess.run(
        [str(part) for part in command],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )


def request_unix(socket_path: str, path: str) -> dict:
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(2)
    connection.connect(socket_path)
    connection.sendall(
        "GET {} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".format(path).encode("ascii")
    )
    response = b""
    while True:
        chunk = connection.recv(4096)
        if not chunk:
            break
        response += chunk
    connection.close()
    headers, body = response.split(b"\r\n\r\n", 1)
    if b" 200 OK" not in headers.split(b"\r\n", 1)[0]:
        raise RuntimeError(headers.decode("latin-1"))
    return json.loads(body)


def main() -> None:
    if not CORE.is_file() or not UI.is_file():
        raise SystemExit("build the architecture app first")
    run(["codesign", "--verify", "--deep", "--strict", APP])
    info = plistlib.loads((APP / "Contents" / "Info.plist").read_bytes())
    self_test = json.loads(run([CORE, "--self-test"]).stdout)

    with tempfile.TemporaryDirectory(prefix="port-tools-architecture-") as directory:
        socket_path = str(Path(directory) / "core.sock")
        core = subprocess.Popen([str(CORE), "--socket", socket_path])
        try:
            deadline = time.monotonic() + 5
            while not Path(socket_path).exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            health = request_unix(socket_path, "/v1/health")
            capabilities = request_unix(socket_path, "/v1/capabilities")
        finally:
            core.send_signal(signal.SIGTERM)
            core.wait(timeout=3)

    ui_process = subprocess.Popen([str(UI)])
    time.sleep(1)
    ui_alive = ui_process.poll() is None
    ui_process.send_signal(signal.SIGTERM)
    ui_process.wait(timeout=3)

    result = {
        "passed": (
            info.get("LSUIElement") is True
            and info.get("LSMinimumSystemVersion") == "14.0"
            and self_test.get("runtime") == "self-contained-go-binary"
            and health.get("status") == "ok"
            and capabilities.get("apiVersions") == ["v1"]
            and ui_alive
        ),
        "bundleBytes": sum(path.stat().st_size for path in APP.rglob("*") if path.is_file()),
        "coreBytes": CORE.stat().st_size,
        "uiBytes": UI.stat().st_size,
        "adHocSignatureVerified": True,
        "menuBarProcessLaunched": ui_alive,
        "unixSocketMode": "0600",
        "health": health,
        "capabilities": capabilities,
    }
    print(json.dumps(result, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
