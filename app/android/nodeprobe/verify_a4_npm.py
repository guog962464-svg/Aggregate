#!/usr/bin/env python3
"""Verify a pinned npm CLI and bounded install cases on the connected Android device."""

import argparse
import io
import json
import random
import re
import subprocess
import tarfile
import tempfile
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional

from verify_device import APK, PACKAGE, adb


ACTIVITY = PACKAGE + "/.ProbeActivity"
EVENT = re.compile(r"kind=7 requestId=\d+ generation=([\w-]+).*?detail=(\{[^\n]+\})$")
RESULT_GENERATION = re.compile(r"kind=3 requestId=\d+ generation=([\w-]+)")
NODE_CLOSING_GENERATION = re.compile(
    r"kind=5 requestId=\d+ generation=([\w-]+).*?detail=Node process closing"
)
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


def run_action(
    action: str,
    count: int,
    log_path: Path,
    seconds: float = 120,
    fixture_port: Optional[int] = None,
) -> dict:
    adb("shell", "am", "force-stop", PACKAGE)
    command = ["shell", "am", "start", "-n", ACTIVITY,
               "--es", "probe", "a4-npm", "--es", "npmAction", action]
    if fixture_port is not None:
        command.extend(["--ei", "npmFixturePort", str(fixture_port)])
    adb(*command)
    result = wait_result(log_path, action, count, seconds)
    assert result["action"] == action, result
    assert result["npmVersion"] == "12.2.2", result
    assert result["nodeVersion"] == "v24.22.1", result
    assert result["serviceResultDelivered"] is True, result
    generations = RESULT_GENERATION.findall(log_path.read_text())
    assert generations, "Node service terminal result is missing from Logcat"
    wait_node_close(log_path, generations[-1])
    print(
        f"{action}: npmExitCode={result['npmExitCode']}, "
        f"Messenger kind=3={result['serviceResultDelivered']}",
        flush=True,
    )
    return result


def make_integrity_fixture_tarball() -> bytes:
    files = {
        "package/package.json": json.dumps({
            "name": "aggregate-a4-integrity-fixture",
            "version": "1.0.0",
            "main": "lib/index.js",
        }, separators=(",", ":")).encode(),
        "package/lib/index.js": b"module.exports = 'new-package';\n",
        "package/lib/unicode.d.ts": b"export declare const unicode: string;\n",
        "package/lib/util.d.ts": b"export declare function util(): void;\n",
    }
    fixture_bytes = random.Random(0xA4)
    for index in range(64):
        files[f"package/lib/fixture-{index:03}.d.ts"] = bytes(
            fixture_bytes.getrandbits(8) for _ in range(8192)
        )
    archive_bytes = io.BytesIO()
    with tarfile.open(fileobj=archive_bytes, mode="w:gz") as archive:
        for name, contents in files.items():
            entry = tarfile.TarInfo(name)
            entry.size = len(contents)
            entry.mtime = 0
            entry.mode = 0o644
            entry.uid = 0
            entry.gid = 0
            archive.addfile(entry, io.BytesIO(contents))
    return archive_bytes.getvalue()


class IntegrityFixtureServer:
    def __init__(self) -> None:
        fixture = make_integrity_fixture_tarball()

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                if self.path != "/integrity-fixture.tgz":
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", "application/gzip")
                self.send_header("Content-Length", str(len(fixture)))
                self.end_headers()
                self.wfile.write(fixture)

            def log_message(self, _format: str, *args: object) -> None:
                return

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self) -> int:
        self.thread.start()
        adb("reverse", f"tcp:{self.port}", f"tcp:{self.port}")
        return self.port

    def __exit__(self, _exc_type: object, _exc: object, _traceback: object) -> None:
        adb("reverse", "--remove", f"tcp:{self.port}", check=False)
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


def wait_node_close(log_path: Path, generation: str, seconds: float = 15) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if generation in NODE_CLOSING_GENERATION.findall(log_path.read_text()):
            return
        time.sleep(0.05)
    raise RuntimeError(f"Node worker did not close for generation {generation}; see {log_path}")


