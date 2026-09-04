#!/usr/bin/env python3

import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = Path(__file__).resolve().parent
RUNTIME_ROOT = FIXTURE_ROOT / ".runtime"
MANAGER = FIXTURE_ROOT / "manage.py"
CLI = REPO_ROOT / "bin" / "port-tools"
PROXY_PORT = 17890
STATE = RUNTIME_ROOT / "proxy-routes.json"


def run(command, capture: bool = True):
    return subprocess.run(
        [str(part) for part in command],
        cwd=str(REPO_ROOT),
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.PIPE if capture else subprocess.DEVNULL,
        text=True,
        check=True,
    )


def wait_for_port(port: int, expected: bool, timeout: float = 8.0) -> None:
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


def request(alias: str, path: str = "/", method: str = "GET", body: bytes = None, headers=None):
    connection = http.client.HTTPConnection("127.0.0.1", PROXY_PORT, timeout=4)
    request_headers = {"Host": "{}.localhost:{}".format(alias, PROXY_PORT)}
    request_headers.update(headers or {})
    connection.request(method, path, body=body, headers=request_headers)
    response = connection.getresponse()
    payload = response.read()
    result = {
        "status": response.status,
        "headers": {key.lower(): value for key, value in response.getheaders()},
        "body": payload,
    }
    connection.close()
    return result


def timed_body(alias: str, path: str, first_size: int):
    connection = http.client.HTTPConnection("127.0.0.1", PROXY_PORT, timeout=4)
    started = time.monotonic()
    connection.request("GET", path, headers={"Host": "{}.localhost:{}".format(alias, PROXY_PORT)})
    response = connection.getresponse()
    first = response.read(first_size)
    first_elapsed = time.monotonic() - started
    rest = response.read()
    total_elapsed = time.monotonic() - started
    connection.close()
    return first + rest, first_elapsed, total_elapsed


def add_alias(
    alias: str,
    port: int,
    host_mode: str = "rewrite",
    scheme: str = "http",
    tls_policy: str = "verify",
) -> None:
    run(
        [
            CLI,
            "alias",
            "add",
            alias,
            port,
            "--host-mode",
            host_mode,
            "--upstream-scheme",
            scheme,
            "--tls-policy",
            tls_policy,
            "--state",
            STATE,
        ]
    )


def remove_alias(alias: str) -> None:
    run([CLI, "alias", "remove", alias, "--state", STATE])


def vite_websocket() -> bool:
    client = request("vite", "/@vite/client")["body"].decode("utf-8")
    token = re.search(r'const wsToken = "([^"]+)"', client).group(1)
    handshake = (
        "GET /?token={} HTTP/1.1\r\n"
        "Host: vite.localhost:{}\r\n"
        "Origin: http://vite.localhost:{}\r\n"
        "Connection: Upgrade\r\n"
        "Upgrade: websocket\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "Sec-WebSocket-Key: MDEyMzQ1Njc4OWFiY2RlZg==\r\n"
        "Sec-WebSocket-Protocol: vite-hmr\r\n\r\n"
    ).format(token, PROXY_PORT, PROXY_PORT)
    connection = socket.create_connection(("127.0.0.1", PROXY_PORT), timeout=2)
    connection.sendall(handshake.encode("ascii"))
    connection.settimeout(2)
    response = connection.recv(2048).decode("latin-1")
    connection.close()
    return response.startswith("HTTP/1.1 101") and "vite-hmr" in response.lower()


