#!/usr/bin/env python3
"""Verify a pinned npm CLI and bounded install cases on the connected Android device."""

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
REGISTRY = "https://registry.npmjs.org/"


def npm_events(log_path: Path) -> list[tuple[str, dict]]:
    found = []
    for line in log_path.read_text().splitlines():
        match = EVENT.search(line)
        if match:
            payload = json.loads(match.group(2))
            if payload.get("type") == "npmResult":
                found.append((match.group(1), payload))
    return found


def wait_result(log_path: Path, action: str, count: int, seconds: float = 120) -> dict:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        found = npm_events(log_path)
        if len(found) >= count:
            generation, event = found[-1]
            assert event.get("action") == action, event
            report = json.loads(adb(
                "shell", "run-as", PACKAGE, "cat", "files/" + event["resultFile"]
            ))
            result_deadline = time.monotonic() + 3
            while time.monotonic() < result_deadline:
                if generation in RESULT_GENERATION.findall(log_path.read_text()):
                    break
                time.sleep(0.05)
            report["serviceResultDelivered"] = generation in RESULT_GENERATION.findall(log_path.read_text())
            return report
        time.sleep(0.1)
    raise RuntimeError(f"Only {len(npm_events(log_path))} npm completion event(s); see {log_path}")


def run_action(action: str, count: int, log_path: Path, seconds: float = 120) -> dict:
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-n", ACTIVITY,
        "--es", "probe", "a4-npm", "--es", "npmAction", action)
    result = wait_result(log_path, action, count, seconds)
    assert result["action"] == action, result
    assert result["npmVersion"] == "12.2.2", result
    assert result["nodeVersion"] == "v24.22.1", result
    print(
        f"{action}: npmExitCode={result['npmExitCode']}, "
        f"Messenger kind=3={result['serviceResultDelivered']}",
        flush=True,
    )
    return result


def npm_packages(result: dict, field: str) -> dict[str, dict]:
    return {
        package["name"]: package
        for package in result[field]
        if package.get("name", "").startswith("node_modules/")
    }


def main() -> None:
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    adb("uninstall", PACKAGE, check=False)
    adb("install", str(APK))
    adb("logcat", "-c")

    with tempfile.TemporaryDirectory(prefix="aggregate-a4-npm-") as temporary:
        log_path = Path(temporary) / "logcat.txt"
        with log_path.open("w") as log:
            monitor = subprocess.Popen(
                ["adb", "logcat", "-s", "A3NodeProbe:I", "*:S"],
                stdout=log,
                stderr=subprocess.DEVNULL,
            )
            try:
                time.sleep(0.5)
                version = run_action("version", 1, log_path)
                assert version["npmExitCode"] == 0, version
                assert version["stdout"].strip() == "12.2.2", version
                print("npm 12.2.2 starts on Node v24.22.1 inside the Android Node service.")

                installed = run_action("install", 2, log_path)
                if installed["npmExitCode"] != 0:
                    ignored = run_action("script-ignored", 3, log_path)
                    assert ignored["npmExitCode"] != 0, ignored
                    assert not ignored["scriptIgnoredMarker"], ignored
                    assert not adb(
                        "shell", "run-as", PACKAGE, "ls",
                        "files/a4-npm-workspace/install/node_modules/supports-color",
                        check=False,
                    )
                    assert not adb(
                        "shell", "run-as", PACKAGE, "ls",
                        "files/a4-npm-workspace/install/package-lock.json", check=False,
                    )
                    print("npm install did not reach registry resolution or package extraction.")
                    print("install error:", installed["error"] or installed["stderr"])
                    print("--ignore-scripts result:", ignored["error"] or ignored["stderr"])
                    print("No partial package tree was committed; later install lifecycle checks were blocked.")
                    return

                installed_packages = npm_packages(installed, "installLockPackages")
                support = installed_packages["node_modules/supports-color"]
                dependency = installed_packages["node_modules/has-flag"]
                assert support["version"] == "7.2.0", support
                assert dependency["version"] == "4.0.0", dependency
                assert support["resolved"].startswith(REGISTRY), support
                assert dependency["resolved"].startswith(REGISTRY), dependency
                assert support["integrity"].startswith("sha512-"), support
                assert dependency["integrity"].startswith("sha512-"), dependency
                assert installed["installPackageLoad"]["loaded"] is True, installed
                print("Registry install passed with transitive has-flag dependency and SHA-512 lockfile integrity.")

                offline = run_action("offline", 3, log_path)
                assert offline["npmExitCode"] == 0, offline
                offline_packages = npm_packages(offline, "offlineLockPackages")
                assert "node_modules/supports-color" in offline_packages
                assert "node_modules/has-flag" in offline_packages
                assert offline["offlinePackageLoad"]["loaded"] is True, offline

                ignored = run_action("script-ignored", 4, log_path)
                assert ignored["npmExitCode"] == 0, ignored
                assert ignored["scriptIgnoredMarker"] is False, ignored
                default_scripts = run_action("script-default", 5, log_path)
                assert default_scripts["npmExitCode"] == 0, default_scripts
                assert default_scripts["scriptDefaultMarker"] is False, default_scripts
                allowed = run_action("script-allowed", 6, log_path)
                script_succeeded = allowed["npmExitCode"] == 0 and allowed["scriptAllowedMarker"] is True

                integrity = run_action("integrity-bad", 7, log_path)
                integrity_output = "\n".join((integrity["stdout"], integrity["stderr"], integrity["error"] or ""))
                assert integrity["npmExitCode"] != 0, integrity
                assert re.search(r"integrity", integrity_output, re.IGNORECASE), integrity
                assert integrity["integrityPackageExists"] is False, integrity
                print("A deliberately incorrect lockfile SHA-512 was rejected before package installation.")

                old = run_action("upgrade-old", 8, log_path)
                assert old["npmExitCode"] == 0, old
                assert any(item.get("version") == "2.2.2"
                           for item in npm_packages(old, "upgradeLockPackages").values()), old
                new = run_action("upgrade-new", 9, log_path)
                assert new["npmExitCode"] == 0, new
                assert any(item.get("version") == "2.2.3"
                           for item in npm_packages(new, "upgradeLockPackages").values()), new
                removed = run_action("uninstall", 10, log_path)
                assert removed["npmExitCode"] == 0, removed
                assert "node_modules/json5" not in npm_packages(removed, "upgradeLockPackages")
                cache = run_action("cache-verify", 11, log_path)
                assert cache["npmExitCode"] == 0, cache

                print("Offline cache, script-disabled install, version upgrade/uninstall, and cache verify passed.")
                if script_succeeded:
                    print("The explicitly allowed lifecycle fixture executed and wrote its private marker.")
                else:
                    print("The explicitly allowed lifecycle fixture did not complete:")
                    print(allowed["error"] or allowed["stderr"])
                delivered = [event.get("serviceResultDelivered") for _, event in npm_events(log_path)]
                print(f"Messenger terminal result delivered for {sum(value is True for value in delivered)}/{len(delivered)} npm actions.")
            except Exception:
                print(log_path.read_text()[-5000:])
                raise
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("shell", "am", "force-stop", PACKAGE, check=False)
                adb("uninstall", PACKAGE, check=False)


if __name__ == "__main__":
    main()
