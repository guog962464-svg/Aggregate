#!/usr/bin/env python3
"""Run fixed nodejs-mobile API boundary cases on the connected Android device."""

import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

from verify_device import APK, PACKAGE, adb


ACTIVITY = PACKAGE + "/.ProbeActivity"
ACTIONS = ["runtime", "child-process", "spawn", "fork", "media-tools", "stdio", "tui", "native-addon"]
EVENT = re.compile(r"kind=7 requestId=\d+ generation=([\w-]+).*?detail=(\{[^\n]+\})$")
RESULT = re.compile(r"kind=3 requestId=\d+ generation=([\w-]+).*?detail=(\{[^\n]+\})$")


def records(log_path: Path, pattern: re.Pattern[str], event_type: str | None = None) -> list[tuple[str, dict]]:
    found = []
    for line in log_path.read_text().splitlines():
        match = pattern.search(line)
        if not match:
            continue
        payload = json.loads(match.group(2))
        if event_type is None or payload.get("type") == event_type:
            found.append((match.group(1), payload))
    return found


def run_action(action: str, log_path: Path, timeout: float = 45) -> dict:
    before = len(records(log_path, EVENT, "boundaryResult"))
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-n", ACTIVITY,
        "--es", "probe", "a4-boundary", "--es", "boundaryAction", action)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        completed = records(log_path, EVENT, "boundaryResult")
        if len(completed) > before:
            generation, event = completed[-1]
            assert event.get("action") == action, event
            payload = json.loads(adb(
                "shell", "run-as", PACKAGE, "cat", "files/" + event["resultFile"]
            ))
            terminal_deadline = time.monotonic() + 2
            while time.monotonic() < terminal_deadline:
                if any(item[0] == generation for item in records(log_path, RESULT)):
                    break
                time.sleep(0.05)
            payload["messengerResultDelivered"] = any(
                item[0] == generation for item in records(log_path, RESULT)
            )
            return payload
        time.sleep(0.1)
    recent = log_path.read_text()[-8000:]
    crash = subprocess.run(["adb", "logcat", "-b", "crash", "-d"],
                           capture_output=True, text=True).stdout
    return {"action": action, "completed": False, "recentLog": recent,
            "crashLog": crash[-2000:]}


def main() -> None:
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    adb("uninstall", PACKAGE, check=False)
    adb("install", str(APK))
    adb("logcat", "-c")
    outcomes = []
    with tempfile.TemporaryDirectory(prefix="aggregate-a4-boundary-") as temporary:
        log_path = Path(temporary) / "logcat.txt"
        with log_path.open("w") as log:
            monitor = subprocess.Popen(
                ["adb", "logcat", "-b", "all", "-v", "brief"],
                stdout=log,
                stderr=subprocess.DEVNULL,
            )
            try:
                time.sleep(0.5)
                for action in ACTIONS:
                    outcome = run_action(action, log_path)
                    outcomes.append(outcome)
                    print(json.dumps(outcome, ensure_ascii=False), flush=True)
                    if not outcome.get("completed", True):
                        raise RuntimeError(f"Node boundary probe did not complete: {action}")
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("shell", "am", "force-stop", PACKAGE, check=False)
                adb("uninstall", PACKAGE, check=False)
    print(f"Completed {len(outcomes)}/{len(ACTIONS)} fixed API-boundary actions.")


if __name__ == "__main__":
    main()
