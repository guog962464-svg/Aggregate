"""Profile the visible Android theme switch without reinstalling or changing VM flags.

Position Aggregate at Settings > Appearance with its whole control and Follow System
button visible. URI_FILE must contain a privately obtained, forwarded VM-service URI.
Requires adb and Node24+. Never prints or stores UI XML, field contents, or VM URI.
Exit0: at most5% build/raster frames over budget;1: over5%;2: any failure/no data.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET

PACKAGE = "io.github.guog962464.aggregate"
SWIPE_MS = 450
REST_MS = 650
FAILURE_RATIO = 0.05


class ProfileError(Exception):
    """Only fixed status codes; never include raw command output or URI details."""


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--uri-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--budget-ms", type=float, default=16.667)
    parser.add_argument("--seconds", type=float, default=10)
    parser.add_argument("--repeats", type=int, default=3)
    args = parser.parse_args()
    if not math.isfinite(args.budget_ms) or args.budget_ms <= 0:
        parser.error("--budget-ms must be finite and positive")
    if not math.isfinite(args.seconds) or not 0 < args.seconds <= 60:
        parser.error("--seconds must be in (0,60]")
    if args.repeats < 1 or args.seconds < args.repeats * 2 * (SWIPE_MS + REST_MS) / 1000 + 1:
        parser.error("capture must cover the requested gestures plus at least1s margin")
    return args


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as file:
            json.dump(data, file, ensure_ascii=False, indent=2)
        os.replace(temp, path)
    finally:
        Path(temp).unlink(missing_ok=True)


class Workload:
    def __init__(self, args):
        self.args = args
        self.xml_cleanup_failures = 0

    def adb(self, *args):
        try:
            result = subprocess.run(
                ["adb", "-s", self.args.device, *args],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=20, check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            raise ProfileError("adb_unavailable_or_timed_out") from None
        if result.returncode:
            raise ProfileError("adb_command_failed")
        return result.stdout

    def guard(self):
        focus = self.adb("shell", "dumpsys", "window")
        if not re.search(r"mCurrentFocus=.*\b" + re.escape(PACKAGE) + r"/", focus):
            raise ProfileError("target_app_not_foreground")

    def nodes(self):
        self.guard()
        remote = f"/data/local/tmp/aggregate-theme-perf-{uuid.uuid4().hex}.xml"
        try:
            self.adb("shell", "uiautomator", "dump", remote)
            text = self.adb("exec-out", "cat", remote)
            root = ET.fromstring(text)
            return [node for node in root.iter("node") if node.get("package") == PACKAGE]
        except ET.ParseError:
            raise ProfileError("ui_xml_invalid") from None
        finally:
            try:
                self.adb("shell", "rm", "-f", remote)
            except ProfileError:
                self.xml_cleanup_failures += 1
                raise ProfileError("ui_xml_cleanup_failed") from None

    @staticmethod
    def bounds(node):
        values = list(map(int, re.findall(r"-?\d+", node.get("bounds", ""))))
        if len(values) != 4:
            raise ProfileError("ui_bounds_missing")
        x0, y0, x1, y1 = values
        if x0 < 0 or y0 < 0 or x1 <= x0 or y1 <= y0:
            raise ProfileError("ui_bounds_not_visible")
        return values

    def appearance(self):
        items = self.nodes()
        controls = [n for n in items if "外观主题" in n.get("content-desc", "")]
        follows = [n for n in items if n.get("content-desc") == "跟随系统"]
        if len(controls) != 1 or len(follows) != 1:
            raise ProfileError("visible_theme_controls_not_found")
        theme, follow = controls[0], follows[0]
        box, follow_box = self.bounds(theme), self.bounds(follow)
        x0, y0, x1, y1 = box
        width, height = x1 - x0, y1 - y0
        if abs(height - width * 0.75) > 3:
            raise ProfileError("theme_control_clipped_reposition_before_sampling")
        description = theme.get("content-desc", "")
        light, dark = "浅色" in description, "深色" in description
        if light == dark or follow.get("selected") not in ("true", "false"):
            raise ProfileError("appearance_state_ambiguous")
        return {"light": light, "followSystem": follow.get("selected") == "true",
                "bounds": box, "followBounds": follow_box}

    def tap(self, box):
        self.guard()
        a, b, c, d = box
        self.adb("shell", "input", "tap", str((a + c) // 2), str((b + d) // 2))

    def restore(self, original):
        current = self.appearance()
        if original["followSystem"]:
            if not current["followSystem"]:
                self.tap(current["followBounds"])
                time.sleep(0.7)
        else:
            # A tap commits an explicit preference and toggles the effective
            # theme. A system preference already showing the desired endpoint
            # therefore needs two taps to restore the original explicit mode.
            for _ in range(2):
                if not current["followSystem"] and current["light"] == original["light"]:
                    break
                self.tap(current["bounds"])
                time.sleep(0.7)
                current = self.appearance()
        current = self.appearance()
        restored = current["followSystem"] == original["followSystem"] and (
            original["followSystem"] or current["light"] == original["light"])
        if not restored:
            raise ProfileError("initial_appearance_not_restored")
        return True


def main():
    args = arguments()
    workload = Workload(args)
    report = {"summary": {"status": "FAILED"}, "frames": [], "workload": {
        "package": PACKAGE,
        "deviceSerialSHA256": hashlib.sha256(args.device.encode()).hexdigest(),
        "requestedBudgetMs": args.budget_ms, "requestedSeconds": args.seconds,
        "repeats": args.repeats, "swipeDurationMs": SWIPE_MS, "restDurationMs": REST_MS,
        "requestedSwipeCount": args.repeats * 2, "completedSwipeCount": 0,
        "failureThresholdRatio": FAILURE_RATIO,
        "uiXmlStorage": "/data/local/tmp only; read in memory then removed",
        "profilingFlagsChanged": False, "appInstalledOrReloaded": False,
        "initialAppearanceRestored": False,
    }}
    metadata = report["workload"]
    original = None
    process = None
    capture_file = None
    failure = None
    capture = None
    try:
        if not args.uri_file.is_file() or not shutil.which("adb") or not shutil.which("node"):
            raise ProfileError("uri_file_or_required_tools_missing")
        workload.guard()
        original = workload.appearance()
        metadata["initialAppearance"] = "system" if original["followSystem"] else "light" if original["light"] else "dark"
        metadata["initialEffectiveLight"] = original["light"]
        metadata["controlBounds"] = original["bounds"]
        x0, y0, x1, y1 = original["bounds"]
        width = x1 - x0
        center_x = (x0 + x1) / 2
        center_y = y0 + width * 0.375 - width * 3 / 720
        offset = 104 * width * 0.76 / 720
        left, right, y = round(center_x - offset), round(center_x + offset), round(center_y)
        if not (x0 < left < right < x1 and y0 < y < y1):
            raise ProfileError("gesture_points_outside_visible_control")
        metadata["swipePoints"] = {"left": [left, y], "right": [right, y]}
        metadata["coordinateModel"] = "nominal glass scene0.76/720; full visible control bounds"
        args.output.parent.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(prefix=args.output.name + ".capture.", suffix=".json", dir=args.output.parent)
        os.close(fd)
        capture_file = Path(name)
        sampler = Path(__file__).with_name("sample_theme_switch_frames.cjs")
        process = subprocess.Popen(
            ["node", str(sampler), str(args.uri_file), str(capture_file),
             str(args.seconds), str(args.budget_ms * 1000)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            if not selector.select(timeout=16):
                raise ProfileError("sampler_ready_timeout")
            ready = process.stdout.readline()
        if not ready.startswith("READY:"):
            raise ProfileError("sampler_not_ready")
        print(f"READY: {args.repeats * 2} visible-control swipes; budget {args.budget_ms:g}ms", flush=True)
        sequence = [(right, left), (left, right)] if original["light"] else [(left, right), (right, left)]
        started = time.monotonic()
        for _ in range(args.repeats):
            for start, end in sequence:
                workload.guard()
                if process.poll() is not None:
                    raise ProfileError("capture_ended_before_workload")
                workload.adb("shell", "input", "swipe", str(start), str(y), str(end), str(y), str(SWIPE_MS))
                metadata["completedSwipeCount"] += 1
                time.sleep(REST_MS / 1000)
        metadata["gestureWorkloadElapsedSeconds"] = time.monotonic() - started
        metadata["samplingCoveredAllGestures"] = process.poll() is None
        if not metadata["samplingCoveredAllGestures"]:
            raise ProfileError("capture_ended_before_workload")
        process.communicate(timeout=args.seconds + 15)
        if process.returncode not in (0, 1):
            raise ProfileError("frame_sampler_failed")
        capture = json.loads(capture_file.read_text())
        summary = capture.get("summary", {})
        ratio = summary.get("buildOrRasterOverBudgetRatio")
        if not summary.get("frameCount") or not isinstance(ratio, (int, float)) or not math.isfinite(ratio):
            raise ProfileError("frame_data_missing")
    except (ProfileError, OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        failure = str(error) if isinstance(error, ProfileError) else "profiling_workload_failed"
    except KeyboardInterrupt:
        failure = "profiling_interrupted"
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
        if original is not None:
            try:
                metadata["initialAppearanceRestored"] = workload.restore(original)
            except ProfileError as error:
                metadata["restoreFailure"] = str(error)
                failure = failure or "appearance_restore_failed"
        metadata["uiXmlCleanupFailures"] = workload.xml_cleanup_failures
        if capture_file is not None:
            capture_file.unlink(missing_ok=True)
    if capture is not None:
        report["summary"], report["frames"] = capture["summary"], capture.get("frames", [])
    if failure:
        metadata["failure"] = failure
        report["summary"]["status"] = "FAILED"
        code = 2
    else:
        code = 1 if report["summary"]["buildOrRasterOverBudgetRatio"] > FAILURE_RATIO else 0
        report["summary"]["status"] = "JANK_REPRODUCED" if code else "PASS"
    try:
        write_json(args.output, report)
    except OSError:
        print("Profiling report could not be written; details redacted.")
        return 2
    print(json.dumps({"status": report["summary"]["status"], "frameCount": report["summary"].get("frameCount", 0),
                      "buildOrRasterOverBudgetRatio": report["summary"].get("buildOrRasterOverBudgetRatio"),
                      "initialAppearanceRestored": metadata["initialAppearanceRestored"]}, ensure_ascii=False))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