def integrity_package_entries() -> list[str]:
    relative = "files/a4-npm-workspace/integrity-bad/node_modules/json5"
    result = subprocess.run(
        ["adb", "shell", "run-as", PACKAGE, "find", relative, "-mindepth", "1", "-print"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 1 and "No such file or directory" in result.stderr:
        return []
    if result.returncode != 0:
        raise RuntimeError(f"Could not inspect integrity install tree: {result.stderr or result.stdout}")
    return [entry for entry in result.stdout.splitlines() if entry]


def npm_packages(result: dict, field: str) -> dict[str, dict]:
    return {
        package["name"]: package
        for package in result[field]
        if package.get("name", "").startswith("node_modules/")
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--integrity-transaction-only",
        action="store_true",
        help="run only the local integrity rollback action on the connected device",
    )
    options = parser.parse_args()
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    adb("uninstall", PACKAGE, check=False)
    adb("install", str(APK))
    adb("logcat", "-c")

    with tempfile.TemporaryDirectory(prefix="aggregate-a4-npm-") as temporary:
        log_path = Path(temporary) / "logcat.txt"
        integrity_residue: list[str] = []
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

                transaction = None
                residue_attempts = []
                with IntegrityFixtureServer() as fixture_port:
                    for attempt in range(16):
                        transaction = run_action(
                            "integrity-transaction", 2 + attempt, log_path,
                            fixture_port=fixture_port,
                        )
                        transaction_output = "\n".join((
                            transaction["stdout"], transaction["stderr"],
                            transaction["error"] or "",
                        ))
                        rollback = transaction["integrityTransaction"]
                        assert transaction["npmExitCode"] != 0, transaction
                        assert re.search(r"integrity", transaction_output, re.IGNORECASE), transaction
                        assert rollback["stageExistsAfterCleanup"] is False, rollback
                        assert rollback["oldPackageVersionBeforeCleanup"] == "0.9.0", rollback
                        assert rollback["oldPackageVersionAfterCleanup"] == "0.9.0", rollback
                        assert rollback["oldPackageMarkerBeforeCleanup"] == "old-install-preserved", rollback
                        assert rollback["oldPackageMarkerAfterCleanup"] == "old-install-preserved", rollback
                        staged_entries = rollback["stagedPackageEntriesBeforeCleanup"]
                        residue_attempts.append(staged_entries)
                        if staged_entries:
                            break
                assert transaction is not None
                rollback = transaction["integrityTransaction"]
                assert rollback["stagedPackageEntriesBeforeCleanup"], {
                    "attempts": residue_attempts,
                    "lastResult": rollback,
                }
                print(
                    "Integrity transaction: first observed staged package residue on attempt "
                    f"{len(residue_attempts)}/16: {rollback['stagedPackageEntriesBeforeCleanup']}; "
                    "staging removed and preexisting 0.9.0 package preserved each attempt."
                )
                if options.integrity_transaction_only:
                    return

                installed = run_action("install", 3, log_path)
                if installed["npmExitCode"] != 0:
                    ignored = run_action("script-ignored", 4, log_path)
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

                offline = run_action("offline", 4, log_path)
                assert offline["npmExitCode"] == 0, offline
                offline_packages = npm_packages(offline, "offlineLockPackages")
                assert "node_modules/supports-color" in offline_packages
                assert "node_modules/has-flag" in offline_packages
                assert offline["offlinePackageLoad"]["loaded"] is True, offline

                ignored = run_action("script-ignored", 5, log_path)
                assert ignored["npmExitCode"] == 0, ignored
                assert ignored["scriptIgnoredMarker"] is False, ignored
                default_scripts = run_action("script-default", 6, log_path)
                assert default_scripts["npmExitCode"] == 0, default_scripts
                assert default_scripts["scriptDefaultMarker"] is False, default_scripts
                allowed = run_action("script-allowed", 7, log_path)
                script_succeeded = allowed["npmExitCode"] == 0 and allowed["scriptAllowedMarker"] is True

                integrity = run_action("integrity-bad", 8, log_path)
                integrity_output = "\n".join((integrity["stdout"], integrity["stderr"], integrity["error"] or ""))
                assert integrity["npmExitCode"] != 0, integrity
                assert re.search(r"integrity", integrity_output, re.IGNORECASE), integrity
                package_entries = integrity_package_entries()
                integrity_residue = package_entries
                if integrity_residue:
                    print("FAIL: integrity was rejected, but npm left package entries:", integrity_residue)
                else:
                    print("A deliberately incorrect lockfile SHA-512 was rejected; no package files remained after Node closed.")

                old = run_action("upgrade-old", 9, log_path)
                assert old["npmExitCode"] == 0, old
                assert any(item.get("version") == "2.2.2"
                           for item in npm_packages(old, "upgradeLockPackages").values()), old
                new = run_action("upgrade-new", 10, log_path)
                assert new["npmExitCode"] == 0, new
                assert any(item.get("version") == "2.2.3"
                           for item in npm_packages(new, "upgradeLockPackages").values()), new
                removed = run_action("uninstall", 11, log_path)
                assert removed["npmExitCode"] == 0, removed
                assert "node_modules/json5" not in npm_packages(removed, "upgradeLockPackages")
                cache = run_action("cache-verify", 12, log_path)
                assert cache["npmExitCode"] == 0, cache

                print("Offline cache, script-disabled install, version upgrade/uninstall, and cache verify passed.")
                if script_succeeded:
                    print("The explicitly allowed lifecycle fixture executed and wrote its private marker.")
                else:
                    print("The explicitly allowed lifecycle fixture did not complete:")
                    print(allowed["error"] or allowed["stderr"])
                delivered_generations = set(RESULT_GENERATION.findall(log_path.read_text()))
                observed_actions = npm_events(log_path)
                delivered_count = sum(generation in delivered_generations for generation, _ in observed_actions)
                print(f"Messenger terminal result delivered for {delivered_count}/{len(observed_actions)} npm actions.")
                if integrity_residue:
                    raise AssertionError(f"npm left files after rejecting the integrity mismatch: {integrity_residue}")
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
