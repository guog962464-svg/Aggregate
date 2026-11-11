#!/usr/bin/env python3
"""Verify pinned JSON5 source and distribution assets on one Android device."""

import subprocess
import tempfile
import time
from pathlib import Path

from verify_device import APK, PACKAGE, adb, wait_for


def main() -> None:
    if not APK.is_file():
        raise SystemExit(f"Build :nodeprobe:assembleDebug first: {APK}")
    adb("install", "-r", str(APK))
    adb("shell", "am", "force-stop", PACKAGE)
    with tempfile.TemporaryDirectory(prefix="aggregate-a4-") as temporary:
        log_path = Path(temporary) / "logcat.txt"
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
                    adb("shell", "am", "start", "-n", PACKAGE + "/.ProbeActivity",
                        "--es", "probe", "a4-json5")
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
                    }, result
                    if count == 2:
                        assert generation != found[0][0]
                print("A4 JSON5 2.2.3 source, dynamic require, distribution bundle, ESM and private config passed twice.")
            except Exception:
                print(log_path.read_text()[-4000:])
                raise
            finally:
                monitor.terminate()
                monitor.wait(timeout=5)
                adb("uninstall", PACKAGE, check=False)


if __name__ == "__main__":
    main()
