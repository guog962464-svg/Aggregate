#!/usr/bin/env python3
"""Verify pinned JSON5 source and distribution assets on one Android device."""

import base64
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
CLI_LINE = re.compile(
    r"kind=(\d+) requestId=(\d+) generation=([\w-]+) exit=(-?\d+) "
    r"elapsedMs=(\d+) detail=([^\n]*)"
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


def start_probe(
    probe: str,
    cli_args: str | None = None,
    *,
    second_cli_args: str | None = None,
    cancel_on_ready: bool = False,
) -> None:
    args = ["shell", "am", "start", "-n", PROBE_ACTIVITY, "--es", "probe", probe]
    if cli_args is not None:
        encoded = base64.b64encode(cli_args.encode()).decode("ascii")
        args += ["--es", "cliArgsBase64", encoded]
    if second_cli_args is not None:
        encoded = base64.b64encode(second_cli_args.encode()).decode("ascii")
        args += ["--es", "secondCliArgsBase64", encoded]
    if cancel_on_ready:
        args += ["--ez", "cancelOnReady", "true"]
    adb(*args)


def cli_records(log_path: Path, after_line: int = 0) -> list[dict]:
    records = []
    for line in log_path.read_text().splitlines()[after_line:]:
        match = CLI_LINE.search(line)
        if match:
            records.append({
                "kind": int(match.group(1)),
                "requestId": int(match.group(2)),
                "generation": match.group(3),
                "exitCode": int(match.group(4)),
                "elapsedMs": int(match.group(5)),
                "detail": parse_detail(match.group(6)),
            })
    return records


def wait_cli_record(
    log_path: Path, kind: int, request_id: int, after_line: int = 0, seconds: float = 20
) -> dict:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        lines = log_path.read_text().splitlines()
        for line in lines[after_line:]:
            match = CLI_LINE.search(line)
            if match and int(match.group(1)) == kind and int(match.group(2)) == request_id:
                return {
                    "kind": kind,
                    "requestId": request_id,
                    "generation": match.group(3),
                    "exitCode": int(match.group(4)),
                    "elapsedMs": int(match.group(5)),
                    "detail": parse_detail(match.group(6)),
                }
        time.sleep(0.1)
    raise RuntimeError(f"No kind={kind} requestId={request_id} record; see {log_path}")


def parse_detail(value: str):
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return value


def wait_log_text(log_path: Path, text: str, after_line: int = 0, seconds: float = 20) -> str:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        lines = log_path.read_text().splitlines()
        suffix = "\n".join(lines[after_line:])
        if text in suffix:
            return suffix
        time.sleep(0.1)
    raise RuntimeError(f"Did not observe {text!r}; see {log_path}")


def main() -> None:
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    adb("install", "-r", str(APK))
    adb("shell", "am", "force-stop", PACKAGE)
    stale_marker = "/data/local/tmp/aggregate-a4-stale-marker.txt"
    large_fixture_remote = "/data/local/tmp/aggregate-a4-cli-large.json5"
    with tempfile.TemporaryDirectory(prefix="aggregate-a4-") as temporary:
        log_path = Path(temporary) / "logcat.txt"
        marker_path = Path(temporary) / "stale-marker.txt"
        large_fixture_path = Path(temporary) / "large-input.json5"
        marker_path.write_text("stale-package-file\n")
        large_fixture_path.write_text('"' + ("x" * (4 * 1024 * 1024)) + '"\n')
        with log_path.open("w") as log:
            adb("logcat", "-c")
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

                adb("shell", "am", "force-stop", PACKAGE)
                start_line = len(log_path.read_text().splitlines())
                start_probe("a4-json5-cli", '["--probe-invalid-json"]')
                failure = wait_cli_record(log_path, 3, 1, after_line=start_line)
                assert failure["exitCode"] == 1, failure
                assert failure["detail"]["exitCode"] == 1, failure
                assert failure["detail"]["requestedArgs"] == ["--probe-invalid-json"]
                assert failure["detail"]["stdout"] == ""
                assert failure["detail"]["stderr"], failure

                adb("shell", "am", "force-stop", PACKAGE)
                start_line = len(log_path.read_text().splitlines())
                start_probe(
                    "a4-json5-cli",
                    '["--version"]',
                    second_cli_args='["--version"]',
                )
                busy = wait_cli_record(log_path, 4, 2, after_line=start_line)
                assert busy["detail"] == "Node instance already started", busy
                concurrent_result = wait_cli_record(log_path, 3, 1, after_line=start_line)
                assert concurrent_result["exitCode"] == 0, concurrent_result
                assert concurrent_result["detail"]["requestedArgs"] == ["--version"]
                assert concurrent_result["detail"]["stdout"] == "2.2.3\n"

                adb("push", str(large_fixture_path), large_fixture_remote)
                adb(
                    "shell", "run-as", PACKAGE, "cp", large_fixture_remote,
                    "files/a4-cli-large.json5",
                )
                adb("shell", "rm", "-f", large_fixture_remote)

                adb("shell", "am", "force-stop", PACKAGE)
                start_line = len(log_path.read_text().splitlines())
                start_probe(
                    "a4-json5-cli",
                    '["--probe-large-validate"]',
                    cancel_on_ready=True,
                )
                wait_log_text(log_path, '"type":"cancelRequested"', after_line=start_line)
                cancelled_logs = wait_log_text(
                    log_path, "SERVICE_DISCONNECTED", after_line=start_line, seconds=10
                )
                assert '"type":"ready"' in cancelled_logs
                cancelled_generation = re.search(
                    r'kind=7 requestId=1 generation=([\w-]+).*?detail=\{"type":"ready"',
                    cancelled_logs,
                )
                assert cancelled_generation, cancelled_logs
                time.sleep(1.5)
                cancellation_records = cli_records(log_path, after_line=start_line)
                assert sum(
                    item["kind"] == 2 and item["requestId"] == 1
                    for item in cancellation_records
                ) == 1, "Service reconnect replayed the cancelled CLI request"
                assert not any(
                    item["requestId"] == 1 and item["kind"] in (3, 4)
                    for item in cancellation_records
                ), "Cancelled CLI unexpectedly returned a terminal result"
                adb("shell", "am", "force-stop", PACKAGE)
                start_line = len(log_path.read_text().splitlines())
                start_probe("a4-json5-cli", '["--version"]')
                recovered = wait_cli_record(log_path, 3, 1, after_line=start_line)
                assert recovered["generation"] != cancelled_generation.group(1)
                assert recovered["detail"]["stdout"] == "2.2.3\n"

                print("A4 JSON5 source, dynamic require, distribution/ESM/esbuild bundles and private config passed after restart.")
                print("JSON5 bin success, non-zero stderr, single-run concurrency and cancellation/recovery passed.")
            except Exception:
                print(log_path.read_text()[-4000:])
                raise
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("uninstall", PACKAGE, check=False)
                adb("shell", "rm", "-f", stale_marker, large_fixture_remote, check=False)


if __name__ == "__main__":
    main()