def main() -> None:
    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
    run(["python3", MANAGER, "start", "static-http"])
    run(["python3", MANAGER, "start", "vite-hmr"])
    run(["python3", MANAGER, "start", "self-signed-https"])
    STATE.unlink(missing_ok=True)
    add_alias("static", 51739)
    add_alias("vite", 51742)

    log_handle = (RUNTIME_ROOT / "proxy.log").open("ab", buffering=0)
    proxy = subprocess.Popen(
        [str(CLI), "proxy", "--listen", "127.0.0.1:{}".format(PROXY_PORT), "--state", str(STATE)],
        cwd=str(REPO_ROOT),
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    results = {}
    completed = False
    try:
        wait_for_port(PROXY_PORT, expected=True)
        results["static_html"] = request("static")["status"] == 200
        results["unknown_alias"] = request("unknown")["status"] == 404
        rewritten = json.loads(request("static", "/inspect")["body"])
        results["host_rewrite"] = (
            rewritten["host"] == "127.0.0.1:51739"
            and rewritten["x_forwarded_host"] == "static.localhost:17890"
        )
        add_alias("preserve", 51739, host_mode="preserve")
        preserved = json.loads(request("preserve", "/inspect")["body"])
        results["host_preserve"] = preserved["host"] == "preserve.localhost:17890"
        add_alias("secure", 51741, scheme="https", tls_policy="insecure-local")
        results["https_upstream"] = request("secure")["status"] == 200
        add_alias("secure-verify", 51741, scheme="https", tls_policy="verify")
        results["https_verification"] = request("secure-verify")["status"] == 502

        add_alias("missing", 59999)
        missing = request("missing")
        results["missing_upstream"] = missing["status"] == 502 and b"127.0.0.1:59999" in missing["body"]

        external = request("static", "/external-redirect")
        results["external_redirect_not_followed"] = (
            external["status"] == 302
            and external["headers"].get("location") == "https://example.invalid/fixture-target"
        )
        results["relative_redirect"] = request("static", "/redirect")["status"] == 302
        results["cookie"] = "fixture=present" in request("static", "/cookie")["headers"].get("set-cookie", "")
        sse_body, sse_first, sse_total = timed_body("static", "/events", 26)
        results["sse"] = sse_body == b"event: ready\ndata: first\n\nevent: complete\ndata: second\n\n"
        results["sse_first_chunk"] = sse_first < 0.18 and sse_total >= 0.2
        stream_body, stream_first, stream_total = timed_body("static", "/stream", 10)
        results["stream"] = stream_body == b"chunk-one\nchunk-two\n"
        results["stream_first_chunk"] = stream_first < 0.18 and stream_total >= 0.2

        upload = b"port-tools-upload" * 65536
        uploaded = json.loads(request("static", "/upload", "POST", upload)["body"])
        results["large_upload"] = (
            uploaded["bytes"] == len(upload)
            and uploaded["sha256"] == hashlib.sha256(upload).hexdigest()
        )
        results["vite_websocket"] = vite_websocket()

        add_alias("dynamic", 51739)
        results["atomic_add"] = request("dynamic")["status"] == 200
        remove_alias("dynamic")
        results["atomic_remove"] = request("dynamic")["status"] == 404

        long_stream = {}

        def read_long_stream() -> None:
            long_stream["body"] = request("static", "/long-stream")["body"]

        reader = threading.Thread(target=read_long_stream)
        reader.start()
        time.sleep(0.1)
        for index in range(8):
            update_alias = "update-{}".format(index)
            add_alias(update_alias, 51739)
            remove_alias(update_alias)
        reader.join(timeout=4)
        expected_long_stream = b"".join(
            "chunk-{0:02d}\n".format(index).encode("ascii") for index in range(20)
        )
        results["route_updates_preserve_stream"] = long_stream.get("body") == expected_long_stream

        lsof = run(["lsof", "-nP", "-iTCP:{}".format(PROXY_PORT), "-sTCP:LISTEN"]).stdout
        results["loopback_only"] = "127.0.0.1:{} (LISTEN)".format(PROXY_PORT) in lsof and "*:" not in lsof
        passed = all(results.values())
        completed = passed
        print(json.dumps({"passed": passed, "results": results}, indent=2))
        if not passed:
            raise SystemExit(1)
    finally:
        if proxy.poll() is None:
            os.killpg(proxy.pid, signal.SIGTERM)
            proxy.wait(timeout=4)
        wait_for_port(PROXY_PORT, expected=False, timeout=2)
        run(["python3", MANAGER, "stop", "static-http"])
        run(["python3", MANAGER, "stop", "vite-hmr"])
        run(["python3", MANAGER, "stop", "self-signed-https"])
        log_handle.close()
        if completed:
            shutil.rmtree(RUNTIME_ROOT, ignore_errors=True)
        else:
            print(
                json.dumps({"failureArtifactsRetained": str(RUNTIME_ROOT)}),
                file=sys.stderr,
            )


if __name__ == "__main__":
    main()
