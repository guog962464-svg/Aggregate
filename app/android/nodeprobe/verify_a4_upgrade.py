#!/usr/bin/env python3
"""Verify JSON5 package replacement and private config across an APK upgrade."""

import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from verify_device import APK, PACKAGE, adb, wait_for


ANDROID = Path(__file__).resolve().parents[1]
PREPARE = ANDROID / "nodeprobe/prepare_a4.sh"
ACTIVITY = PACKAGE + "/.ProbeActivity"
ARCHIVES = {
    "2.2.2": Path("/tmp/json5-2.2.2.tgz"),
    "2.2.3": Path("/tmp/json5-2.2.3.tgz"),
}


def prepare(version: str) -> None:
    subprocess.run(
        [str(PREPARE), str(ARCHIVES[version]), version],
        cwd=ANDROID,
        check=True,
    )


def build(version_code: int, destination: Path) -> None:
    subprocess.run(
        [
            "./gradlew",
            ":nodeprobe:assembleDebug",
            "--offline",
            "--quiet",
            f"-Pa3ProbeVersionCode={version_code}",
        ],
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
    return set(adb("shell", "run-as", PACKAGE, "ls", "files").splitlines())


def start_probe() -> None:
    adb("shell", "am", "start", "-n", ACTIVITY, "--es", "probe", "a4-json5")


def assert_version_result(result: dict, package_version: str, user_value: str | None) -> None:
    assert result == {
        "node": "v24.22.1",
        "package": "json5",
        "version": package_version,
        "entry": "lib/index.js",
        "bin": "lib/cli.js",
        "source": "works",
        "dynamic": "works",
        "bundled": "works",
        "esm": "works",
        "configPrivate": True,
        "configVersion": package_version,
        "configUserValue": user_value,
    }, result


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="aggregate-a4-upgrade-") as temporary:
        directory = Path(temporary)
        old_apk = directory / "probe-json5-2.2.2-v1.apk"
        new_apk = directory / "probe-json5-2.2.3-v2.apk"
        config = directory / "a4-config.json5"
        stale_file = directory / "stale-resource.js"
        config.write_text('{"enabled":true,"version":"2.2.2","userValue":"keep-me"}\n')
        stale_file.write_text("stale package resource\n")
        remote_config = "/data/local/tmp/aggregate-a4-upgrade-config.json5"
        remote_stale = "/data/local/tmp/aggregate-a4-upgrade-stale.js"

        prepare("2.2.2")
        build(1, old_apk)
        prepare("2.2.3")
        build(2, new_apk)

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
                adb("install", str(old_apk))
                assert installed_version() == 1
                start_probe()
                first = wait_for(log_path, 1)[-1]
                assert_version_result(first[1], "2.2.2", None)
                before = private_files()

                adb("push", str(config), remote_config)
                adb("push", str(stale_file), remote_stale)
                adb(
                    "shell",
                    "run-as",
                    PACKAGE,
                    "cp",
                    remote_config,
                    "files/a4-config.json5",
                )
                adb(
                    "shell",
                    "run-as",
                    PACKAGE,
                    "cp",
                    remote_stale,
                    "files/node_modules/json5/stale-upgrade.js",
                )
                adb("shell", "am", "force-stop", PACKAGE)
                adb("install", "-r", str(new_apk))
                assert installed_version() == 2
                start_probe()
                second = wait_for(log_path, 2)[-1]
                assert second[0] != first[0], "Service generation did not change across upgrade"
                assert_version_result(second[1], "2.2.3", "keep-me")
                assert private_files() == before, "Upgrade changed the app-private root file set"
                assert not adb(
                    "shell",
                    "run-as",
                    PACKAGE,
                    "ls",
                    "files/node_modules/json5/stale-upgrade.js",
                    check=False,
                ), "Old package resource survived package version upgrade"
                print("A4 package upgrade passed: JSON5 2.2.2 -> 2.2.3, APK versionCode 1 -> 2.")
                print("Node reloaded the new package, removed stale files and preserved user config.")
            except Exception:
                print(log_path.read_text()[-4000:])
                raise
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("uninstall", PACKAGE, check=False)
                adb("shell", "rm", "-f", remote_config, remote_stale, check=False)


if __name__ == "__main__":
    main()
