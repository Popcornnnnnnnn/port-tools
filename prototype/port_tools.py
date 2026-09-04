#!/usr/bin/env python3

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shlex
import socket
import ssl
import subprocess
import sys
from typing import Dict, List, Optional, Tuple


HTTP_STATUS = re.compile(rb"^HTTP/(?:1\.[01]|2) ([1-5][0-9]{2})(?: |\r?$)")
TITLE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
WEB_COMMAND_HINTS = (
    "vite",
    "next dev",
    "webpack-dev-server",
    "uvicorn",
    "gunicorn",
    "flask run",
    "django",
    "http.server",
)


def run_text(command: List[str]) -> str:
    completed = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    return completed.stdout.strip()


def discover_listeners() -> List[Dict[str, object]]:
    output = run_text(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-FpcuLn"])
    listeners = []
    process = {}
    seen = set()
    for line in output.splitlines():
        if not line:
            continue
        field, value = line[0], line[1:]
        if field == "p":
            process = {"pid": int(value)}
        elif field == "c":
            process["processName"] = value
        elif field == "u":
            process["uid"] = int(value)
        elif field == "L":
            process["owner"] = value
        elif field == "n" and process.get("uid") == os.getuid():
            endpoint = parse_endpoint(value)
            if endpoint is None:
                continue
            key = (process["pid"], endpoint["address"], endpoint["port"])
            if key in seen:
                continue
            seen.add(key)
            listeners.append(dict(process, **endpoint))
    return listeners


def parse_endpoint(value: str) -> Optional[Dict[str, object]]:
    if ":" not in value:
        return None
    address, raw_port = value.rsplit(":", 1)
    try:
        port = int(raw_port)
    except ValueError:
        return None
    if address.startswith("[") and address.endswith("]"):
        address = address[1:-1]
    if address in ("*", "0.0.0.0", "::"):
        scope = "all-interfaces"
    elif address in ("127.0.0.1", "::1"):
        scope = "loopback"
    else:
        scope = "interface"
    return {"address": address, "port": port, "bindScope": scope}


def process_metadata(pid: int) -> Dict[str, object]:
    command = run_text(["ps", "-p", str(pid), "-o", "command="])
    parent_text = run_text(["ps", "-p", str(pid), "-o", "ppid="])
    started = run_text(["ps", "-p", str(pid), "-o", "lstart="])
    cwd_output = run_text(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"])
    cwd = next((line[1:] for line in cwd_output.splitlines() if line.startswith("n")), None)
    metadata = {
        "command": command or None,
        "parentPid": int(parent_text) if parent_text.isdigit() else None,
        "started": started or None,
        "cwd": cwd,
    }
    if cwd:
        metadata["project"] = git_metadata(cwd)
    return metadata


def git_metadata(cwd: str) -> Optional[Dict[str, object]]:
    root = run_text(["git", "-C", cwd, "rev-parse", "--show-toplevel"])
    if not root:
        return None
    branch = run_text(["git", "-C", cwd, "branch", "--show-current"])
    common_dir = run_text(["git", "-C", cwd, "rev-parse", "--git-common-dir"])
    if common_dir and not os.path.isabs(common_dir):
        common_dir = str((Path(cwd) / common_dir).resolve())
    return {
        "root": root,
        "name": Path(root).name,
        "branch": branch or None,
        "commonGitDirectory": common_dir or None,
        "isWorktree": bool(common_dir and Path(common_dir).parent != Path(root)),
    }


def receive_response(sock: socket.socket) -> bytes:
    chunks = []
    remaining = 65536
    while remaining > 0:
        try:
            chunk = sock.recv(min(8192, remaining))
        except socket.timeout:
            break
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def request_bytes(port: int) -> bytes:
    return (
        "GET / HTTP/1.1\r\n"
        "Host: localhost:{}\r\n"
        "User-Agent: port-tools-spike/0.1\r\n"
        "Accept: text/html,*/*;q=0.1\r\n"
        "Connection: close\r\n\r\n"
    ).format(port).encode("ascii")


def connect_host(listener: Dict[str, object]) -> str:
    address = listener["address"]
    if address == "::1":
        return "::1"
    return "127.0.0.1"


def raw_probe(listener: Dict[str, object], use_tls: bool, verify_tls: bool = False) -> Tuple[bytes, Optional[str]]:
    host = connect_host(listener)
    port = int(listener["port"])
    try:
        with socket.create_connection((host, port), timeout=0.3) as plain:
            plain.settimeout(0.45)
            connection = plain
            if use_tls:
                context = ssl.create_default_context() if verify_tls else ssl._create_unverified_context()
                connection = context.wrap_socket(plain, server_hostname="localhost")
                connection.settimeout(0.45)
            connection.sendall(request_bytes(port))
            return receive_response(connection), None
    except ssl.SSLCertVerificationError as error:
        return b"", "untrusted-certificate:{}".format(error.verify_code)
    except (OSError, ssl.SSLError) as error:
        return b"", error.__class__.__name__


def parse_http_response(data: bytes) -> Optional[Dict[str, object]]:
    if not data:
        return None
    head, _, body = data.partition(b"\r\n\r\n")
    lines = head.split(b"\r\n")
    status_match = HTTP_STATUS.match(lines[0]) if lines else None
    if status_match is None:
        return None
    headers = {}
    for line in lines[1:]:
        key, separator, value = line.partition(b":")
        if separator:
            headers[key.decode("latin-1").lower()] = value.decode("latin-1").strip()
    body_text = body.decode("utf-8", errors="replace")
    title_match = TITLE.search(body_text)
    title = re.sub(r"\s+", " ", title_match.group(1)).strip() if title_match else None
    return {
        "status": int(status_match.group(1)),
        "contentType": headers.get("content-type"),
        "server": headers.get("server"),
        "title": title,
        "bytesRead": len(data),
    }


def probe_listener(listener: Dict[str, object]) -> Dict[str, object]:
    plain_data, plain_error = raw_probe(listener, use_tls=False)
    plain_http = parse_http_response(plain_data)
    if plain_http:
        return {
            "classification": "confirmed-web",
            "protocol": "http",
            "confidence": 1.0,
            "http": plain_http,
            "evidence": [{"kind": "valid-http-response", "value": plain_http["status"]}],
        }

    tls_data, tls_error = raw_probe(listener, use_tls=True)
    tls_http = parse_http_response(tls_data)
    if tls_http:
        _, verification_error = raw_probe(listener, use_tls=True, verify_tls=True)
        evidence = [
            {"kind": "tls-handshake", "value": "succeeded"},
            {"kind": "valid-http-response", "value": tls_http["status"]},
        ]
        if verification_error and verification_error.startswith("untrusted-certificate"):
            evidence.append({"kind": "untrusted-certificate", "value": verification_error})
        return {
            "classification": "confirmed-web",
            "protocol": "https",
            "confidence": 1.0,
            "http": tls_http,
            "evidence": evidence,
        }

    command = str(listener.get("command") or "").lower()
    hint = next((candidate for candidate in WEB_COMMAND_HINTS if candidate in command), None)
    if hint:
        return {
            "classification": "suspected-web",
            "protocol": "unknown",
            "confidence": 0.55,
            "evidence": [
                {"kind": "command-hint", "value": hint},
                {"kind": "probe-failed", "value": plain_error or tls_error or "no-response"},
            ],
        }
    if plain_data:
        sample = plain_data[:48].decode("utf-8", errors="replace")
        return {
            "classification": "non-web",
            "protocol": "tcp",
            "confidence": 0.9,
            "evidence": [{"kind": "invalid-http-response", "value": sample}],
        }
    return {
        "classification": "unknown",
        "protocol": "tcp",
        "confidence": 0.2,
        "evidence": [
            {"kind": "no-valid-http-response", "value": plain_error or tls_error or "no-response"}
        ],
    }


def relevance(listener: Dict[str, object]) -> Dict[str, object]:
    project = listener.get("project")
    command = str(listener.get("command") or "").lower()
    hint = next((candidate for candidate in WEB_COMMAND_HINTS if candidate in command), None)
    if project:
        return {
            "category": "developer-project",
            "developerRelevant": True,
            "confidence": 0.95,
            "evidence": [{"kind": "git-project", "value": project["root"]}],
        }
    if hint:
        return {
            "category": "developer-tool",
            "developerRelevant": True,
            "confidence": 0.7,
            "evidence": [{"kind": "command-hint", "value": hint}],
        }
    return {
        "category": "unattributed-web-endpoint",
        "developerRelevant": False,
        "confidence": 0.6,
        "evidence": [{"kind": "no-project-or-framework-evidence", "value": True}],
    }


def stable_id(listener: Dict[str, object]) -> str:
    identity = "{}:{}:{}".format(listener["pid"], listener["address"], listener["port"])
    return hashlib.sha256(identity.encode("utf-8")).hexdigest()[:12]


def scan() -> List[Dict[str, object]]:
    listeners = discover_listeners()
    metadata = {}
    for listener in listeners:
        pid = int(listener["pid"])
        if pid not in metadata:
            metadata[pid] = process_metadata(pid)
        listener.update(metadata[pid])

    with ThreadPoolExecutor(max_workers=min(24, max(1, len(listeners)))) as executor:
        probes = list(executor.map(probe_listener, listeners))
    services = []
    for listener, probe in zip(listeners, probes):
        services.append(
            {
                "id": stable_id(listener),
                "listener": {
                    "address": listener["address"],
                    "port": listener["port"],
                    "bindScope": listener["bindScope"],
                },
                "process": {
                    "pid": listener["pid"],
                    "parentPid": listener.get("parentPid"),
                    "name": listener.get("processName"),
                    "owner": listener.get("owner"),
                    "command": listener.get("command"),
                    "cwd": listener.get("cwd"),
                    "started": listener.get("started"),
                },
                "project": listener.get("project"),
                "observation": probe,
                "relevance": relevance(listener),
            }
        )
    return services


def group_id(service: Dict[str, object]) -> str:
    project = service.get("project") or {}
    identity = project.get("root")
    if not identity:
        identity = "process:{}".format(service["process"]["pid"])
    return hashlib.sha256(str(identity).encode("utf-8")).hexdigest()[:12]


def group_services(services: List[Dict[str, object]]) -> List[Dict[str, object]]:
    groups = {}
    order = []
    for service in services:
        identifier = group_id(service)
        if identifier not in groups:
            project = service.get("project") or {}
            label = project.get("name") or service["process"].get("name") or "unknown"
            groups[identifier] = {
                "id": identifier,
                "label": label,
                "project": service.get("project"),
                "serviceIds": [],
            }
            order.append(identifier)
        groups[identifier]["serviceIds"].append(service["id"])
    for group in groups.values():
        group["serviceIds"].sort(
            key=lambda service_id: next(
                int(service["listener"]["port"])
                for service in services
                if service["id"] == service_id
            )
        )
    return [groups[identifier] for identifier in order]


def document(services: List[Dict[str, object]]) -> Dict[str, object]:
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "host": socket.gethostname(),
        "services": services,
        "groups": group_services(services),
    }


def visible_services(services: List[Dict[str, object]]) -> List[Dict[str, object]]:
    return [
        service
        for service in services
        if service["observation"]["classification"] in ("confirmed-web", "suspected-web")
        and service["relevance"]["developerRelevant"]
    ]


def web_services(services: List[Dict[str, object]]) -> List[Dict[str, object]]:
    return [
        service
        for service in services
        if service["observation"]["classification"] in ("confirmed-web", "suspected-web")
    ]


def endpoint_summary(service: Dict[str, object]) -> str:
    observation = service["observation"]
    response = observation.get("http") or {}
    if response.get("title"):
        return html.unescape(response["title"])
    parts = []
    command = service["process"].get("command") or ""
    try:
        command_parts = shlex.split(command)
    except ValueError:
        command_parts = command.split()
    script = next(
        (
            Path(part).name
            for part in reversed(command_parts)
            if Path(part).suffix.lower() in (".js", ".mjs", ".cjs", ".ts", ".py", ".rb")
        ),
        None,
    )
    if script:
        parts.append(script)
    if response.get("status"):
        parts.append("HTTP {}".format(response["status"]))
    if response.get("contentType"):
        parts.append(response["contentType"].split(";", 1)[0])
    if parts:
        return " · ".join(parts)
    return ", ".join(item["kind"] for item in observation["evidence"])


def print_table(services: List[Dict[str, object]], show_all_web: bool = False) -> None:
    focused = web_services(services) if show_all_web else visible_services(services)
    by_id = {service["id"]: service for service in focused}
    print("DEVELOPMENT APPS" if not show_all_web else "WEB ENDPOINTS")
    for group in group_services(focused):
        project = group.get("project") or {}
        branch = " [{}]".format(project["branch"]) if project.get("branch") else ""
        print("\n{}{}".format(group["label"], branch))
        for service_id in group["serviceIds"]:
            service = by_id[service_id]
            observation = service["observation"]
            exposure = " · LAN" if service["listener"]["bindScope"] != "loopback" else ""
            print(
                "  :{:<5} {:<5} {}{}".format(
                    service["listener"]["port"],
                    observation["protocol"],
                    endpoint_summary(service),
                    exposure,
                )
            )
    web_count = len(web_services(services))
    if show_all_web:
        print("\n{} Web endpoints; {} non-Web/unknown listeners hidden".format(web_count, len(services) - web_count))
    else:
        print(
            "\n{} projects · {} services; {} unattributed Web endpoints and {} other listeners hidden".format(
                len(group_services(focused)), len(focused), web_count - len(focused), len(services) - web_count
            )
        )


def main() -> None:
    parser = argparse.ArgumentParser(prog="port-tools")
    subparsers = parser.add_subparsers(dest="command", required=True)
    scan_parser = subparsers.add_parser("scan")
    scan_parser.add_argument("--json", action="store_true")
    scan_parser.add_argument("--all", action="store_true")
    scan_parser.add_argument("--all-web", action="store_true")
    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("service_id")
    args = parser.parse_args()

    services = scan()
    if args.command == "inspect":
        service = next((item for item in services if item["id"] == args.service_id), None)
        if service is None:
            raise SystemExit("service not found in current scan: {}".format(args.service_id))
        print(json.dumps(service, indent=2, ensure_ascii=False))
    elif args.json:
        output = services if args.all else web_services(services) if args.all_web else visible_services(services)
        print(json.dumps(document(output), indent=2, ensure_ascii=False))
    else:
        print_table(services, show_all_web=args.all or args.all_web)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(0)
