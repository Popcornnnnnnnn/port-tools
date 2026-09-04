#!/usr/bin/env python3

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import html
import json
import os
from pathlib import Path
import pwd
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
    "next-server",
    "webpack-dev-server",
    "uvicorn",
    "gunicorn",
    "flask run",
    "django",
    "http.server",
)
REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROUTE_STATE = REPO_ROOT / ".port-tools-spike" / "routes.json"
SHARED_RUNTIME_HINTS = (
    "com.docker.backend",
    "docker daemon",
    "dockerd",
    "launchd",
    "orbstack helper",
)


def run_text(command: List[str]) -> str:
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return ""
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
    project = git_metadata(cwd) if cwd else None
    evidence = "cwd" if project else None
    if project is None:
        candidates = project_candidates_from_command(command, cwd)
        if len(candidates) == 1:
            project = candidates[0]
            evidence = "command-path"
        elif len(candidates) > 1:
            metadata["projectCandidates"] = [candidate["root"] for candidate in candidates]
            evidence = "ambiguous-command-path"
    metadata["project"] = project
    metadata["projectEvidence"] = evidence
    return metadata


def process_snapshot() -> Dict[int, Dict[str, object]]:
    output = run_text(["ps", "-axo", "pid=,ppid=,user=,comm="])
    processes = {}
    for line in output.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) != 4 or not parts[0].isdigit() or not parts[1].isdigit():
            continue
        pid, parent_pid = int(parts[0]), int(parts[1])
        processes[pid] = {
            "pid": pid,
            "parentPid": parent_pid,
            "owner": parts[2],
            "name": Path(parts[3]).name,
        }
    return processes


def descendant_pids(root_pid: int, processes: Dict[int, Dict[str, object]]) -> List[int]:
    children = {}
    for process in processes.values():
        children.setdefault(process.get("parentPid"), []).append(int(process["pid"]))
    descendants = []
    pending = list(children.get(root_pid, []))
    while pending:
        pid = pending.pop(0)
        descendants.append(pid)
        pending.extend(children.get(pid, []))
    return descendants


def build_stop_plan(
    service: Dict[str, object],
    processes: Dict[int, Dict[str, object]],
    listeners: List[Dict[str, object]],
    current_user: str,
) -> Dict[str, object]:
    target = service["process"]
    root_pid = int(target["pid"])
    project = service.get("project") or {}
    project_root = project.get("root")
    management = service.get("management") or {"source": "unmanaged"}
    root_snapshot = processes.get(root_pid)
    reasons = []

    if target.get("owner") != current_user:
        reasons.append("target is not owned by the current user")
    if root_snapshot is None:
        reasons.append("target PID no longer exists")
    elif root_snapshot.get("owner") != current_user:
        reasons.append("current PID owner does not match the scanned owner")
    elif target.get("started") and root_snapshot.get("started") != target.get("started"):
        reasons.append("PID identity changed since the service was scanned")
    elif target.get("command") and root_snapshot.get("command") != target.get("command"):
        reasons.append("process command changed since the service was scanned")
    if management.get("source") == "docker":
        reasons.append("Docker-published services must be managed through the container, not its daemon")
    if not project_root:
        reasons.append("target has no unambiguous Git-project ownership evidence")
    identity_text = "{} {}".format(target.get("name") or "", target.get("command") or "").lower()
    if any(hint in identity_text for hint in SHARED_RUNTIME_HINTS):
        reasons.append("target appears to be a shared or system runtime")

    descendants = descendant_pids(root_pid, processes) if root_snapshot else []
    included = []
    exclusions = []
    for pid in [root_pid] + descendants:
        process = dict(processes.get(pid) or {"pid": pid})
        if pid == root_pid:
            process.update(
                {
                    "owner": target.get("owner"),
                    "name": target.get("name"),
                    "command": target.get("command"),
                    "cwd": target.get("cwd"),
                    "projectRoot": project_root,
                }
            )
        owner = process.get("owner")
        child_project_root = process.get("projectRoot")
        exclusion_reason = None
        if owner != current_user:
            exclusion_reason = "different owner"
        elif pid != root_pid and child_project_root != project_root:
            exclusion_reason = "same-project ownership not established"
        if exclusion_reason:
            exclusions.append({**process, "reason": exclusion_reason})
        else:
            included.append(process)

    included_pids = {int(process["pid"]) for process in included}
    expected_listeners = [
        {
            "pid": int(listener["pid"]),
            "address": listener["address"],
            "port": int(listener["port"]),
        }
        for listener in listeners
        if int(listener["pid"]) in included_pids
    ]
    signal_order = [pid for pid in reversed(descendants) if pid in included_pids]
    if root_pid in included_pids:
        signal_order.append(root_pid)

    return {
        "schemaVersion": 1,
        "mode": "dry-run",
        "signalSent": False,
        "decision": "refused" if reasons else "eligible",
        "reasons": reasons,
        "service": {
            "id": service["id"],
            "listener": service["listener"],
            "projectRoot": project_root,
            "managementSource": management.get("source", "unknown"),
        },
        "rootProcess": included[0] if included and included[0]["pid"] == root_pid else target,
        "descendants": [process for process in included if process["pid"] != root_pid],
        "exclusions": exclusions,
        "gracefulPlan": {
            "signal": "SIGTERM",
            "pids": signal_order if not reasons else [],
            "verifyListenersReleased": expected_listeners,
        },
        "forcePlan": {
            "signal": "SIGKILL",
            "allowedInThisAction": False,
            "requiresSeparateExplicitAction": True,
        },
    }


