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
PORTLESS_HELPER = APP / "Contents" / "Library" / "LaunchServices" / "port-tools-portless-helper"
PORTLESS_PLIST = APP / "Contents" / "Library" / "LaunchDaemons" / "PortlessHelper.plist"
SWIFT_SOURCES = sorted((REPO_ROOT / "native" / "PortTools").glob("*.swift"))


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


def verify_duplicate_instance_isolation(socket_path: Path, environment: dict, owner_process) -> dict:
    health_before = json.loads(run([
        CORE, "request", "--socket", socket_path, "--path", "/v1/health",
    ]).stdout)
    duplicate = subprocess.Popen(
        [str(EXECUTABLE)],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    exited = False
    try:
        try:
            duplicate.wait(timeout=5)
            exited = True
        except subprocess.TimeoutExpired:
            pass
        health_after = json.loads(run([
            CORE, "request", "--socket", socket_path, "--path", "/v1/health",
        ]).stdout)
        token_before = health_before.get("instanceToken")
        token_after = health_after.get("instanceToken")
        return {
            "passed": (
                exited
                and owner_process.poll() is None
                and socket_path.exists()
                and bool(token_before)
                and token_after == token_before
            ),
            "duplicateExited": exited,
            "ownerStillRunning": owner_process.poll() is None,
            "socketOwnerUnchanged": bool(token_before) and token_after == token_before,
        }
    finally:
        if duplicate.poll() is None:
            duplicate.terminate()
            duplicate.wait(timeout=5)


def verify_safe_stop(socket_path: Path) -> dict:
    reservation = socket_module.socket(socket_module.AF_INET, socket_module.SOCK_STREAM)
    reservation.bind(("127.0.0.1", 0))
    port = reservation.getsockname()[1]
    reservation.close()
    fixture = subprocess.Popen(
        [
            "python3",
            str(REPO_ROOT / "evaluation" / "fixtures" / "http_fixture.py"),
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
        ],
        cwd=str(REPO_ROOT),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                with socket_module.create_connection(("127.0.0.1", port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.05)
        services = json.loads(run([CORE, "request", "--socket", socket_path, "--path", "/v1/services"]).stdout)
        service = next(item for item in services["services"] if item["listener"]["port"] == port)
        plan = json.loads(run([
            CORE,
            "request",
            "--socket",
            socket_path,
            "--method",
            "POST",
            "--path",
            f"/v1/services/{service['id']}/stop-plan",
        ]).stdout)
        if plan.get("decision") != "eligible" or not plan.get("planToken"):
            return {"passed": False, "plan": plan}
        request_body = json.dumps({"planToken": plan["planToken"], "timeoutSeconds": 5})
        result = json.loads(run([
            CORE,
            "request",
            "--socket",
            socket_path,
            "--method",
            "POST",
            "--path",
            f"/v1/services/{service['id']}/graceful-stop",
            "--body",
            request_body,
        ]).stdout)
        fixture.wait(timeout=5)
        return {
            "passed": (
                result.get("success") is True
                and result.get("listenersReleased") is True
                and result.get("forceStopPerformed") is False
            ),
            "planTokenIssued": True,
            "signalSent": result.get("signalSent"),
            "listenersReleased": result.get("listenersReleased"),
            "forceStopPerformed": result.get("forceStopPerformed"),
        }
    finally:
        if fixture.poll() is None:
            fixture.terminate()
            fixture.wait(timeout=5)


def verify_portless_helper(proxy_port: int) -> dict:
    reservation = socket_module.socket(socket_module.AF_INET, socket_module.SOCK_STREAM)
    reservation.bind(("127.0.0.1", 0))
    helper_port = reservation.getsockname()[1]
    reservation.close()
    helper = subprocess.Popen(
        [
            str(PORTLESS_HELPER),
            "--listen-v4", f"127.0.0.1:{helper_port}",
            "--listen-v6", "",
            "--target", f"http://127.0.0.1:{proxy_port}",
        ],
        env={**dict(os.environ), "PORT_TOOLS_PORTLESS_TEST_MODE": "1"},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                with socket_module.create_connection(("127.0.0.1", helper_port), timeout=0.1):
                    break
            except OSError:
                if helper.poll() is not None:
                    return {"passed": False, "started": False}
                time.sleep(0.05)

        health_connection = http.client.HTTPConnection("127.0.0.1", helper_port, timeout=3)
        health_connection.request("GET", "/__port_tools/health", headers={"Host": "port-tools.localhost"})
        health_response = health_connection.getresponse()
        health = json.loads(health_response.read())
        health_connection.close()

        route_connection = http.client.HTTPConnection("127.0.0.1", helper_port, timeout=3)
        route_connection.request("GET", "/", headers={"Host": "verification.localhost"})
        route_response = route_connection.getresponse()
        route_body = route_response.read()
        route_connection.close()
        return {
            "passed": (
                health_response.status == 200
                and health.get("service") == "port-tools-portless-helper"
                and route_response.status == 200
                and b"port-tools-route-ok" in route_body
            ),
            "started": True,
            "healthStatus": health_response.status,
            "routeStatus": route_response.status,
        }
    finally:
        if helper.poll() is None:
            helper.terminate()
            helper.wait(timeout=5)


def main() -> None:
    run(["codesign", "--verify", "--deep", "--strict", APP])
    run(["codesign", "--verify", "--strict", CORE])
    run(["codesign", "--verify", "--strict", PORTLESS_HELPER])
    info = plistlib.loads((APP / "Contents" / "Info.plist").read_bytes())
    portless_plist = plistlib.loads(PORTLESS_PLIST.read_bytes())
    local_networking_allowed = (
        info.get("NSAppTransportSecurity", {}).get("NSAllowsLocalNetworking") is True
    )
    localhost_exception = (
        info.get("NSAppTransportSecurity", {})
        .get("NSExceptionDomains", {})
        .get("localhost", {})
    )
    localhost_subdomains_allowed = (
        localhost_exception.get("NSIncludesSubdomains") is True
        and localhost_exception.get("NSExceptionAllowsInsecureHTTPLoads") is True
    )
    helper_revision_is_declared = info.get("PortlessHelperRevision") == "1"
    expected_version = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()
    swift_source = "\n".join(path.read_text(encoding="utf-8") for path in SWIFT_SOURCES)
    title_hover_contract_passed = all(
        fragment in swift_source
        for fragment in (
            "idealWidth > renderedWidth + 1",
            "DispatchQueue.main.asyncAfter(deadline: .now() + 1.0",
            ".onHover(perform: handleHover)",
            "if isVisible || forcesTooltipForPreview",
        )
    )
    runtime_age_single_line_passed = all(
        fragment in swift_source
        for fragment in (
            "private struct RuntimeAgeLabel: View",
            ".lineLimit(1)",
            ".fixedSize(horizontal: true, vertical: false)",
        )
    )
    portless_test_isolation_passed = all(
        fragment in swift_source
        for fragment in (
            'ProcessInfo.processInfo.environment["PORT_TOOLS_DISABLE_PORTLESS"] == "1"',
            "if isDisabledForTests",
        )
    )
    capabilities = json.loads(run([CORE, "self-test"]).stdout)
    portless_capabilities = json.loads(run([PORTLESS_HELPER, "--self-test"]).stdout)
    portless_packaging_passed = (
        portless_plist.get("Label") == "xyz.popcornnn.PortTools.PortlessHelper"
        and portless_plist.get("BundleProgram") == "Contents/Library/LaunchServices/port-tools-portless-helper"
        and portless_plist.get("AssociatedBundleIdentifiers") == ["xyz.popcornnn.PortTools"]
        and portless_capabilities.get("service") == "port-tools-portless-helper"
        and portless_capabilities.get("version") == expected_version
    )
    with tempfile.TemporaryDirectory(prefix="port-tools-native-") as directory:
        state_root = Path(directory)
        socket = state_root / "runtime" / "core.sock"
        environment = {
            **dict(os.environ),
            "PORT_TOOLS_STATE_ROOT": str(state_root),
            "PORT_TOOLS_PROXY_ADDRESS": "127.0.0.1:0",
            "PORT_TOOLS_DISABLE_PORTLESS": "1",
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
            duplicate_instance = verify_duplicate_instance_isolation(socket, environment, process)
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
            portless_setting = json.loads(run([
                CORE, "request", "--socket", socket, "--method", "PUT",
                "--path", "/v1/settings/public-port", "--body", json.dumps({"port": 80}),
            ]).stdout)
            portless_routes = json.loads(run([
                CORE, "request", "--socket", socket, "--path", "/v1/routes",
            ]).stdout)
            portless_route_url = next(
                item["url"] for item in portless_routes["routes"] if item["alias"] == "verification"
            )
            run([
                CORE, "request", "--socket", socket, "--method", "PUT",
                "--path", "/v1/settings/public-port", "--body", json.dumps({"port": 0}),
            ])
            fallback_routes = json.loads(run([
                CORE, "request", "--socket", socket, "--path", "/v1/routes",
            ]).stdout)
            route = next(item for item in fallback_routes["routes"] if item["alias"] == "verification")
            portless_url_switch_passed = (
                portless_setting.get("portless") is True
                and portless_route_url == "http://verification.localhost"
            )
            proxy_port = urlparse(route["url"]).port
            portless_helper_runtime = verify_portless_helper(proxy_port)
            connection = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=3)
            connection.request("GET", "/", headers={"Host": f"verification.localhost:{proxy_port}"})
            response = connection.getresponse()
            route_proxy_passed = response.status == 200 and b"port-tools-route-ok" in response.read()
            connection.close()
            run([CORE, "request", "--socket", socket, "--method", "DELETE", "--path", "/v1/routes/verification"])
            safe_stop = verify_safe_stop(socket)
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
            and info.get("CFBundleShortVersionString") == expected_version
            and local_networking_allowed
            and localhost_subdomains_allowed
            and helper_revision_is_declared
            and EXECUTABLE.is_file()
            and CORE.is_file()
            and len(scan.get("services", [])) > 0
            and presentation_roles_valid
            and verification_fixture_is_page
            and alive
            and socket_removed
            and capabilities.get("runtime") == "self-contained-go-binary"
            and capabilities.get("version") == expected_version
            and "safe-stop" in capabilities.get("capabilities", [])
            and "portless-public-urls" in capabilities.get("capabilities", [])
            and route_proxy_passed
            and startup_retry_passed
            and duplicate_instance.get("passed") is True
            and safe_stop.get("passed") is True
            and title_hover_contract_passed
            and runtime_age_single_line_passed
            and portless_test_isolation_passed
            and portless_packaging_passed
            and portless_url_switch_passed
            and portless_helper_runtime.get("passed") is True
        ),
        "bundleBytes": sum(path.stat().st_size for path in APP.rglob("*") if path.is_file()),
        "menuBarProcessLaunched": alive,
        "scannerServices": len(scan.get("services", [])),
        "presentationRolesValid": presentation_roles_valid,
        "verificationFixtureIsPage": verification_fixture_is_page,
        "coreRuntime": capabilities.get("runtime"),
        "appVersion": info.get("CFBundleShortVersionString"),
        "coreVersion": capabilities.get("version"),
        "pythonBundled": any(APP.rglob("*.py")),
        "routeProxyPassed": route_proxy_passed,
        "startupRetryPassed": startup_retry_passed,
        "duplicateInstanceIsolationPassed": duplicate_instance.get("passed"),
        "duplicateInstance": duplicate_instance,
        "safeStopPassed": safe_stop.get("passed"),
        "safeStop": safe_stop,
        "titleHoverContractPassed": title_hover_contract_passed,
        "runtimeAgeSingleLinePassed": runtime_age_single_line_passed,
        "portlessTestIsolationPassed": portless_test_isolation_passed,
        "portlessHelperPackaged": portless_packaging_passed,
        "localNetworkingAllowed": local_networking_allowed,
        "localhostSubdomainsAllowed": localhost_subdomains_allowed,
        "portlessHelperRevisionDeclared": helper_revision_is_declared,
        "portlessURLSwitchPassed": portless_url_switch_passed,
        "portlessHelperRuntimePassed": portless_helper_runtime.get("passed"),
        "portlessHelperRuntime": portless_helper_runtime,
        "unixSocketCleanedUp": socket_removed,
        "adHocSignatureVerified": True,
    }
    print(json.dumps(result, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
