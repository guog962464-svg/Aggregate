#!/usr/bin/env python3
"""Run the isolated Mac Host ↔ physical Android setup integration fixture."""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit


APP_DIR = Path(__file__).resolve().parents[1]
ISOLATED_PACKAGE = "io.github.guog962464.aggregate.integration"
SERVICE_TYPE = "_aggregate-host._tcp"


def run(args: list[str], *, cwd: Path | None = None, **kwargs):
    return subprocess.run(args, cwd=cwd, check=True, **kwargs)


def package_is_installed(device: str, package: str) -> bool:
    result = subprocess.run(
        ["adb", "-s", device, "shell", "pm", "path", package],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip().startswith("package:")


def tail(path: Path, secret: str, count: int = 100) -> str:
    if not path.exists():
        return "(no log was produced)"
    content = path.read_text(errors="replace")
    if secret:
        content = content.replace(secret, "[fixture key redacted]")
    return "\n".join(content.splitlines()[-count:])


def write_executable(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    path.chmod(0o700)


def prepare_fake_ncm(fixture_dir: Path) -> Path:
    fake_home = fixture_dir / "fake-home"
    fake_bin = fake_home / ".local" / "bin"
    for name, output in (
        ("node", "v24.22.3\n"),
        ("npm", "11.11.0\n"),
        ("mpv", "mpv isolated fixture\n"),
    ):
        write_executable(
            fake_bin / name,
            "#!/bin/sh\nprintf '%s\\n' '" + output.rstrip() + "'\n",
        )

    package = fake_home / ".local" / "lib" / "node_modules" / "@music163" / "ncm-cli"
    (package / "bin").mkdir(parents=True)
    (package / "package.json").write_text(
        json.dumps(
            {
                "name": "@music163/ncm-cli",
                "version": "0.1.7-fixture",
                "bin": {"ncm-cli": "bin/ncm-cli"},
            }
        )
    )
    write_executable(
        package / "bin" / "ncm-cli",
        "#!/bin/sh\n"
        "set -eu\n"
        "case \"${1:-}\" in\n"
        "  --version) printf 'ncm-cli isolated fixture\\n' ;;\n"
        "  --help) printf 'isolated fixture only\\n' ;;\n"
        "  config)\n"
        "    if [ \"${2:-}\" = set ] && [ \"${3:-}\" = appId ]; then\n"
        "      printf '%s' \"$4\" > \"$HOME/app-id.txt\"\n"
        "      chmod 600 \"$HOME/app-id.txt\"\n"
        "    elif [ \"${2:-}\" = set ] && [ \"${3:-}\" = privateKey ]; then\n"
        "      cp \"$4\" \"$HOME/private-key.pem\"\n"
        "      chmod 600 \"$HOME/private-key.pem\"\n"
        "    fi\n"
        "    ;;\n"
        "  login)\n"
        "    if [ \"${2:-}\" = \"--check\" ]; then\n"
        "      printf '{\"success\":false}\\n'\n"
        "      exit 1\n"
        "    fi\n"
        "    printf 'fixture login is disabled\\n'\n"
        "    exit 1\n"
        "    ;;\n"
        "  state) printf '{\"state\":\"fixture-playback-idle\"}\\n' ;;\n"
        "  fixture-terminal)\n"
        "    printf 'FIXTURE_TUI_READY\\n'\n"
        "    IFS= read -r fixture_line\n"
        "    printf 'FIXTURE_TUI_ECHO:%s\\n' \"$fixture_line\"\n"
        "    ;;\n"
        "  fixture-terminal-held)\n"
        "    printf '%s\\n' \"$$\" > \"$HOME/host-terminal-pid\"\n"
        "    trap 'printf stopped > \"$HOME/host-terminal-stopped\"; exit 0' TERM\n"
        "    printf 'FIXTURE_TUI_HELD_READY\\n'\n"
        "    while :; do sleep 1; done\n"
        "    ;;\n"
        "  *) exit 0 ;;\n"
        "esac\n",
    )
    (fake_bin / "ncm-cli").symlink_to(package / "bin" / "ncm-cli")
    return fake_home


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--device",
        default=os.environ.get("ANDROID_SERIAL"),
        help="ADB serial of a connected physical Android device",
    )
    options = parser.parse_args()
    if not options.device:
        parser.error("pass --device or set ANDROID_SERIAL")

    device = options.device
    devices = run(["adb", "devices", "-l"], capture_output=True, text=True).stdout
    device_line = next(
        (line for line in devices.splitlines() if line.startswith(device + " ")),
        None,
    )
    if device_line is None or " device " not in device_line:
        parser.error(f"{device} is not an online ADB device")
    if device.startswith("emulator-") or re.search(
        r"(?:^|\s)(?:model:.*(?:emulator|sdk)|device:.*(?:emulator|generic))",
        device_line,
        re.IGNORECASE,
    ):
        parser.error("this acceptance runner requires physical Android hardware")

    package_ids = (ISOLATED_PACKAGE, ISOLATED_PACKAGE + ".test")
    if any(package_is_installed(device, package) for package in package_ids):
        parser.error("an isolated integration package is already installed")

    fixture_dir = Path(tempfile.mkdtemp(prefix="aggregate-host-setup-e2e-"))
    mac_log = fixture_dir / "mac.log"
    android_log = fixture_dir / "android.log"
    fixture_secret_file = fixture_dir / "setup-private-key.pem"
    fixture_secret = ""
    mac_process: subprocess.Popen | None = None
    reverse_port: int | None = None
    reverse_added = False
    android_result_written = False
    success = False

    try:
        run(
            [
                "openssl",
                "pkey",
                "-in",
                str(APP_DIR / "test" / "fixtures" / "host_test_key.pem"),
                "-out",
                str(fixture_secret_file),
            ],
            capture_output=True,
            text=True,
        )
        fixture_secret_file.chmod(0o600)
        fixture_secret = fixture_secret_file.read_text().strip()
        fake_home = prepare_fake_ncm(fixture_dir)
        flutter_executable = shutil.which("flutter")
        if flutter_executable is None:
            raise RuntimeError("flutter executable was not found on PATH")
        dart_executable = (
            Path(flutter_executable).resolve().parent
            / "cache"
            / "dart-sdk"
            / "bin"
            / "dart"
        )
        if not dart_executable.is_file():
            raise RuntimeError("Flutter's bundled Dart executable was not found")
        mac_environment = os.environ.copy()
        mac_environment["HOME"] = str(fake_home)
        mac_environment["AGGREGATE_DART_EXECUTABLE"] = str(dart_executable)
        with mac_log.open("w") as output:
            mac_process = subprocess.Popen(
                [
                    "flutter",
                    "test",
                    "--no-pub",
                    "--reporter",
                    "expanded",
                    "integration_test/macos_android_host_setup_fixture_test.dart",
                    "-d",
                    "macos",
                    f"--dart-define=aggregateHostSetupFixtureDirectory={fixture_dir}",
                ],
                cwd=APP_DIR,
                env=mac_environment,
                stdout=output,
                stderr=subprocess.STDOUT,
            )

        invitation_file = fixture_dir / "invitation.json"
        mcp_invitation_file = fixture_dir / "mcp-invitation.json"
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            if (
                invitation_file.exists()
                and invitation_file.stat().st_size
                and mcp_invitation_file.exists()
                and mcp_invitation_file.stat().st_size
            ):
                break
            if mac_process.poll() is not None:
                raise RuntimeError(
                    f"Mac fixture exited before creating an invitation "
                    f"(exit {mac_process.returncode})"
                )
            time.sleep(0.25)
        else:
            raise TimeoutError("timed out waiting for the loopback invitation")

        payload = invitation_file.read_text()
        invitation = json.loads(payload)
        mcp_payload = mcp_invitation_file.read_text()
        mcp_invitation = json.loads(mcp_payload)
        endpoints = invitation.get("endpoints")
        if invitation.get("serviceType") != SERVICE_TYPE or not isinstance(
            endpoints, list
        ) or len(endpoints) != 1:
            raise RuntimeError("unexpected isolated Host invitation")
        endpoint = endpoints[0].get("uri") if isinstance(endpoints[0], dict) else None
        parsed = urlsplit(endpoint or "")
        if (
            parsed.scheme != "wss"
            or parsed.hostname not in {"127.0.0.1", "localhost"}
            or parsed.path != "/host"
            or parsed.port is None
            or parsed.query
            or parsed.fragment
            or parsed.username
            or parsed.password
        ):
            raise RuntimeError("fixture invitation is not loopback-only WSS")
        if (
            mcp_invitation.get("hostId") != invitation.get("hostId")
            or mcp_invitation.get("certificateSha256")
            != invitation.get("certificateSha256")
            or mcp_invitation.get("endpoints") != endpoints
            or mcp_invitation.get("serviceType") != SERVICE_TYPE
        ):
            raise RuntimeError("MCP fixture invitation does not match the Host")
        reverse_port = parsed.port
        existing_reverse = run(
            ["adb", "-s", device, "reverse", "--list"],
            capture_output=True,
            text=True,
        ).stdout
        if re.search(rf"(?:^|\s)tcp:{reverse_port}(?:\s|$)", existing_reverse):
            raise RuntimeError("ADB already has a reverse mapping on the fixture port")
        run(
            [
                "adb",
                "-s",
                device,
                "reverse",
                f"tcp:{reverse_port}",
                f"tcp:{reverse_port}",
            ],
            capture_output=True,
            text=True,
        )
        reverse_added = True

        environment = os.environ.copy()
        environment["ORG_GRADLE_PROJECT_aggregateIsolatedIntegration"] = "true"
        android_command = [
            "flutter",
            "test",
            "--no-pub",
            "--no-uninstall",
            "--reporter",
            "expanded",
            "integration_test/android_host_setup_e2e_test.dart",
            "-d",
            device,
            "--dart-define=aggregateHostSetupFixtureInvitationBase64="
            + base64.b64encode(payload.encode()).decode(),
            "--dart-define=aggregateHostSetupFixtureSecretBase64="
            + base64.b64encode(fixture_secret.encode()).decode(),
            "--dart-define=aggregateHostMcpFixtureInvitationBase64="
            + base64.b64encode(mcp_payload.encode()).decode(),
        ]
        try:
            with android_log.open("w") as output:
                android = subprocess.run(
                    android_command,
                    cwd=APP_DIR,
                    env=environment,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    timeout=600,
                )
        except subprocess.TimeoutExpired:
            (fixture_dir / "android-result.txt").write_text("failed")
            android_result_written = True
            raise TimeoutError("Android integration test exceeded 10 minutes")

        result = "passed" if android.returncode == 0 else f"failed:{android.returncode}"
        (fixture_dir / "android-result.txt").write_text(result)
        android_result_written = True
        if android.returncode:
            raise RuntimeError(f"Android integration test exited {android.returncode}")

        mac_return = mac_process.wait(timeout=90)
        if mac_return:
            raise RuntimeError(f"Mac fixture test exited {mac_return}")
        for log_path in (mac_log, android_log):
            if fixture_secret in log_path.read_text(errors="replace"):
                raise RuntimeError("fixture private key appeared in an integration log")
        success = True
        print("Mac loopback Host fixture: PASS")
        print("Android physical Keystore + WSS setup flow: PASS")
        print("Scope: test certificate, fake Node/npm/mpv/CLI, isolated HOME and MacRuntime data")
    except Exception as error:
        print(f"INTEGRATION FAILURE: {type(error).__name__}: {error}")
        print("--- Mac fixture (last 100 lines) ---")
        print(tail(mac_log, fixture_secret))
        print("--- Android client (last 100 lines) ---")
        print(tail(android_log, fixture_secret))
    finally:
        if not android_result_written:
            (fixture_dir / "android-result.txt").write_text("failed")
        if mac_process is not None and mac_process.poll() is None:
            mac_process.terminate()
            try:
                mac_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                mac_process.kill()
                mac_process.wait()
        if reverse_added and reverse_port is not None:
            subprocess.run(
                ["adb", "-s", device, "reverse", "--remove", f"tcp:{reverse_port}"],
                capture_output=True,
                text=True,
            )
        for package in package_ids:
            if package_is_installed(device, package):
                subprocess.run(
                    ["adb", "-s", device, "uninstall", package],
                    capture_output=True,
                    text=True,
                )
        shutil.rmtree(fixture_dir, ignore_errors=True)
        print(
            "Cleanup: fixture reverse mapping removed; isolated test packages "
            "removed; normal Aggregate package was not targeted"
        )

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
