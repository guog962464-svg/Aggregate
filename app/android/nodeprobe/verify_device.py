#!/usr/bin/env python3
"""Verify the isolated A3 probe on a connected arm64 Android device."""

import json
import re
import subprocess
import tempfile
import time
from pathlib import Path


PACKAGE = "io.github.guog962464.aggregate.nodeprobe"
APK = Path(__file__).resolve().parents[2] / "build/nodeprobe/outputs/apk/debug/nodeprobe-debug.apk"
RESULT = re.compile(r"kind=3 requestId=\d+ generation=([\w-]+).*?exit=0.*?detail=(\{[^\n]+\})")


def adb(*args: str, check: bool = True) -> str:
    result = subprocess.run(["adb", *args], capture_output=True, text=True, check=check)
    return result.stdout.strip()


def results(log_path: Path) -> list[tuple[str, dict]]:
    return [(generation, json.loads(payload)) for generation, payload in RESULT.findall(log_path.read_text())]


def wait_for(log_path: Path, count: int, seconds: float = 15) -> list[tuple[str, dict]]:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        found = results(log_path)
        if len(found) >= count:
            return found
        time.sleep(0.1)
    raise RuntimeError(f"Only {len(results(log_path))} result(s); see {log_path}")


def main() -> None:
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    adb("install", "-r", str(APK))
    adb("shell", "am", "force-stop", PACKAGE)
    with tempfile.TemporaryDirectory(prefix="aggregate-a3-") as temporary:
        log_path = Path(temporary) / "logcat.txt"
        with log_path.open("w") as log:
            monitor = subprocess.Popen(
                ["adb", "logcat", "-s", "A3NodeProbe:I", "*:S"],
                stdout=log,
                stderr=subprocess.DEVNULL,
            )
            try:
                time.sleep(0.5)
                adb("shell", "am", "start", "-n", PACKAGE + "/.ProbeActivity")
                first = wait_for(log_path, 1)[-1]
                main_pid = adb("shell", "pidof", PACKAGE)
                node_pid = adb("shell", "pidof", PACKAGE + ":node")
                adb("shell", "run-as", PACKAGE, "kill", "-9", node_pid)
                resumed = False
                try:
                    second = wait_for(log_path, 2, seconds=5)[-1]
                except RuntimeError:
                    # An OEM may defer a background binding until the app is foreground.
                    resumed = True
                    adb("shell", "am", "start", "-n", PACKAGE + "/.ProbeActivity")
                    second = wait_for(log_path, 2)[-1]
                assert first[0] != second[0], "Service generation did not change"
                assert adb("shell", "pidof", PACKAGE) == main_pid, "Main process died"
                assert "SERVICE_DISCONNECTED" in log_path.read_text(), "Disconnect not reported"
                expected = {"version": "v24.22.1", "file": "ok", "network": "network-ok"}
                assert first[1] == expected and second[1] == expected, (first, second)
                adb("shell", "am", "force-stop", PACKAGE)
                adb("shell", "am", "start", "-n", PACKAGE + "/.ProbeActivity")
                third = wait_for(log_path, 3)[-1]
                assert third[0] not in (first[0], second[0]) and third[1] == expected
                adb("install", "-r", str(APK))
                adb("shell", "am", "start", "-n", PACKAGE + "/.ProbeActivity")
                fourth = wait_for(log_path, 4)[-1]
                assert fourth[0] not in (first[0], second[0], third[0]) and fourth[1] == expected
                adb("shell", "input", "keyevent", "3")
                time.sleep(1)
                adb("shell", "am", "kill", PACKAGE)
                assert not adb("shell", "pidof", PACKAGE, check=False), "Background main process survived am kill"
                assert not adb("shell", "pidof", PACKAGE + ":node", check=False), "Node process survived am kill"
                adb("shell", "am", "start", "-n", PACKAGE + "/.ProbeActivity")
                fifth = wait_for(log_path, 5)[-1]
                assert fifth[0] not in (first[0], second[0], third[0], fourth[0])
                assert fifth[1] == expected
                print("A3 probe passed: Node started twice; file and loopback network worked;")
                print("service crash, full app restart, APK reinstall and background am kill recovered;")
                print("main process survived the isolated service crash.")
                if resumed:
                    print("Recovery required bringing the probe Activity to foreground.")
            except Exception:
                print(log_path.read_text()[-3000:])
                print("main pid:", adb("shell", "pidof", PACKAGE, check=False))
                print("node pid:", adb("shell", "pidof", PACKAGE + ":node", check=False))
                raise
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("shell", "am", "force-stop", PACKAGE, check=False)
                adb("uninstall", PACKAGE, check=False)


if __name__ == "__main__":
    main()
