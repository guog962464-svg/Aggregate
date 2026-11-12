#!/usr/bin/env python3
"""Verify the isolated A4.3 profile lifecycle on the connected Android device."""

import json
import re
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

from verify_device import APK, PACKAGE, adb, wait_for


ACTIVITY = PACKAGE + "/.ProbeActivity"
PROFILE_RESULT = re.compile(r"PROFILE_RESULT:(\{[^\n]+\})")


def profile_results(log_path: Path) -> list[dict]:
    return [json.loads(payload) for payload in PROFILE_RESULT.findall(log_path.read_text())]


def wait_profile_result(log_path: Path, count: int, seconds: float = 10) -> dict:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        found = profile_results(log_path)
        if len(found) >= count:
            return found[-1]
        time.sleep(0.1)
    raise RuntimeError(f"Only {len(profile_results(log_path))} profile result(s); see {log_path}")


def launch_action(
    action: str,
    count: int,
    log_path: Path,
    draft_id: str | None = None,
    profile_id: str | None = None,
) -> dict:
    adb("shell", "am", "force-stop", PACKAGE)
    args = ["shell", "am", "start", "-n", ACTIVITY,
            "--es", "probe", "a4-profile", "--es", "profileAction", action]
    if draft_id is not None:
        args += ["--es", "draftId", draft_id]
    if profile_id is not None:
        args += ["--es", "profileId", profile_id]
    adb(*args)
    result = wait_profile_result(log_path, count)
    assert result.get("ok") is True, result
    return result


def run_as(*args: str, check: bool = True) -> str:
    return adb("shell", "run-as", PACKAGE, *args, check=check)


