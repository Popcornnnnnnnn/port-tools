#!/usr/bin/env python3

import json
from pathlib import Path
import plistlib
import subprocess
import time


REPO_ROOT = Path(__file__).resolve().parents[2]
APP = REPO_ROOT / "native" / ".build" / "Port Tools.app"
EXECUTABLE = APP / "Contents" / "MacOS" / "PortTools"
SCANNER = APP / "Contents" / "Resources" / "Scanner" / "port_tools.py"


def run(command):
    return subprocess.run(
        [str(part) for part in command],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )


def main() -> None:
    run(["codesign", "--verify", "--deep", "--strict", APP])
    info = plistlib.loads((APP / "Contents" / "Info.plist").read_bytes())
    scan = json.loads(run(["/usr/bin/python3", SCANNER, "scan", "--json", "--all"]).stdout)
    process = subprocess.Popen([str(EXECUTABLE)])
    try:
        time.sleep(1.5)
        alive = process.poll() is None
    finally:
        process.terminate()
        process.wait(timeout=3)

    result = {
        "passed": (
            info.get("LSUIElement") is True
            and info.get("CFBundleName") == "Port Tools"
            and EXECUTABLE.is_file()
            and SCANNER.is_file()
            and len(scan.get("services", [])) > 0
            and alive
        ),
        "bundleBytes": sum(path.stat().st_size for path in APP.rglob("*") if path.is_file()),
        "menuBarProcessLaunched": alive,
        "scannerServices": len(scan.get("services", [])),
        "trialScannerRuntime": "/usr/bin/python3",
        "adHocSignatureVerified": True,
    }
    print(json.dumps(result, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
