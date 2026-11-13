#!/usr/bin/env python3
"""Run fixed A4.6 package/CLI actions on the currently connected Android device."""

from __future__ import annotations

import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

from verify_device import APK, PACKAGE, adb

ACTIVITY = f"{PACKAGE}/.ProbeActivity"
LOCK_SHA256 = "64b01d9e8f90ea92086d4e8950e891a630b85922528b50224d5c2522e2296f7a"
RESULT = re.compile(r"generation=([\w-]+).*?detail=(\{[^\n]+\})$")
CLI_ACTIONS = ("version", "help", "configure", "login-help", "search", "tui")


def device_summary() -> dict[str, str]:
    devices = [line.split()[0] for line in adb("devices").splitlines()[1:] if "\tdevice" in line]
    if len(devices) != 1:
        raise SystemExit(f"Expected one connected device, found {len(devices)}: {devices}")
    props = {
        "serial": devices[0],
        "model": adb("shell", "getprop", "ro.product.model").strip(),
        "android": adb("shell", "getprop", "ro.build.version.release").strip(),
        "api": adb("shell", "getprop", "ro.build.version.sdk").strip(),
        "abis": adb("shell", "getprop", "ro.product.cpu.abilist").strip(),
        "pageSize": adb("shell", "getconf", "PAGE_SIZE").strip(),
    }
    if "emulator" in props["model"].lower() or props["model"].lower().startswith("sdk_"):
        raise SystemExit("A4.6 requires the physical Android device; emulator execution is disabled.")
    return props


def records(log_path: Path, action: str | None = None) -> list[tuple[str, dict]]:
    found = []
    for line in log_path.read_text(errors="replace").splitlines():
        match = RESULT.search(line)
        if not match:
            continue
        payload = json.loads(match.group(2))
        if payload.get("type") == "ncmResult" and (action is None or payload.get("action") == action):
            found.append((match.group(1), payload))
    return found


def installed_package_state() -> dict | None:
    root = "files/a4-ncm-workspace/install"
    lock_hash = adb("shell", "run-as", PACKAGE, "sha256sum", f"{root}/package-lock.json",
                    check=False).split()
    if not lock_hash or lock_hash[0] != LOCK_SHA256:
        return None
    manifest_text = adb("shell", "run-as", PACKAGE, "cat",
                        f"{root}/node_modules/@music163/ncm-cli/package.json", check=False)
    if not manifest_text:
        return None
    try:
        manifest = json.loads(manifest_text)
    except json.JSONDecodeError:
        return None
    if manifest.get("version") != "0.1.7":
        return None
    for relative in (
        "node_modules/@music163/ncm-cli/dist/index.js",
        "node_modules/ffprobe-static/package.json",
        "node_modules/fluent-ffmpeg/package.json",
    ):
        output = adb("shell", "run-as", PACKAGE, "sha256sum", f"{root}/{relative}", check=False)
        if not output.strip():
            return None
    return {"lockSha256": lock_hash[0], "ncmCliVersion": manifest["version"],
            "requiredFilesPresent": True}


def run_action(action: str, log_path: Path, timeout: float) -> dict:
    before = len(records(log_path, action))
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-n", ACTIVITY,
        "--es", "probe", "a4-ncm", "--es", "ncmAction", action)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        results = records(log_path, action)
        if len(results) > before:
            generation, _ = results[-1]
            payload = json.loads(adb(
                "shell", "run-as", PACKAGE, "cat", "files/a3-result.json"
            ))
            terminal_deadline = time.monotonic() + 4
            while time.monotonic() < terminal_deadline:
                if any(item[0] == generation for item in records(log_path)):
                    break
                time.sleep(0.05)
            payload["messengerResultDelivered"] = any(
                item[0] == generation for item in records(log_path)
            )
            return payload
        time.sleep(0.1)
    crash = subprocess.run(["adb", "logcat", "-b", "crash", "-d"],
                           capture_output=True, text=True).stdout
    return {"action": action, "completed": False,
            "recentLog": log_path.read_text(errors="replace")[-4000:], "crashLog": crash[-2000:]}


def main() -> None:
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    summary = device_summary()
    print("A4.6 physical device:", json.dumps(summary, ensure_ascii=False), flush=True)
    # Reinstall over an existing probe without clearing its npm cache/workspace.
    adb("install", "-r", str(APK))
    adb("logcat", "-c")
    cached_install = installed_package_state()
    actions = CLI_ACTIONS
    if cached_install:
        print("Using previously installed, lock-verified package tree:",
              json.dumps(cached_install), flush=True)
    else:
        actions = ("install", *CLI_ACTIONS)

    with tempfile.TemporaryDirectory(prefix="aggregate-a4-ncm-") as temporary:
        log_path = Path(temporary) / "logcat.txt"
        with log_path.open("w") as log:
            monitor = subprocess.Popen(
                ["adb", "logcat", "-s", "A3NodeProbe:I", "*:S"],
                stdout=log,
                stderr=subprocess.DEVNULL,
            )
            outcomes = []
            try:
                time.sleep(0.5)
                for action in actions:
                    timeout = 1200 if action == "install" else 120
                    outcome = run_action(action, log_path, timeout)
                    outcomes.append(outcome)
                    display = dict(outcome)
                    for field in ("stdout", "stderr", "recentLog", "crashLog"):
                        if isinstance(display.get(field), str) and len(display[field]) > 900:
                            display[field] = display[field][:900] + "… [truncated]"
                    print(json.dumps(display, ensure_ascii=False), flush=True)
                    if not outcome.get("messengerResultDelivered"):
                        print("Node service did not deliver a terminal Messenger result; stopping the sequence.", flush=True)
                        break
                    if action == "install" and outcome.get("exitCode") != 0:
                        print("Install failed; later CLI actions require a successful install.", flush=True)
                        break
                    if action == "install":
                        install = outcome.get("install", {})
                        if install.get("lockSha256") != LOCK_SHA256:
                            raise AssertionError(f"Installed lockfile hash mismatch: {install}")
                        if install.get("installedPackageVersion") != "0.1.7":
                            raise AssertionError(f"Unexpected ncm-cli package version: {install}")
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("shell", "am", "force-stop", PACKAGE, check=False)
                adb("uninstall", PACKAGE, check=False)
    print(f"Completed {len(outcomes)}/{len(actions)} A4.6 fixed package/CLI actions.")


if __name__ == "__main__":
    main()
