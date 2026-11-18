#!/usr/bin/env python3
"""Verify npm lifecycle `node` command lookup on one physical 4 KB device."""

import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

from verify_device import APK, PACKAGE, adb


ACTIVITY = PACKAGE + "/.ProbeActivity"
EVENT = re.compile(r"kind=7 requestId=\d+ generation=([\w-]+).*?detail=(\{[^\n]+\})$")
RESULT_GENERATION = re.compile(r"kind=3 requestId=\d+ generation=([\w-]+)")


def ensure_physical_4kb_device() -> dict[str, str]:
    devices = [
        fields for fields in (line.split() for line in adb("devices", "-l").splitlines()[1:])
        if len(fields) >= 2 and fields[1] == "device"
    ]
    if len(devices) != 1:
        raise SystemExit(f"Expected exactly one connected Android device; found {len(devices)}")
    properties = {
        "model": adb("shell", "getprop", "ro.product.model"),
        "abi": adb("shell", "getprop", "ro.product.cpu.abi"),
        "api": adb("shell", "getprop", "ro.build.version.sdk"),
        "pageSize": adb("shell", "getconf", "PAGE_SIZE"),
        "qemu": adb("shell", "getprop", "ro.kernel.qemu"),
    }
    model = properties["model"].lower()
    if "emulator" in model or model.startswith("sdk_") or properties["qemu"] == "1":
        raise SystemExit("Physical-device acceptance is required; emulator use is disabled.")
    if properties["abi"] != "arm64-v8a" or properties["pageSize"] != "4096":
        raise SystemExit(f"Expected arm64 4 KB device; got {properties}")
    return properties


def npm_events(log_path: Path) -> list[tuple[str, dict]]:
    events = []
    for line in log_path.read_text().splitlines():
        match = EVENT.search(line)
        if not match:
            continue
        payload = json.loads(match.group(2))
        if payload.get("type") == "npmResult":
            events.append((match.group(1), payload))
    return events


def wait_for_result(log_path: Path, timeout: float = 30) -> tuple[str, dict]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        events = npm_events(log_path)
        if events:
            generation, event = events[-1]
            result = json.loads(adb(
                "shell", "run-as", PACKAGE, "cat", "files/" + event["resultFile"]
            ))
            terminal_deadline = time.monotonic() + 3
            while time.monotonic() < terminal_deadline:
                log_text = log_path.read_text()
                if generation in RESULT_GENERATION.findall(log_text):
                    result["serviceResultDelivered"] = True
                    return generation, result
                if "SERVICE_DISCONNECTED" in log_text:
                    break
                time.sleep(0.05)
            log_text = log_path.read_text()
            result["serviceResultDelivered"] = generation in RESULT_GENERATION.findall(log_text)
            result["serviceDisconnected"] = "SERVICE_DISCONNECTED" in log_text
            return generation, result
        time.sleep(0.1)
    raise RuntimeError(f"npm lifecycle result was not delivered; see {log_path}")


def main() -> None:
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    device = ensure_physical_4kb_device()
    if adb("shell", "pm", "path", PACKAGE, check=False):
        raise SystemExit(f"Refusing to replace a pre-existing NodeProbe installation: {PACKAGE}")

    installed_by_this_run = False
    try:
        adb("install", str(APK))
        installed_by_this_run = True
        adb("shell", "am", "force-stop", PACKAGE)
        adb("logcat", "-c")
        with tempfile.TemporaryDirectory(prefix="aggregate-node-alias-") as temporary:
            log_path = Path(temporary) / "logcat.txt"
            with log_path.open("w") as log:
                monitor = subprocess.Popen(
                    ["adb", "logcat", "-s", "A3NodeProbe:I", "*:S"],
                    stdout=log,
                    stderr=subprocess.DEVNULL,
                )
                try:
                    time.sleep(0.5)
                    adb("shell", "am", "start", "-n", ACTIVITY,
                        "--es", "probe", "a4-npm", "--es", "npmAction", "script-allowed")
                    _, result = wait_for_result(log_path)
                    assert result["action"] == "script-allowed", result
                    assert result["npmVersion"] == "12.2.2", result
                    assert result["nodeVersion"] == "v24.22.1", result
                    assert result["npmExitCode"] == 0, result
                    assert result["scriptAllowedMarker"] is True, result
                    marker = result["scriptAllowedMarkerData"]
                    assert marker == {
                        "installed": True,
                        "nodeVersion": "v24.22.1",
                        "childStatus": 0,
                        "childSignal": None,
                    }, result
                    print(f"Device: {device}")
                    print("npm script resolved PATH node, ran its child, and matched v24.22.1.")
                    print("The explicitly allowed local lifecycle install completed with npm exit 0.")
                    if not result["serviceResultDelivered"]:
                        crash = subprocess.run(
                            ["adb", "logcat", "-b", "crash", "-d"],
                            capture_output=True, text=True, check=False,
                        ).stdout[-3000:]
                        raise RuntimeError(
                            "npm lifecycle result and child marker succeeded, but Node Service "
                            "did not deliver Messenger kind=3 before disconnect.\n"
                            + json.dumps(result, ensure_ascii=False) + "\n" + crash
                        )
                except Exception:
                    print(log_path.read_text()[-5000:])
                    raise
                finally:
                    monitor.terminate()
                    monitor.wait(timeout=5)
    finally:
        if installed_by_this_run:
            adb("shell", "am", "force-stop", PACKAGE, check=False)
            adb("uninstall", PACKAGE, check=False)


if __name__ == "__main__":
    main()