def main() -> None:
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    adb("uninstall", PACKAGE, check=False)
    adb("install", str(APK))
    adb("logcat", "-c")

    with tempfile.TemporaryDirectory(prefix="aggregate-a4-profile-") as temporary:
        root = Path(temporary)
        log_path = root / "logcat.txt"
        with log_path.open("w") as log:
            monitor = subprocess.Popen(
                ["adb", "logcat", "-s", "A3NodeProbe:I", "A4ProfileProbe:I", "*:S"],
                stdout=log,
                stderr=subprocess.DEVNULL,
            )
            remote_tampered = "/data/local/tmp/aggregate-a4-profile-tampered.json"
            try:
                time.sleep(0.5)
                adb("shell", "am", "start", "-n", ACTIVITY,
                    "--es", "probe", "a4-json5")
                source_result = wait_for(log_path, 1, seconds=20)[-1][1]
                assert source_result["version"] == "2.2.3", source_result
                assert json.loads(run_as("cat", "files/node_modules/json5/package.json"))["version"] == "2.2.3"

                tested = launch_action("test", 1, log_path)
                assert tested["saved"] is False
                first_draft = tested["draftId"]
                assert run_as("cat", "files/connections.json", check=False) == ""
                assert run_as("ls", "files/node-profiles", check=False) == ""
                discarded = launch_action("discard", 2, log_path, draft_id=first_draft)
                assert discarded["discarded"] is True and discarded["connectionCount"] == 0
                assert run_as("ls", f"cache/node-profile-drafts/{first_draft}", check=False) == ""
                assert run_as("ls", "files/node-profiles", check=False) == ""

                second_draft = launch_action("test", 3, log_path)["draftId"]
                saved = launch_action("save", 4, log_path, draft_id=second_draft)
                profile_id = saved["profileId"]
                assert re.fullmatch(r"node-profile-[0-9a-f]{32}", profile_id)
                assert saved["draftRemoved"] is True and saved["connectionCount"] == 1
                spec = saved["spec"]
                assert spec["kind"] == "cli" and spec["profileId"] == profile_id
                assert "executable" not in spec and "entrypoint" not in spec and "packageId" not in spec

                connection_document = json.loads(run_as("cat", "files/connections.json"))
                assert connection_document["schemaVersion"] == 1
                assert len(connection_document["connections"]) == 1
                assert connection_document["connections"][0]["spec"] == spec
                profile_path = f"files/node-profiles/{profile_id}/profile.json"
                original_profile = json.loads(run_as("cat", profile_path))
                assert original_profile["adapterId"] == "android-bundled-json5"
                assert original_profile["packageId"] == "json5"
                assert original_profile["packageVersion"] == "2.2.3"
                assert original_profile["entrypointId"] == "json5.bin"
                assert "entrypointPath" not in original_profile
                assert json.loads(run_as(
                    "cat", f"files/node-profiles/{profile_id}/config.json5"
                ))["userValue"] == "keep-me"

                inspected = launch_action("inspect", 5, log_path, profile_id=profile_id)
                assert inspected["found"] is True
                assert inspected["config"]["userValue"] == "keep-me"

                orphan = launch_action("create-orphan", 6, log_path)["profileId"]
                orphan_result = profile_results(log_path)[-1]
                staging_id = orphan_result["stagingId"]
                assert orphan != profile_id and staging_id.startswith(".staging-")
                swept = launch_action("inspect", 7, log_path, profile_id=profile_id)
                assert swept["found"] is True and swept["cleanedOrphans"] == 2, swept
                assert run_as("ls", f"files/node-profiles/{orphan}", check=False) == ""
                assert run_as("ls", f"files/node-profiles/{staging_id}", check=False) == ""

                connection_text = run_as("cat", "files/connections.json")
                corrupt_connection = root / "corrupt-connections.json"
                corrupt_connection.write_text("{invalid json")
                adb("push", str(corrupt_connection), remote_tampered)
                run_as("cp", remote_tampered, "files/connections.json")
                adb("shell", "am", "force-stop", PACKAGE)
                adb("shell", "am", "start", "-n", ACTIVITY, "--es", "probe", "a4-profile",
                    "--es", "profileAction", "inspect", "--es", "profileId", profile_id)
                corrupt_result = wait_profile_result(log_path, 8)
                assert corrupt_result.get("ok") is False
                assert run_as("ls", f"files/node-profiles/{profile_id}")
                assert "connections.json.damaged-" in run_as("ls", "files")
                restore_connections = root / "connections.json"
                restore_connections.write_text(connection_text)
                adb("push", str(restore_connections), remote_tampered)
                run_as("cp", remote_tampered, "files/connections.json")
                adb("shell", "rm", "-f", remote_tampered)

                # Invalid IDs are expected errors; invoke directly to inspect the rejection result.
                adb("shell", "am", "force-stop", PACKAGE)
                adb("shell", "am", "start", "-n", ACTIVITY, "--es", "probe", "a4-profile",
                    "--es", "profileAction", "inspect", "--es", "profileId", "../shared_prefs")
                traversal = wait_profile_result(log_path, 9)
                assert traversal.get("ok") is False and traversal["error"] == "invalid profile ID", traversal

                tampered_profile = dict(original_profile)
                tampered_profile["entrypointId"] = "/data/local/tmp/evil.js"
                local_tampered = root / "tampered-profile.json"
                local_tampered.write_text(json.dumps(tampered_profile))
                adb("push", str(local_tampered), remote_tampered)
                run_as("cp", remote_tampered, profile_path)
                adb("shell", "am", "force-stop", PACKAGE)
                adb("shell", "am", "start", "-n", ACTIVITY, "--es", "probe", "a4-profile",
                    "--es", "profileAction", "inspect", "--es", "profileId", profile_id)
                rejected = wait_profile_result(log_path, 10)
                assert rejected.get("ok") is False
                assert rejected["error"] == "profile does not match the APK package manifest", rejected
                restore_profile = root / "original-profile.json"
                restore_profile.write_text(json.dumps(original_profile))
                adb("push", str(restore_profile), remote_tampered)
                run_as("cp", remote_tampered, profile_path)
                adb("shell", "rm", "-f", remote_tampered)

                second_profile_id = "node-profile-" + uuid.uuid4().hex
                second_profile_path = f"files/node-profiles/{second_profile_id}"
                run_as("mkdir", "-p", f"{second_profile_path}/cache")
                second_metadata = {
                    "schemaVersion": 1,
                    "profileId": second_profile_id,
                    "adapterId": "android-bundled-json5",
                    "packageId": "json5",
                    "packageVersion": "2.2.3",
                    "tarballSha256": "08afb33db600d11fc89b98fac4054f19d5d3e0fe527063116150e1ecc2d2377b",
                    "entrypointId": "json5.bin",
                }
                metadata_file = root / "second-profile.json"
                metadata_file.write_text(json.dumps(second_metadata))
                adb("push", str(metadata_file), remote_tampered)
                run_as("cp", remote_tampered, f"{second_profile_path}/profile.json")
                second_config_file = root / "second-config.json5"
                second_config_file.write_text('{"enabled":true,"userValue":"second-profile"}')
                adb("push", str(second_config_file), remote_tampered)
                run_as("cp", remote_tampered, f"{second_profile_path}/config.json5")
                run_as("touch", f"{second_profile_path}/cache/probe-cache.bin")
                multiple_connections = json.loads(connection_text)
                multiple_connections["connections"].append({
                    "id": "node-connection-fixture",
                    "spec": {
                        "kind": "cli",
                        "label": "Second JSON5 CLI",
                        "arguments": [],
                        "profileId": second_profile_id,
                    },
                })
                multi_connection_file = root / "multiple-connections.json"
                multi_connection_file.write_text(json.dumps(multiple_connections))
                adb("push", str(multi_connection_file), remote_tampered)
                run_as("cp", remote_tampered, "files/connections.json")
                adb("shell", "rm", "-f", remote_tampered)
                run_as("touch", "files/unrelated.keep")
                removed = launch_action("remove", 11, log_path, profile_id=profile_id)
                assert removed["removed"] is True and removed["profileExists"] is False
                assert removed["connectionCount"] == 1
                assert run_as("ls", f"files/node-profiles/{profile_id}", check=False) == ""
                remaining = json.loads(run_as("cat", "files/connections.json"))["connections"]
                assert len(remaining) == 1
                assert remaining[0]["spec"]["profileId"] == second_profile_id
                assert run_as("ls", f"files/node-profiles/{second_profile_id}")
                assert json.loads(run_as(
                    "cat", f"{second_profile_path}/config.json5"
                ))["userValue"] == "second-profile"
                assert run_as("ls", "files/unrelated.keep") == "files/unrelated.keep"
                assert run_as("ls", "files/node_modules/json5/package.json") == "files/node_modules/json5/package.json"

                final_draft = launch_action("test", 12, log_path)["draftId"]
                final_saved = launch_action("save", 13, log_path, draft_id=final_draft)
                final_profile_path = f"files/node-profiles/{final_saved['profileId']}"
                assert run_as("ls", f"{final_profile_path}/profile.json")
                adb("uninstall", PACKAGE)
                adb("install", str(APK))
                files_after_install = adb("shell", "run-as", PACKAGE, "ls", "files", check=False)
                assert "node-profiles" not in files_after_install
                assert "connections.json" not in files_after_install
                print("A4.3 profile lifecycle passed: discard, save/restart, static manifest validation,")
                print("orphan cleanup, malformed-index preservation, path rejection, multi-connection removal and uninstall data clearing.")
            except Exception:
                print(log_path.read_text()[-5000:])
                raise
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("uninstall", PACKAGE, check=False)
                adb("shell", "rm", "-f", remote_tampered, check=False)


if __name__ == "__main__":
    main()
