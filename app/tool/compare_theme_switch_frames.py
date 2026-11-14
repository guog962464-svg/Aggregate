"""Create unmasked, timestamp-aligned image differences from an export manifest.

uv run --python 3.13 --with pillow==13.0.0 --with numpy==2.5.4 \
  python tool/compare_theme_switch_frames.py manifest.json output-directory
"""

import argparse
import csv
import json
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name in ("reference", "render", "difference"):
        (output / name).mkdir(exist_ok=True)

    crop = manifest["scene"].get("referenceCrop")
    results = []
    for frame in manifest["frames"]:
        reference = Image.open(frame["referencePath"]).convert("RGB")
        if crop:
            reference = reference.crop((
                crop["x"], crop["y"],
                crop["x"] + crop["width"], crop["y"] + crop["height"],
            ))
        rendered = Image.open(frame["renderPath"]).convert("RGB")
        if reference.size != rendered.size:
            raise ValueError(f"Frame {frame['index']}: unequal image sizes")
        delta = np.abs(np.asarray(reference, dtype=float) - np.asarray(rendered, dtype=float))
        # This fixed ROI includes the handle, recess and nearby edge light.
        control = delta[170:360, 185:535]
        filename = f"frame_{frame['index']:04d}.png"
        paths = {name: f"{name}/{filename}" for name in ("reference", "render", "difference")}
        reference.save(output / paths["reference"])
        rendered.save(output / paths["render"])
        Image.fromarray(np.uint8(np.minimum(delta * 4, 255))).save(output / paths["difference"])
        results.append({
            "frame": frame["index"], "pts": frame["pts"],
            "eligible": frame["comparisonEligible"],
            "openingMedia": manifest.get("sourceMode", "recording") == "recording" and frame["pts"] < 1.52,
            "mae": float(delta.mean()), "controlMae": float(control.mean()),
            "maxError": float(delta.max()),
            "identicalPixels": float((delta.max(axis=2) == 0).mean()),
            "paths": paths,
        })

    eligible = [row for row in results if row["eligible"]]
    stable = [row for row in eligible if 1.52 <= row["pts"] <= 4.25]
    summary = {
        "manifest": str(args.manifest.resolve()),
        "sourceMode": manifest.get("sourceMode", "recording"),
        "frameCount": len(results), "eligibleFrameCount": len(eligible),
        "meanMae": float(np.mean([row["mae"] for row in eligible])),
        "allFrameMeanMae": float(np.mean([row["mae"] for row in results])),
        "maximumFrameMae": max(row["mae"] for row in eligible),
        "mask": "none",
        "comparison": "same timestamp, fixed crop, no image registration or color correction",
        "limitations": manifest.get("limitations", []),
    }
    if manifest.get("sourceMode", "recording") == "recording" and stable:
        summary["stableView"] = {
            "intervalSeconds": [1.52, 4.25],
            "frameCount": len(stable),
            "meanMae": float(np.mean([row["mae"] for row in stable])),
            "meanControlMae": float(np.mean([row["controlMae"] for row in stable])),
            "scope": "Additional fixed interval after opening media zoom and before ending gallery blend; all frames remain in the full report.",
        }
    (output / "metrics.json").write_text(json.dumps({"summary": summary, "frames": results}, indent=2))
    with (output / "metrics.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=[key for key in results[0] if key != "paths"])
        writer.writeheader()
        writer.writerows({key: value for key, value in row.items() if key != "paths"} for row in results)
    template = Path(__file__).with_name("theme_switch_comparison.html").read_text()
    data = json.dumps({"summary": summary, "frames": results}, ensure_ascii=False).replace("</", "<\\/")
    (output / "index.html").write_text(template.replace("__FRAME_DATA__", data))
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
