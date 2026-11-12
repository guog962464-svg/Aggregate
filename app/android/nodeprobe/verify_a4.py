#!/usr/bin/env python3
"""Verify pinned JSON5 source and distribution assets on one Android device."""

import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

from verify_device import APK, PACKAGE, adb, wait_for

PROBE_ACTIVITY = PACKAGE + "/.ProbeActivity"
EVENT = re.compile(
    r"kind=7 requestId=\d+ generation=[\w-]+.*?detail=(\{[^\n]+\})"
)


def package_events(log_path: Path) -> list[dict]:
    events = [json.loads(payload) for payload in EVENT.findall(log_path.read_text())]
    return [event for event in events if event.get("type") == "packageResult"]


def wait_for_package_event(log_path: Path, count: int, seconds: float = 5) -> list[dict]:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        found = package_events(log_path)
        if len(found) >= count:
            return found
        time.sleep(0.1)
    raise RuntimeError(f"Only {len(package_events(log_path))} package event(s); see {log_path}")


def start_probe(probe: str, cli_args: str | None = None) -> None:
    args = ["shell", "am", "start", "-n", PROBE_ACTIVITY, "--es", "probe", probe]
    if cli_args is not None:
        args += ["--es", "cliArgsJson", cli_args]
    adb(*args)


def main() -> None:
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    adb("install", "-r", str(APK))
    adb("shell", "am", "force-stop", PACKAGE)
    stale_marker = "/data/local/tmp/aggregate-a4-stale-marker.txt"
    with tempfile.TemporaryDirectory(prefix="aggregate-a4-") as temporary:
        log_path = Path(temporary) / "logcat.txt"
        marker_path = Path(temporary) / "stale-marker.txt"
        marker_path.write_text("stale-package-file\n")
        with log_path.open("w") as log:
            monitor = subprocess.Popen(
                ["adb", "logcat", "-s", "A3NodeProbe:I", "*:S"],
                stdout=log,
                stderr=subprocess.DEVNULL,
            )
            try:
                time.sleep(0.5)
                for count in (1, 2):
                    if count == 2:
                        adb("shell", "am", "force-stop", PACKAGE)
                    start_probe("a4-json5")
                    found = wait_for(log_path, count, seconds=20)
                    generation, result = found[-1]
                    assert result == {
                        "node": "v24.22.1",
                        "package": "json5",
                        "version": "2.2.3",
                        "entry": "lib/index.js",
                        "bin": "lib/cli.js",
                        "source": "works",
                        "dynamic": "works",
                        "bundled": "works",
                        "esm": "works",
                        "configPrivate": True,
                        "configVersion": "2.2.3",
                        "configUserValue": None,
                    }, result
                    package_event = wait_for_package_event(log_path, count)[-1]
                    assert package_event["package"] == "json5"
                    assert package_event["version"] == "2.2.3"
                    assert package_event["esbuildMatches"] is True, package_event
                    assert package_event["esbuildBundleBytes"] > 0
                    assert package_event["packageTreeBytes"] > package_event["esbuildBundleBytes"]
                    if count == 2:
                        assert generation != found[0][0]
                        assert not adb(
                            "shell",
                            "run-as",
                            PACKAGE,
                            "ls",
                            "files/node_modules/json5/a4-stale-marker.txt",
                            check=False,
                        ), "stale package marker survived resource refresh"
                    else:
                        adb("push", str(marker_path), stale_marker)
                        adb(
                            "shell",
                            "run-as",
                            PACKAGE,
                            "cp",
                            stale_marker,
                            "files/node_modules/json5/a4-stale-marker.txt",
                        )
                for count, args, expected_stdout in (
                    (3, '["--version"]', "2.2.3\n"),
                    (4, '["--help"]', None),
                ):
                    adb("shell", "am", "force-stop", PACKAGE)
                    start_probe("a4-json5-cli", args)
                    result = wait_for(log_path, count, seconds=20)[-1][1]
                    assert result["package"] == "json5"
                    assert result["version"] == "2.2.3"
                    assert result["bin"] == "lib/cli.js"
                    assert result["args"] == json.loads(args)
                    assert result["exitCode"] == 0
                    assert result["stderr"] == ""
                    if expected_stdout is not None:
                        assert result["stdout"] == expected_stdout, result
                    else:
                        assert "Usage: json5" in result["stdout"], result
                print("A4 JSON5 source, dynamic require, distribution/ESM/esbuild bundles and private config passed after restart.")
                print("JSON5 bin --version and --help preserved args, stdout/stderr and exit code.")
            except Exception:
                print(log_path.read_text()[-4000:])
                raise
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("uninstall", PACKAGE, check=False)
                adb("shell", "rm", "-f", stale_marker, check=False)


if __name__ == "__main__":
    main()
