#!/usr/bin/env python3

import argparse
import ctypes
import errno
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
RUSAGE_INFO_V0 = 0


class RusageInfoV0(ctypes.Structure):
    _fields_ = [
        ("ri_uuid", ctypes.c_uint8 * 16),
        ("ri_user_time", ctypes.c_uint64),
        ("ri_system_time", ctypes.c_uint64),
        ("ri_pkg_idle_wkups", ctypes.c_uint64),
        ("ri_interrupt_wkups", ctypes.c_uint64),
        ("ri_pageins", ctypes.c_uint64),
        ("ri_wired_size", ctypes.c_uint64),
        ("ri_resident_size", ctypes.c_uint64),
        ("ri_phys_footprint", ctypes.c_uint64),
        ("ri_proc_start_abstime", ctypes.c_uint64),
        ("ri_proc_exit_abstime", ctypes.c_uint64),
    ]


LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
LIBPROC.proc_pid_rusage.argtypes = [
    ctypes.c_int,
    ctypes.c_int,
    ctypes.POINTER(RusageInfoV0),
]
LIBPROC.proc_pid_rusage.restype = ctypes.c_int


def percentile(values, fraction):
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((len(ordered) - 1) * fraction)))
    return ordered[index]


def physical_footprint_kib(pid):
    usage = RusageInfoV0()
    if LIBPROC.proc_pid_rusage(pid, RUSAGE_INFO_V0, ctypes.byref(usage)) != 0:
        error_number = ctypes.get_errno()
        if error_number == errno.ESRCH:
            return 0
        raise OSError(error_number, os.strerror(error_number))
    return usage.ri_phys_footprint // 1024


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
    footprint_kib = sum(physical_footprint_kib(pid) for pid in pids)
    return cpu, footprint_kib, rss_kib


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
            footprint_samples = []
            rss_samples = []
            sample_deadline = time.monotonic() + args.duration
            while time.monotonic() < sample_deadline:
                cpu, footprint_kib, rss_kib = process_metrics(descendants(process.pid))
                cpu_samples.append(cpu)
                footprint_samples.append(footprint_kib)
                rss_samples.append(rss_kib)
                time.sleep(args.interval)

            info = plistlib.loads((args.app / "Contents" / "Info.plist").read_bytes())
            result = {
                "passed": ready_seconds < 2 and statistics.median(cpu_samples) < 1
                and percentile(cpu_samples, 0.95) < 3
                and percentile(footprint_samples, 0.95) < 80 * 1024,
                "version": info.get("CFBundleShortVersionString"),
                "coldReadySeconds": round(ready_seconds, 3),
                "durationSeconds": args.duration,
                "warmupSeconds": args.warmup,
                "sampleCount": len(cpu_samples),
                "cpuMedianPercent": round(statistics.median(cpu_samples), 3),
                "cpuP95Percent": round(percentile(cpu_samples, 0.95), 3),
                "physicalFootprintMedianMiB": round(statistics.median(footprint_samples) / 1024, 2),
                "physicalFootprintP95MiB": round(percentile(footprint_samples, 0.95) / 1024, 2),
                "physicalFootprintPeakMiB": round(max(footprint_samples) / 1024, 2),
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
