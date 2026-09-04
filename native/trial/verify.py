#!/usr/bin/env python3

import json
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import plistlib
import socket as socket_module
import subprocess
import tempfile
import threading
import time
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[2]
APP = REPO_ROOT / "native" / ".build" / "Port Tools.app"
EXECUTABLE = APP / "Contents" / "MacOS" / "PortTools"
CORE = APP / "Contents" / "Helpers" / "port-tools-core"


def run(command):
    return subprocess.run(
        [str(part) for part in command],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )


class UpstreamHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"<!doctype html><title>Port Tools verification</title><p>port-tools-route-ok</p>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def verify_startup_retry() -> bool:
    blocker = socket_module.socket(socket_module.AF_INET, socket_module.SOCK_STREAM)
    blocker.setsockopt(socket_module.SOL_SOCKET, socket_module.SO_REUSEADDR, 1)
    blocker.bind(("127.0.0.1", 0))
    blocker.listen()
    proxy_port = blocker.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="port-tools-retry-") as directory:
        state_root = Path(directory)
        socket_path = state_root / "runtime" / "core.sock"
        environment = {
            **dict(os.environ),
            "PORT_TOOLS_STATE_ROOT": str(state_root),
            "PORT_TOOLS_PROXY_ADDRESS": f"127.0.0.1:{proxy_port}",
        }
        process = subprocess.Popen([str(EXECUTABLE)], env=environment)
        try:
            time.sleep(0.8)
            blocker.close()
            deadline = time.monotonic() + 6
            while time.monotonic() < deadline and not socket_path.exists() and process.poll() is None:
                time.sleep(0.05)
            return socket_path.exists() and process.poll() is None
        finally:
            blocker.close()
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


def main() -> None:
    run(["codesign", "--verify", "--deep", "--strict", APP])
    run(["codesign", "--verify", "--strict", CORE])
    info = plistlib.loads((APP / "Contents" / "Info.plist").read_bytes())
    capabilities = json.loads(run([CORE, "self-test"]).stdout)
    with tempfile.TemporaryDirectory(prefix="port-tools-native-") as directory:
        state_root = Path(directory)
        socket = state_root / "runtime" / "core.sock"
        environment = {
            **dict(os.environ),
            "PORT_TOOLS_STATE_ROOT": str(state_root),
            "PORT_TOOLS_PROXY_ADDRESS": "127.0.0.1:0",
        }
        process = subprocess.Popen([str(EXECUTABLE)], env=environment)
        upstream = ThreadingHTTPServer(("127.0.0.1", 0), UpstreamHandler)
        upstream_thread = threading.Thread(target=upstream.serve_forever, daemon=True)
        upstream_thread.start()
        try:
            deadline = time.monotonic() + 6
            while time.monotonic() < deadline and not socket.exists() and process.poll() is None:
                time.sleep(0.05)
            alive = process.poll() is None
            scan = json.loads(run([CORE, "request", "--socket", socket, "--path", "/v1/services"]).stdout)
            scanned_services = scan.get("services", [])
            presentation_roles_valid = all(
                service.get("observation", {}).get("role") in {"page", "service"}
                for service in scanned_services
            )
            verification_service = next(
                (service for service in scanned_services if service.get("listener", {}).get("port") == upstream.server_port),
                None,
            )
            verification_fixture_is_page = (
                verification_service is not None
                and verification_service.get("observation", {}).get("role") == "page"
            )
            route_body = json.dumps({
                "port": upstream.server_port,
                "scheme": "http",
                "hostMode": "rewrite",
                "projectRoot": "/verification/project",
                "applicationRoot": "/verification/project",
            })
            route = json.loads(run([
                CORE, "request", "--socket", socket, "--method", "PUT",
                "--path", "/v1/routes/verification", "--body", route_body,
            ]).stdout)
            proxy_port = urlparse(route["url"]).port
            connection = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=3)
            connection.request("GET", "/", headers={"Host": f"verification.localhost:{proxy_port}"})
            response = connection.getresponse()
            route_proxy_passed = response.status == 200 and b"port-tools-route-ok" in response.read()
            connection.close()
            run([CORE, "request", "--socket", socket, "--method", "DELETE", "--path", "/v1/routes/verification"])
        finally:
            upstream.shutdown()
            upstream.server_close()
            process.terminate()
            process.wait(timeout=5)
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline and socket.exists():
            time.sleep(0.05)
        socket_removed = not socket.exists()

    startup_retry_passed = verify_startup_retry()
    result = {
        "passed": (
            info.get("LSUIElement") is True
            and info.get("CFBundleName") == "Port Tools"
            and EXECUTABLE.is_file()
            and CORE.is_file()
            and len(scan.get("services", [])) > 0
            and presentation_roles_valid
            and verification_fixture_is_page
            and alive
            and socket_removed
            and capabilities.get("runtime") == "self-contained-go-binary"
            and route_proxy_passed
            and startup_retry_passed
        ),
        "bundleBytes": sum(path.stat().st_size for path in APP.rglob("*") if path.is_file()),
        "menuBarProcessLaunched": alive,
        "scannerServices": len(scan.get("services", [])),
        "presentationRolesValid": presentation_roles_valid,
        "verificationFixtureIsPage": verification_fixture_is_page,
        "coreRuntime": capabilities.get("runtime"),
        "pythonBundled": any(APP.rglob("*.py")),
        "routeProxyPassed": route_proxy_passed,
        "startupRetryPassed": startup_retry_passed,
        "unixSocketCleanedUp": socket_removed,
        "adHocSignatureVerified": True,
    }
    print(json.dumps(result, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