def stop_dry_run(service: Dict[str, object]) -> Dict[str, object]:
    processes = process_snapshot()
    root_pid = int(service["process"]["pid"])
    tree_pids = [root_pid] + descendant_pids(root_pid, processes)
    for pid in tree_pids:
        process = processes.get(pid)
        if process is None:
            continue
        metadata = process_metadata(pid)
        process.update(
            {
                "command": metadata.get("command"),
                "cwd": metadata.get("cwd"),
                "started": metadata.get("started"),
                "projectRoot": (metadata.get("project") or {}).get("root"),
            }
        )
    return build_stop_plan(
        service,
        processes,
        discover_listeners(),
        pwd.getpwuid(os.getuid()).pw_name,
    )


def print_stop_plan(plan: Dict[str, object]) -> None:
    root = plan["rootProcess"]
    listener = plan["service"]["listener"]
    graceful = plan["gracefulPlan"]
    print("SAFE STOP DRY RUN")
    print("Decision: {}".format(plan["decision"].upper()))
    print("Service: {} at {}:{}".format(plan["service"]["id"], listener["address"], listener["port"]))
    print("Project: {}".format(plan["service"].get("projectRoot") or "unverified"))
    print("Owner: {}".format(root.get("owner") or "unknown"))
    print("Root PID: {} ({})".format(root.get("pid"), root.get("name") or "unknown"))
    descendant_text = ", ".join(str(item["pid"]) for item in plan["descendants"]) or "none"
    print("Owned descendants: {}".format(descendant_text))
    signal_text = ", ".join(str(pid) for pid in graceful["pids"]) or "none"
    print("Graceful plan: SIGTERM -> {}".format(signal_text))
    listeners = graceful["verifyListenersReleased"]
    listener_text = ", ".join("{}:{}".format(item["address"], item["port"]) for item in listeners) or "none"
    print("Verify released: {}".format(listener_text))
    if plan["exclusions"]:
        print("Exclusions:")
        for exclusion in plan["exclusions"]:
            print("  PID {}: {}".format(exclusion["pid"], exclusion["reason"]))
    if plan["reasons"]:
        print("Refusal reasons:")
        for reason in plan["reasons"]:
            print("  - {}".format(reason))
    print("Force plan: unavailable; requires a separate explicit action")
    print("No signal was sent.")


def project_candidates_from_command(command: str, cwd: Optional[str]) -> List[Dict[str, object]]:
    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.split()
    projects = []
    seen = set()
    for part in parts:
        if part.startswith("-"):
            continue
        candidate = Path(part)
        if not candidate.is_absolute() and cwd:
            candidate = Path(cwd) / candidate
        if not candidate.exists():
            continue
        search_path = candidate if candidate.is_dir() else candidate.parent
        project = git_metadata(str(search_path))
        if project and project["root"] not in seen:
            seen.add(project["root"])
            projects.append(project)
    return projects


def project_from_command(command: str, cwd: Optional[str]) -> Optional[Dict[str, object]]:
    candidates = project_candidates_from_command(command, cwd)
    return candidates[0] if len(candidates) == 1 else None


