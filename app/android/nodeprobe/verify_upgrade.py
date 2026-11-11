#!/usr/bin/env python3
"""Build two probe APK versions and verify an in-place device upgrade."""

import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from verify_device import APK, PACKAGE, adb, wait_for


ANDROID = Path(__file__).resolve().parents[1]
EXPECTED = {"version": "v18.20.4", "file": "ok", "network": "network-ok"}


def build(version: int, destination: Path) -> None:
    subprocess.run(
        ["./gradlew", ":nodeprobe:assembleDebug", "--offline", "--quiet", f"-Pa3ProbeVersionCode={version}"],
        cwd=ANDROID,
        check=True,
    )
    shutil.copy2(APK, destination)


def installed_version() -> int:
    package = adb("shell", "dumpsys", "package", PACKAGE)
    match = re.search(r"versionCode=(\d+)", package)
    if not match:
        raise AssertionError("Installed probe versionCode was not reported")
    return int(match.group(1))


def private_files() -> set[str]:
    listing = adb("shell", "run-as", PACKAGE, "ls", "files").splitlines()
    return set(listing)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="aggregate-a3-upgrade-") as temporary:
        directory = Path(temporary)
        first_apk = directory / "probe-v1.apk"
        second_apk = directory / "probe-v2.apk"
        build(1, first_apk)
        build(2, second_apk)
        adb("uninstall", PACKAGE, check=False)
        log_path = directory / "logcat.txt"
        with log_path.open("w") as log:
            monitor = subprocess.Popen(
                ["adb", "logcat", "-s", "A3NodeProbe:I", "*:S"],
                stdout=log,
                stderr=subprocess.DEVNULL,
            )
            try:
                time.sleep(0.5)
                adb("install", str(first_apk))
                assert installed_version() == 1
                adb("shell", "am", "start", "-n", PACKAGE + "/.ProbeActivity")
                first = wait_for(log_path, 1)[-1]
                assert first[1] == EXPECTED
                before = private_files()
                assert {"a3-probe.js", "a3-result.json", "a3-events.jsonl"} <= before
                adb("install", "-r", str(second_apk))
                assert installed_version() == 2
                adb("shell", "am", "start", "-n", PACKAGE + "/.ProbeActivity")
                second = wait_for(log_path, 2)[-1]
                assert second[1] == EXPECTED and second[0] != first[0]
                assert private_files() == before, "Upgrade left additional probe files"
                print("A3 in-place upgrade passed: versionCode 1 -> 2, private data retained,")
                print("Node ran in a fresh Service generation without extra probe files.")
            except Exception:
                print(log_path.read_text()[-3000:])
                raise
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("uninstall", PACKAGE, check=False)


if __name__ == "__main__":
    main()
