#!/usr/bin/env python3

import argparse
import base64
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import struct
import subprocess
import threading
import time


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = Path(__file__).resolve().parent
RUNTIME_ROOT = FIXTURE_ROOT / ".runtime"
ENDURANCE_ROOT = RUNTIME_ROOT / "hmr-endurance"
CLI = REPO_ROOT / "bin" / "port-tools"
PROXY_PORT = 17890
VITE_PORT = 51752
NEXT_PORT = 51753


def wait_for_port(port: int, expected: bool, timeout: float = 15.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                listening = True
        except OSError:
            listening = False
        if listening == expected:
            return
        time.sleep(0.1)
    raise RuntimeError("port {} did not reach listening={}".format(port, expected))


def copy_app(name: str) -> Path:
    source = FIXTURE_ROOT / name
    destination = ENDURANCE_ROOT / name
    shutil.copytree(
        source,
        destination,
        ignore=shutil.ignore_patterns("node_modules", ".next", "AGENTS.md", "CLAUDE.md"),
    )
    if name == "next":
        subprocess.run(
            ["cp", "-cR", str(source / "node_modules"), str(destination / "node_modules")],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
    else:
        os.symlink(source / "node_modules", destination / "node_modules", target_is_directory=True)
    return destination


def start_process(command, cwd: Path, log_name: str, environment=None):
    log = (ENDURANCE_ROOT / log_name).open("ab", buffering=0)
    merged_environment = os.environ.copy()
    merged_environment.update(environment or {})
    return subprocess.Popen(
        command,
        cwd=str(cwd),
        env=merged_environment,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )


def run_cli(arguments) -> None:
    subprocess.run(
        [str(CLI)] + [str(argument) for argument in arguments],
        cwd=str(REPO_ROOT),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )


def request(alias: str, path: str = "/") -> str:
    connection = http.client.HTTPConnection("127.0.0.1", PROXY_PORT, timeout=8)
    connection.request("GET", path, headers={"Host": "{}.localhost:{}".format(alias, PROXY_PORT)})
    response = connection.getresponse()
    body = response.read().decode("utf-8", errors="replace")
    connection.close()
    if response.status != 200:
        raise RuntimeError("{}{} returned {}".format(alias, path, response.status))
    return body


class WebSocketRecorder:
    def __init__(self, alias: str, path: str, subprotocol: str = "") -> None:
        self.socket = socket.create_connection(("127.0.0.1", PROXY_PORT), timeout=3)
        self.socket.settimeout(1)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        protocol_header = "Sec-WebSocket-Protocol: {}\r\n".format(subprotocol) if subprotocol else ""
        handshake = (
            "GET {} HTTP/1.1\r\n"
            "Host: {}.localhost:{}\r\n"
            "Origin: http://{}.localhost:{}\r\n"
            "Connection: Upgrade\r\n"
            "Upgrade: websocket\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "Sec-WebSocket-Key: {}\r\n"
            "{}\r\n"
        ).format(path, alias, PROXY_PORT, alias, PROXY_PORT, key, protocol_header)
        self.socket.sendall(handshake.encode("ascii"))
        received = b""
        while b"\r\n\r\n" not in received:
            received += self.socket.recv(4096)
        headers, self.buffer = received.split(b"\r\n\r\n", 1)
        status = headers.split(b"\r\n", 1)[0]
        if b" 101 " not in status:
            raise RuntimeError("{} websocket failed: {}".format(alias, status.decode("latin-1")))
        self.messages = []
        self.errors = []
        self.closed = False
        self.lock = threading.Lock()
        self.thread = threading.Thread(target=self._read_loop, daemon=True)
        self.thread.start()

    def _recv_exact(self, length: int) -> bytes:
        while len(self.buffer) < length:
            self.buffer += self.socket.recv(max(4096, length - len(self.buffer)))
        result, self.buffer = self.buffer[:length], self.buffer[length:]
        return result

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        mask = os.urandom(4)
        length = len(payload)
        if length < 126:
            header = bytes([0x80 | opcode, 0x80 | length])
        elif length < 65536:
            header = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack("!H", length)
        else:
            header = bytes([0x80 | opcode, 0x80 | 127]) + struct.pack("!Q", length)
        masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
        self.socket.sendall(header + mask + masked)

    def _read_loop(self) -> None:
        try:
            while not self.closed:
                try:
                    first, second = self._recv_exact(2)
                except socket.timeout:
                    continue
                opcode = first & 0x0F
                length = second & 0x7F
                if length == 126:
                    length = struct.unpack("!H", self._recv_exact(2))[0]
                elif length == 127:
                    length = struct.unpack("!Q", self._recv_exact(8))[0]
                masked = bool(second & 0x80)
                mask = self._recv_exact(4) if masked else None
                payload = self._recv_exact(length)
                if mask:
                    payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
                if opcode == 0x8:
                    self.closed = True
                elif opcode == 0x9:
                    self._send_frame(0xA, payload)
                elif opcode in (0x1, 0x2):
                    with self.lock:
                        self.messages.append(
                            payload.decode("utf-8", errors="replace") if opcode == 0x1 else "<binary>"
                        )
        except (OSError, ValueError) as error:
            if not self.closed:
                self.errors.append(type(error).__name__)
                self.closed = True

    def count(self) -> int:
        with self.lock:
            return len(self.messages)

    def wait_for_growth(self, previous_count: int, timeout: float = 12.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.count() > previous_count:
                return True
            if self.closed:
                return False
            time.sleep(0.1)
        return False

    def close(self) -> None:
        self.closed = True
        try:
            self._send_frame(0x8, b"")
        except OSError:
            pass
        self.socket.close()
        self.thread.join(timeout=2)


def write_vite_marker(root: Path, marker: str) -> None:
    (root / "src" / "main.js").write_text(
        "document.documentElement.dataset.fixture = 'port-tools-vite';\n"
        "document.querySelector('#status').textContent = '{}';\n"
        "if (import.meta.hot) {{ import.meta.hot.accept(); }}\n".format(marker),
        encoding="utf-8",
    )


def write_next_marker(root: Path, marker: str) -> None:
    (root / "app" / "page.js").write_text(
        "export default function Home() {{\n"
        "  return <main><h1>port-tools Next.js fixture</h1><p id=\"status\">{}</p></main>;\n"
        "}}\n".format(marker),
        encoding="utf-8",
    )


def wait_for_content(alias: str, path: str, marker: str, timeout: float = 15.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if marker in request(alias, path):
                return True
        except (OSError, RuntimeError):
            pass
        time.sleep(0.2)
    return False


def stop_process(process) -> None:
    if process and process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=2)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--duration", type=int, default=900)
    parser.add_argument("--heartbeat", type=int, default=30)
    args = parser.parse_args()
    if args.duration < 12:
        raise SystemExit("duration must be at least 12 seconds")

    telemetry_root = Path.home() / "Library" / "Preferences" / "nextjs-nodejs"
    telemetry_existed = telemetry_root.exists()
    if ENDURANCE_ROOT.exists():
        shutil.rmtree(ENDURANCE_ROOT)
    ENDURANCE_ROOT.mkdir(parents=True)
    vite_root = copy_app("vite")
    next_root = copy_app("next")
    state = ENDURANCE_ROOT / "routes.json"
    processes = []
    sockets = []
    results = {"updates": []}
    completed = False

    try:
        vite = start_process(
            ["npm", "run", "dev", "--", "--host", "127.0.0.1", "--port", str(VITE_PORT), "--strictPort"],
            vite_root,
            "vite.log",
        )
        next_server = start_process(
            ["npm", "run", "dev", "--", "--hostname", "127.0.0.1", "--port", str(NEXT_PORT)],
            next_root,
            "next.log",
            {"NEXT_TELEMETRY_DISABLED": "1"},
        )
        processes.extend([vite, next_server])
        wait_for_port(VITE_PORT, True)
        wait_for_port(NEXT_PORT, True)

        run_cli(["alias", "add", "vite-endurance", VITE_PORT, "--state", state])
        run_cli(["alias", "add", "next-endurance", NEXT_PORT, "--state", state])
        proxy = start_process(
            [str(CLI), "proxy", "--listen", "127.0.0.1:{}".format(PROXY_PORT), "--state", str(state)],
            REPO_ROOT,
            "proxy.log",
        )
        processes.append(proxy)
        wait_for_port(PROXY_PORT, True)

        if not wait_for_content("vite-endurance", "/", "port-tools Vite fixture", timeout=20):
            raise RuntimeError("Vite did not become HTTP-ready")
        if not wait_for_content("next-endurance", "/", "port-tools Next.js fixture", timeout=30):
            raise RuntimeError("Next.js did not become HTTP-ready")

        vite_client = request("vite-endurance", "/@vite/client")
        vite_token = re.search(r'const wsToken = "([^"]+)"', vite_client).group(1)
        next_page = request("next-endurance", "/")
        next_request_id = re.search(r'self\.__next_r="([^"]+)"', next_page).group(1)
        vite_socket = WebSocketRecorder(
            "vite-endurance", "/?token={}".format(vite_token), subprotocol="vite-hmr"
        )
        next_socket = WebSocketRecorder("next-endurance", "/_next/hmr?id={}".format(next_request_id))
        sockets.extend([vite_socket, next_socket])
        time.sleep(1)

        started = time.monotonic()
        schedule = sorted(set([1, args.duration // 3, (args.duration * 2) // 3, args.duration - 3]))
        update_index = 0
        next_heartbeat = args.heartbeat
        while time.monotonic() - started < args.duration:
            elapsed = int(time.monotonic() - started)
            if update_index < len(schedule) and elapsed >= schedule[update_index]:
                marker = "hmr-update-{}".format(update_index + 1)
                vite_before = vite_socket.count()
                next_before = next_socket.count()
                write_vite_marker(vite_root, marker)
                write_next_marker(next_root, marker)
                vite_http = wait_for_content("vite-endurance", "/src/main.js", marker)
                next_http = wait_for_content("next-endurance", "/", marker)
                vite_message = vite_socket.wait_for_growth(vite_before)
                next_message = next_socket.wait_for_growth(next_before)
                result = {
                    "elapsed": elapsed,
                    "marker": marker,
                    "viteHttp": vite_http,
                    "viteWebSocket": vite_message,
                    "nextHttp": next_http,
                    "nextWebSocket": next_message,
                }
                results["updates"].append(result)
                print(json.dumps({"event": "update", **result}), flush=True)
                update_index += 1
            if elapsed >= next_heartbeat:
                print(
                    json.dumps(
                        {
                            "event": "heartbeat",
                            "elapsed": elapsed,
                            "viteMessages": vite_socket.count(),
                            "nextMessages": next_socket.count(),
                            "viteClosed": vite_socket.closed,
                            "nextClosed": next_socket.closed,
                        }
                    ),
                    flush=True,
                )
                next_heartbeat += args.heartbeat
            if vite_socket.closed or next_socket.closed:
                break
            time.sleep(0.25)

        elapsed = int(time.monotonic() - started)
        results.update(
            {
                "durationSeconds": elapsed,
                "viteConnectionOpen": not vite_socket.closed,
                "nextConnectionOpen": not next_socket.closed,
                "viteErrors": vite_socket.errors,
                "nextErrors": next_socket.errors,
            }
        )
        passed = (
            elapsed >= args.duration
            and len(results["updates"]) == len(schedule)
            and all(
                update["viteHttp"]
                and update["viteWebSocket"]
                and update["nextHttp"]
                and update["nextWebSocket"]
                for update in results["updates"]
            )
            and results["viteConnectionOpen"]
            and results["nextConnectionOpen"]
        )
        results["passed"] = passed
        completed = passed
        print(json.dumps({"event": "complete", **results}, indent=2), flush=True)
        if not passed:
            raise SystemExit(1)
    finally:
        for web_socket in sockets:
            web_socket.close()
        for process in reversed(processes):
            stop_process(process)
        for port in (PROXY_PORT, VITE_PORT, NEXT_PORT):
            wait_for_port(port, False, timeout=3)
        if not telemetry_existed and telemetry_root.exists():
            generated_telemetry = ENDURANCE_ROOT / "generated-next-telemetry"
            shutil.move(str(telemetry_root), str(generated_telemetry))
        if completed:
            shutil.rmtree(ENDURANCE_ROOT, ignore_errors=True)
        else:
            print(
                json.dumps({"event": "failure-artifacts-retained", "path": str(ENDURANCE_ROOT)}),
                flush=True,
            )


if __name__ == "__main__":
    main()