def git_metadata(cwd: str) -> Optional[Dict[str, object]]:
    root = run_text(["git", "-C", cwd, "rev-parse", "--show-toplevel"])
    if not root:
        return None
    branch = run_text(["git", "-C", cwd, "branch", "--show-current"])
    common_dir = run_text(["git", "-C", cwd, "rev-parse", "--git-common-dir"])
    if common_dir and not os.path.isabs(common_dir):
        common_dir = str((Path(cwd) / common_dir).resolve())
    repository_root = str(Path(common_dir).parent) if common_dir else root
    is_worktree = Path(repository_root) != Path(root)
    return {
        "root": root,
        "name": Path(repository_root).name,
        "repositoryRoot": repository_root,
        "repositoryName": Path(repository_root).name,
        "worktreeName": Path(root).name,
        "branch": branch or None,
        "commonGitDirectory": common_dir or None,
        "isWorktree": is_worktree,
    }


def docker_port_metadata() -> Dict[int, Dict[str, object]]:
    container_ids = run_text(["docker", "ps", "-q"]).splitlines()
    if not container_ids:
        return {}
    try:
        completed = subprocess.run(
            ["docker", "inspect"] + container_ids,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
        containers = json.loads(completed.stdout) if completed.returncode == 0 else []
    except (FileNotFoundError, json.JSONDecodeError):
        return {}
    ports = {}
    for container in containers:
        config = container.get("Config") or {}
        labels = config.get("Labels") or {}
        for container_port, bindings in (container.get("NetworkSettings", {}).get("Ports") or {}).items():
            for binding in bindings or []:
                try:
                    host_port = int(binding["HostPort"])
                except (KeyError, TypeError, ValueError):
                    continue
                ports[host_port] = {
                    "source": "docker",
                    "containerId": container.get("Id", "")[:12],
                    "containerName": str(container.get("Name") or "").lstrip("/"),
                    "image": config.get("Image"),
                    "containerPort": container_port,
                    "labels": labels,
                }
    return ports


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


def raw_probe(
    listener: Dict[str, object],
    use_tls: bool,
    verify_tls: bool = False,
    read_timeout: float = 0.45,
) -> Tuple[bytes, Optional[str]]:
    host = connect_host(listener)
    port = int(listener["port"])
    try:
        with socket.create_connection((host, port), timeout=0.3) as plain:
            plain.settimeout(read_timeout)
            connection = plain
            if use_tls:
                context = ssl.create_default_context() if verify_tls else ssl._create_unverified_context()
                connection = context.wrap_socket(plain, server_hostname="localhost")
                connection.settimeout(read_timeout)
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


def detect_framework(listener: Dict[str, object], data: bytes) -> Optional[str]:
    command = str(listener.get("command") or "").lower()
    body = data.partition(b"\r\n\r\n")[2].lower()
    if b"/@vite/client" in body or "vite" in command:
        return "vite"
    if b"/_next/" in body or "next dev" in command or "next-server" in command:
        return "next"
    if b'"framework":"fastapi"' in body or ("uvicorn" in command and "app:app" in command):
        return "fastapi"
    return None


def redis_response(data: bytes) -> bool:
    return data.startswith((b"-ERR", b"-DENIED", b"+PONG")) and (
        b"unknown command" in data.lower()
        or b"wrong number of arguments" in data.lower()
        or b"redis" in data.lower()
        or data.startswith(b"+PONG")
    )


def redis_candidate(listener: Dict[str, object]) -> bool:
    management = listener.get("management") or {}
    values = (
        listener.get("processName"),
        listener.get("command"),
        management.get("containerName"),
        management.get("image"),
    )
    return any("redis" in str(value).lower() for value in values if value)


def redis_probe(listener: Dict[str, object]) -> bytes:
    try:
        with socket.create_connection((connect_host(listener), int(listener["port"])), timeout=0.3) as connection:
            connection.settimeout(0.45)
            connection.sendall(b"*1\r\n$4\r\nPING\r\n")
            return receive_response(connection)
    except OSError:
        return b""


def probe_listener(listener: Dict[str, object]) -> Dict[str, object]:
    plain_data, plain_error = raw_probe(listener, use_tls=False)
    command = str(listener.get("command") or "").lower()
    if not plain_data and any(hint in command for hint in WEB_COMMAND_HINTS):
        plain_data, plain_error = raw_probe(listener, use_tls=False, read_timeout=1.2)
    plain_http = parse_http_response(plain_data)
    if plain_http:
        framework = detect_framework(listener, plain_data)
        evidence = [{"kind": "valid-http-response", "value": plain_http["status"]}]
        if framework:
            evidence.append({"kind": "framework-marker", "value": framework})
        return {
            "classification": "confirmed-web",
            "protocol": "http",
            "confidence": 1.0,
            "http": plain_http,
            "framework": framework,
            "evidence": evidence,
        }

    redis_data = plain_data
    if not redis_data and redis_candidate(listener):
        redis_data = redis_probe(listener)
    if redis_response(redis_data):
        return {
            "classification": "non-web",
            "protocol": "redis",
            "confidence": 0.99,
            "evidence": [
                {
                    "kind": "redis-response",
                    "value": redis_data[:96].decode("utf-8", errors="replace"),
                }
            ],
        }

    tls_data, tls_error = raw_probe(listener, use_tls=True)
    tls_http = parse_http_response(tls_data)
    if tls_http:
        framework = detect_framework(listener, tls_data)
        _, verification_error = raw_probe(listener, use_tls=True, verify_tls=True)
        evidence = [
            {"kind": "tls-handshake", "value": "succeeded"},
            {"kind": "valid-http-response", "value": tls_http["status"]},
        ]
        if verification_error and verification_error.startswith("untrusted-certificate"):
            evidence.append({"kind": "untrusted-certificate", "value": verification_error})
        if framework:
            evidence.append({"kind": "framework-marker", "value": framework})
        return {
            "classification": "confirmed-web",
            "protocol": "https",
            "confidence": 1.0,
            "http": tls_http,
            "framework": framework,
            "evidence": evidence,
        }

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
    management = listener.get("management") or {}
    command = str(listener.get("command") or "").lower()
    hint = next((candidate for candidate in WEB_COMMAND_HINTS if candidate in command), None)
    if management.get("source") == "docker":
        return {
            "category": "developer-container",
            "developerRelevant": True,
            "confidence": 0.9,
            "evidence": [
                {"kind": "docker-published-port", "value": management.get("containerName")}
            ],
        }
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
    docker_ports = docker_port_metadata()
    for listener in listeners:
        pid = int(listener["pid"])
        if pid not in metadata:
            metadata[pid] = process_metadata(pid)
        listener.update(metadata[pid])
        management = docker_ports.get(int(listener["port"]))
        if management:
            listener["management"] = management
            labels = management.get("labels", {})
            project_root = labels.get("com.docker.compose.project.working_dir") or labels.get(
                "dev.port-tools.project-root"
            )
            if project_root:
                listener["project"] = git_metadata(project_root)
                listener["projectEvidence"] = "docker-compose-working-directory"

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
                "projectEvidence": listener.get("projectEvidence"),
                "projectCandidates": listener.get("projectCandidates", []),
                "management": listener.get("management", {"source": "unmanaged"}),
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
    if observation.get("framework"):
        parts.append(observation["framework"])
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
        context = []
        if project.get("branch"):
            context.append(project["branch"])
        if project.get("isWorktree"):
            context.append(project["worktreeName"])
        suffix = " [{}]".format(" · ".join(context)) if context else ""
        print("\n{}{}".format(group["label"], suffix))
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


def validate_alias(alias: str) -> str:
    normalized = alias.lower()
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", normalized):
        raise ValueError("alias must use lowercase letters, numbers, and internal hyphens")
    return normalized


def load_route_state(state_path: Path) -> Dict[str, object]:
    if not state_path.exists():
        return {"schemaVersion": 1, "routes": {}}
    with state_path.open(encoding="utf-8") as handle:
        document = json.load(handle)
    if document.get("schemaVersion") != 1 or not isinstance(document.get("routes"), dict):
        raise ValueError("unsupported route state")
    return document


def write_route_state(state_path: Path, document: Dict[str, object]) -> None:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = state_path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(str(temporary), str(state_path))


def add_alias(
    state_path: Path,
    alias: str,
    port: int,
    host_mode: str,
    scheme: str = "http",
    tls_policy: str = "verify",
) -> Dict[str, object]:
    alias = validate_alias(alias)
    if port < 1 or port > 65535:
        raise ValueError("port must be between 1 and 65535")
    document = load_route_state(state_path)
    existing = document["routes"].get(alias)
    proposed = {
        "port": port,
        "hostMode": host_mode,
        "scheme": scheme,
        "tlsPolicy": tls_policy,
    }
    if existing and existing != proposed:
        raise ValueError("alias already exists with a different route")
    document["routes"][alias] = proposed
    write_route_state(state_path, document)
    return {"alias": alias, **proposed, "url": "http://{}.localhost:17890".format(alias)}


def remove_alias(state_path: Path, alias: str) -> Dict[str, object]:
    alias = validate_alias(alias)
    document = load_route_state(state_path)
    removed = document["routes"].pop(alias, None)
    if removed is None:
        raise ValueError("alias does not exist")
    write_route_state(state_path, document)
    return {"alias": alias, "removed": True}


def run_proxy(listen: str, state_path: Path) -> int:
    command = [
        "node",
        str(Path(__file__).resolve().parent / "proxy.mjs"),
        "--listen",
        listen,
        "--state",
        str(state_path),
    ]
    try:
        return subprocess.run(command, check=False).returncode
    except KeyboardInterrupt:
        return 130


def main() -> None:
    parser = argparse.ArgumentParser(prog="port-tools")
    subparsers = parser.add_subparsers(dest="command", required=True)
    scan_parser = subparsers.add_parser("scan")
    scan_parser.add_argument("--json", action="store_true")
    scan_parser.add_argument("--all", action="store_true")
    scan_parser.add_argument("--all-web", action="store_true")
    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("service_id")
    stop_parser = subparsers.add_parser("stop")
    stop_parser.add_argument("service_id")
    stop_parser.add_argument("--dry-run", action="store_true")
    stop_parser.add_argument("--json", action="store_true")
    proxy_parser = subparsers.add_parser("proxy")
    proxy_parser.add_argument("--listen", default="127.0.0.1:17890")
    proxy_parser.add_argument("--state", type=Path, default=DEFAULT_ROUTE_STATE)
    alias_parser = subparsers.add_parser("alias")
    alias_subparsers = alias_parser.add_subparsers(dest="alias_command", required=True)
    alias_add = alias_subparsers.add_parser("add")
    alias_add.add_argument("alias")
    alias_add.add_argument("port", type=int)
    alias_add.add_argument("--host-mode", choices=("rewrite", "preserve"), default="rewrite")
    alias_add.add_argument("--upstream-scheme", choices=("http", "https"), default="http")
    alias_add.add_argument("--tls-policy", choices=("verify", "insecure-local"), default="verify")
    alias_add.add_argument("--state", type=Path, default=DEFAULT_ROUTE_STATE)
    alias_list = alias_subparsers.add_parser("list")
    alias_list.add_argument("--state", type=Path, default=DEFAULT_ROUTE_STATE)
    alias_remove = alias_subparsers.add_parser("remove")
    alias_remove.add_argument("alias")
    alias_remove.add_argument("--state", type=Path, default=DEFAULT_ROUTE_STATE)
    args = parser.parse_args()

    if args.command == "proxy":
        raise SystemExit(run_proxy(args.listen, args.state))
    if args.command == "alias":
        try:
            if args.alias_command == "add":
                result = add_alias(
                    args.state,
                    args.alias,
                    args.port,
                    args.host_mode,
                    args.upstream_scheme,
                    args.tls_policy,
                )
            elif args.alias_command == "remove":
                result = remove_alias(args.state, args.alias)
            else:
                result = load_route_state(args.state)
        except (OSError, ValueError, json.JSONDecodeError) as error:
            raise SystemExit(str(error))
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    if args.command == "stop" and not args.dry_run:
        raise SystemExit("refusing to stop: only --dry-run is implemented")

    services = scan()
    if args.command in ("inspect", "stop"):
        service = next((item for item in services if item["id"] == args.service_id), None)
        if service is None:
            raise SystemExit("service not found in current scan: {}".format(args.service_id))
        if args.command == "inspect":
            print(json.dumps(service, indent=2, ensure_ascii=False))
        else:
            plan = stop_dry_run(service)
            if args.json:
                print(json.dumps(plan, indent=2, ensure_ascii=False))
            else:
                print_stop_plan(plan)
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
