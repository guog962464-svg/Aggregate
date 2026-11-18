#!/usr/bin/env python3
"""Install, cold-start, and remove an isolated test-signed Android Release APK."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys
import time


PACKAGE = "io.github.guog962464.aggregate.integration"
ACTIVITY = "io.github.guog962464.aggregate.MainActivity"


def adb(device: str, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["adb", "-s", device, *args],
        check=check,
        capture_output=True,
        text=True,
    )


def epoch_lines(output: str) -> list[tuple[float, str]]:
    result: list[tuple[float, str]] = []
    for line in output.splitlines():
        match = re.match(r"\s*(\d+\.\d+)\s+(.*)", line)
        if match:
            result.append((float(match.group(1)), line))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="ADB serial of physical hardware")
    parser.add_argument("--apk", required=True, type=Path, help="test-signed isolated Release APK")
    args = parser.parse_args()
    apk = args.apk.expanduser().resolve()
    if not apk.is_file():
        parser.error(f"APK does not exist: {apk}")

    devices = subprocess.run(
        ["adb", "devices", "-l"], check=True, capture_output=True, text=True
    ).stdout
    line = next((item for item in devices.splitlines() if item.startswith(args.device + " ")), None)
    if line is None or " device " not in line:
        parser.error(f"{args.device} is not an online ADB device")
    if args.device.startswith("emulator-") or re.search(
        r"(?:^|\s)(?:model:.*(?:emulator|sdk)|device:.*(?:emulator|generic))",
        line,
        re.IGNORECASE,
    ):
        parser.error("this acceptance check requires physical Android hardware")

    installed = adb(args.device, "shell", "pm", "path", PACKAGE, check=False)
    if installed.returncode == 0 and installed.stdout.strip().startswith("package:"):
        parser.error(f"{PACKAGE} is already installed; refusing to replace an existing test package")

    before = adb(args.device, "logcat", "-b", "crash", "-d", "-v", "epoch", check=False)
    previous = epoch_lines(before.stdout)
    baseline = max((timestamp for timestamp, _ in previous), default=0.0)
    installed_by_this_run = False
    try:
        adb(args.device, "install", str(apk))
        installed_by_this_run = True
        adb(args.device, "shell", "am", "force-stop", PACKAGE, check=False)
        started = adb(
            args.device,
            "shell",
            "am",
            "start",
            "-W",
            "-n",
            f"{PACKAGE}/{ACTIVITY}",
            check=False,
        )
        print(started.stdout.strip())
        if started.returncode != 0 or "Status: ok" not in started.stdout:
            raise RuntimeError("Android did not report a successful Activity launch")

        time.sleep(3)
        pid = adb(args.device, "shell", "pidof", PACKAGE, check=False).stdout.strip()
        activity_state = adb(
            args.device, "shell", "dumpsys", "activity", "activities", check=False
        ).stdout
        current = adb(args.device, "logcat", "-b", "crash", "-d", "-v", "epoch", check=False)
        new_lines = [line for timestamp, line in epoch_lines(current.stdout) if timestamp > baseline]
        app_crash = [
            line
            for line in new_lines
            if PACKAGE in line or "JNI is not initialized" in line
        ]
        resumed = re.search(
            rf"(?:mResumedActivity|topResumedActivity).*{re.escape(PACKAGE)}/{re.escape(ACTIVITY)}",
            activity_state,
        )
        if not pid or not resumed or app_crash:
            if app_crash:
                print("New crash-buffer lines:", file=sys.stderr)
                print("\n".join(app_crash[-30:]), file=sys.stderr)
            if not pid:
                print("The isolated app process exited during the cold-start window.", file=sys.stderr)
            if not resumed:
                print("MainActivity is not the resumed Activity.", file=sys.stderr)
            raise RuntimeError("isolated Release cold-start check failed")
        print(f"PASS: {PACKAGE} remained alive and MainActivity resumed (pid {pid}).")
        return 0
    finally:
        if installed_by_this_run:
            adb(args.device, "shell", "am", "force-stop", PACKAGE, check=False)
            adb(args.device, "uninstall", PACKAGE, check=False)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
