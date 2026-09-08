#!/usr/bin/env python3

import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import statistics
import subprocess
import tempfile
import time


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP = REPO_ROOT / "native" / ".build" / "Port Tools.app"


def percentile(values, fraction):
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((len(ordered) - 1) * fraction)))
    return ordered[index]


def process_metrics(pids):
    completed = subprocess.run(
        ["ps", "-o", "%cpu=,rss=", "-p", ",".join(str(pid) for pid in pids)],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    cpu = 0.0
    rss_kib = 0
    for line in completed.stdout.splitlines():
        fields = line.split()
        if len(fields) == 2:
            cpu += float(fields[0])
            rss_kib += int(fields[1])
    return cpu, rss_kib


def descendants(root_pid):
    completed = subprocess.run(
        ["pgrep", "-P", str(root_pid)], stdout=subprocess.PIPE, text=True, check=False
    )
    return [root_pid] + [int(value) for value in completed.stdout.split()]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--duration", type=int, default=600)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--warmup", type=int, default=10)
    args = parser.parse_args()
    executable = args.app / "Contents" / "MacOS" / "PortTools"
    if not executable.is_file():
        raise SystemExit("Port Tools app is not built: {}".format(args.app))

    with tempfile.TemporaryDirectory(prefix="port-tools-metrics-") as directory:
        state_root = Path(directory)
        socket_path = state_root / "runtime" / "core.sock"
        environment = {
            **os.environ,
            "PORT_TOOLS_STATE_ROOT": str(state_root),
            "PORT_TOOLS_PROXY_ADDRESS": "127.0.0.1:0",
            "PORT_TOOLS_DISABLE_PROMPTS": "1",
        }
        started = time.monotonic()
        process = subprocess.Popen([str(executable)], env=environment, start_new_session=True)
        try:
            deadline = started + 10
            while time.monotonic() < deadline and not socket_path.exists() and process.poll() is None:
                time.sleep(0.02)
            ready_seconds = time.monotonic() - started
            if process.poll() is not None or not socket_path.exists():
                raise RuntimeError("Port Tools did not become ready")

            time.sleep(args.warmup)
            cpu_samples = []
            rss_samples = []
            sample_deadline = time.monotonic() + args.duration
            while time.monotonic() < sample_deadline:
                cpu, rss_kib = process_metrics(descendants(process.pid))
                cpu_samples.append(cpu)
                rss_samples.append(rss_kib)
                time.sleep(args.interval)

            info = plistlib.loads((args.app / "Contents" / "Info.plist").read_bytes())
            result = {
                "passed": ready_seconds < 2 and statistics.median(cpu_samples) < 1
                and percentile(cpu_samples, 0.95) < 3
                and percentile(rss_samples, 0.95) < 80 * 1024,
                "version": info.get("CFBundleShortVersionString"),
                "coldReadySeconds": round(ready_seconds, 3),
                "durationSeconds": args.duration,
                "warmupSeconds": args.warmup,
                "sampleCount": len(cpu_samples),
                "cpuMedianPercent": round(statistics.median(cpu_samples), 3),
                "cpuP95Percent": round(percentile(cpu_samples, 0.95), 3),
                "rssMedianMiB": round(statistics.median(rss_samples) / 1024, 2),
                "rssP95MiB": round(percentile(rss_samples, 0.95) / 1024, 2),
                "rssPeakMiB": round(max(rss_samples) / 1024, 2),
            }
            print(json.dumps(result, indent=2))
            if not result["passed"]:
                raise SystemExit(1)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=2)


if __name__ == "__main__":
    main()
