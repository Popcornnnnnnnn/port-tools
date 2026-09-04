#!/usr/bin/env python3

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time
from typing import Dict, List, Optional


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = Path(__file__).resolve().parent
RUNTIME_ROOT = FIXTURE_ROOT / ".runtime"
MANIFEST_PATH = FIXTURE_ROOT / "manifest.json"


def load_manifest() -> Dict[str, object]:
    with MANIFEST_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def fixtures_by_id() -> Dict[str, Dict[str, object]]:
    manifest = load_manifest()
    return {fixture["id"]: fixture for fixture in manifest["fixtures"]}


def selected_fixtures(fixture_id: Optional[str]) -> List[Dict[str, object]]:
    fixtures = fixtures_by_id()
    if fixture_id is None or fixture_id == "all":
        return list(fixtures.values())
    if fixture_id not in fixtures:
        raise SystemExit("unknown fixture: {}".format(fixture_id))
    return [fixtures[fixture_id]]


def pid_path(fixture_id: str) -> Path:
    return RUNTIME_ROOT / "{}.pid".format(fixture_id)


def read_pid(fixture_id: str) -> Optional[int]:
    path = pid_path(fixture_id)
    if not path.exists():
        return None
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None


def process_alive(pid: Optional[int]) -> bool:
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def ensure_certificate() -> None:
    certificate = RUNTIME_ROOT / "localhost.crt"
    private_key = RUNTIME_ROOT / "localhost.key"
    if certificate.exists() and private_key.exists():
        return
    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-days",
            "1",
            "-subj",
            "/CN=localhost",
            "-addext",
            "subjectAltName=DNS:localhost,IP:127.0.0.1",
            "-keyout",
            str(private_key),
            "-out",
            str(certificate),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def run_checked(command: List[str], cwd: Optional[Path] = None) -> None:
    subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def ensure_git_worktrees() -> None:
    main_root = RUNTIME_ROOT / "worktree-main"
    feature_root = RUNTIME_ROOT / "worktree-feature"
    if (main_root / ".git").exists() and (feature_root / ".git").exists():
        return
    if main_root.exists():
        shutil.rmtree(main_root)
    if feature_root.exists():
        shutil.rmtree(feature_root)
    main_root.mkdir(parents=True)
    shutil.copy2(FIXTURE_ROOT / "http_fixture.py", main_root / "http_fixture.py")
    run_checked(["git", "init", "-b", "main"], cwd=main_root)
    run_checked(["git", "config", "user.name", "port-tools fixture"], cwd=main_root)
    run_checked(["git", "config", "user.email", "fixture@port-tools.local"], cwd=main_root)
    run_checked(["git", "add", "http_fixture.py"], cwd=main_root)
    run_checked(["git", "commit", "-m", "fixture baseline"], cwd=main_root)
    run_checked(["git", "branch", "fixture-feature"], cwd=main_root)
    run_checked(["git", "worktree", "add", str(feature_root), "fixture-feature"], cwd=main_root)


def ensure_node_modules(cwd: Path) -> None:
    if (cwd / "node_modules").exists():
        return
    run_checked(["npm", "ci", "--no-audit", "--no-fund"], cwd=cwd)


def ensure_fastapi_venv() -> None:
    venv_root = RUNTIME_ROOT / "fastapi-venv"
    python = venv_root / "bin" / "python"
    if python.exists():
        return
    run_checked(["python3", "-m", "venv", str(venv_root)])
    run_checked(
        [
            str(python),
            "-m",
            "pip",
            "install",
            "--disable-pip-version-check",
            "--requirement",
            str(FIXTURE_ROOT / "fastapi" / "requirements.txt"),
        ]
    )


def render_value(value: str) -> str:
    return (
        value.replace("{runtime}", str(RUNTIME_ROOT))
        .replace("{repo}", str(REPO_ROOT))
        .replace("{fastapi_python}", str(RUNTIME_ROOT / "fastapi-venv" / "bin" / "python"))
    )


def render_command(fixture: Dict[str, object]) -> List[str]:
    return [render_value(part) for part in fixture["command"]]


def docker_container_id(fixture: Dict[str, object]) -> Optional[str]:
    completed = subprocess.run(
        ["docker", "inspect", "--format", "{{.Id}}", fixture["containerName"]],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    return completed.stdout.strip() or None


def start_docker_fixture(fixture: Dict[str, object]) -> Dict[str, object]:
    existing = docker_container_id(fixture)
    if existing:
        return {"id": fixture["id"], "status": "already-running", "containerId": existing[:12]}
    command = [
        "docker",
        "run",
        "--detach",
        "--rm",
        "--name",
        fixture["containerName"],
        "--publish",
        "127.0.0.1:{}:{}/tcp".format(fixture["port"], fixture["containerPort"]),
    ]
    for key, value in fixture.get("labels", {}).items():
        command.extend(["--label", "{}={}".format(key, render_value(value))])
    command.append(fixture["image"])
    completed = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "docker run failed")
    if not wait_for_listener(int(fixture["port"]), timeout=20.0):
        stop_docker_fixture(fixture)
        raise RuntimeError("{} did not publish its listener".format(fixture["id"]))
    return {
        "id": fixture["id"],
        "status": "started",
        "containerId": completed.stdout.strip()[:12],
        "port": fixture["port"],
    }


def stop_docker_fixture(fixture: Dict[str, object]) -> Dict[str, object]:
    existing = docker_container_id(fixture)
    if not existing:
        return {"id": fixture["id"], "status": "not-running"}
    run_checked(["docker", "stop", "--time", "3", fixture["containerName"]])
    released = wait_for_release(int(fixture["port"]))
    return {"id": fixture["id"], "status": "stopped", "listenerReleased": released}


def wait_for_listener(port: int, timeout: float = 8.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.15):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def wait_for_release(port: int, timeout: float = 5.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.15):
                pass
        except OSError:
            return True
        time.sleep(0.1)
    return False


def start_fixture(fixture: Dict[str, object]) -> Dict[str, object]:
    if fixture.get("kind") == "docker":
        return start_docker_fixture(fixture)
    fixture_id = fixture["id"]
    existing_pid = read_pid(fixture_id)
    if process_alive(existing_pid):
        return {"id": fixture_id, "status": "already-running", "pid": existing_pid}

    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
    cwd_value = render_value(fixture.get("cwd", "."))
    cwd = Path(cwd_value) if os.path.isabs(cwd_value) else REPO_ROOT / cwd_value
    if fixture.get("prepare") == "self-signed-certificate":
        ensure_certificate()
    elif fixture.get("prepare") == "git-worktrees":
        ensure_git_worktrees()
    elif fixture.get("prepare") == "npm-install":
        ensure_node_modules(cwd)
    elif fixture.get("prepare") == "fastapi-venv":
        ensure_fastapi_venv()

    command = render_command(fixture)
    log_path = RUNTIME_ROOT / "{}.log".format(fixture_id)
    log_handle = log_path.open("ab", buffering=0)
    environment = os.environ.copy()
    environment.update(fixture.get("environment", {}))
    process = subprocess.Popen(
        command,
        cwd=str(cwd),
        env=environment,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    pid_path(fixture_id).write_text(str(process.pid), encoding="utf-8")
    if not wait_for_listener(int(fixture["port"])):
        stop_fixture(fixture)
        raise RuntimeError("{} did not listen; inspect {}".format(fixture_id, log_path))
    return {
        "id": fixture_id,
        "status": "started",
        "pid": process.pid,
        "port": fixture["port"],
        "log": str(log_path),
    }


def stop_fixture(fixture: Dict[str, object]) -> Dict[str, object]:
    if fixture.get("kind") == "docker":
        return stop_docker_fixture(fixture)
    fixture_id = fixture["id"]
    path = pid_path(fixture_id)
    pid = read_pid(fixture_id)
    if not process_alive(pid):
        path.unlink(missing_ok=True)
        return {"id": fixture_id, "status": "not-running"}

    os.killpg(pid, signal.SIGTERM)
    deadline = time.monotonic() + 4.0
    while process_alive(pid) and time.monotonic() < deadline:
        time.sleep(0.1)
    if process_alive(pid):
        os.killpg(pid, signal.SIGKILL)
    path.unlink(missing_ok=True)
    released = wait_for_release(int(fixture["port"]))
    return {"id": fixture_id, "status": "stopped", "listenerReleased": released}


def status_fixture(fixture: Dict[str, object]) -> Dict[str, object]:
    if fixture.get("kind") == "docker":
        container_id = docker_container_id(fixture)
        return {
            "id": fixture["id"],
            "status": "running" if container_id else "stopped",
            "containerId": container_id[:12] if container_id else None,
            "port": fixture["port"],
        }
    pid = read_pid(fixture["id"])
    return {
        "id": fixture["id"],
        "status": "running" if process_alive(pid) else "stopped",
        "pid": pid,
        "port": fixture["port"],
    }


def clean_all() -> Dict[str, object]:
    results = [stop_fixture(fixture) for fixture in selected_fixtures("all")]
    next_build = FIXTURE_ROOT / "next" / ".next"
    if next_build.exists():
        shutil.rmtree(next_build)
    if RUNTIME_ROOT.exists():
        shutil.rmtree(RUNTIME_ROOT)
    return {
        "status": "clean",
        "runtimeRemoved": not RUNTIME_ROOT.exists(),
        "nextBuildRemoved": not next_build.exists(),
        "fixtures": results,
        "note": "Shared Docker image cache is intentionally retained.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage disposable port-tools fixtures")
    parser.add_argument("action", choices=("start", "stop", "status", "clean"))
    parser.add_argument("fixture", nargs="?", default="all")
    args = parser.parse_args()

    if args.action == "clean":
        if args.fixture != "all":
            raise SystemExit("clean applies to the complete disposable fixture runtime")
        print(json.dumps(clean_all(), indent=2))
        return

    results = []
    for fixture in selected_fixtures(args.fixture):
        if args.action == "start":
            results.append(start_fixture(fixture))
        elif args.action == "stop":
            results.append(stop_fixture(fixture))
        else:
            results.append(status_fixture(fixture))
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        raise SystemExit(1)
