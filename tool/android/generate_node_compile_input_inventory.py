#!/usr/bin/env python3
"""Inventory complete Clang preprocessing inputs for a Node Android candidate.

The existing static-link inventory identifies object files and their sources.
This tool reuses each object's recorded compiler command, changes the dependency
mode from -MMD to -M, and records the complete include graph, including system
headers. It does not compile or attest the Node binary.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import shlex
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any


FORMAT = "aggregate-node-compile-input-inventory-v1"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_from_depfile(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("cmd_") and " := " in line:
            return line.split(" := ", 1)[1]
    raise ValueError("depfile has no recorded compiler command")


def preprocessing_argv(command: str) -> list[str]:
    """Convert a recorded compile command to a dependency-only Clang call."""
    original = shlex.split(command)
    if not original:
        raise ValueError("empty compiler command")

    result: list[str] = []
    index = 0
    while index < len(original):
        arg = original[index]
        if arg in {"-o", "-MF", "-MT", "-MQ"}:
            index += 2
            continue
        if arg in {"-MMD", "-MD", "-MM", "-M", "-c", "-S"}:
            index += 1
            continue
        result.append(arg)
        index += 1
    result.append("-M")
    return result


def dependencies_from_make_output(output: str) -> list[str]:
    collapsed = output.replace("\\\r\n", " ").replace("\\\n", " ")
    if ":" not in collapsed:
        raise ValueError("Clang dependency output has no target separator")
    _, dependency_text = collapsed.split(":", 1)
    return shlex.split(dependency_text)


def recorded_object_command(depfile: Path, object_path: Path) -> tuple[str, str]:
    text = depfile.read_text(errors="strict")
    command = command_from_depfile(text)
    target_prefix = f"{object_path}:"
    if not any(line.startswith(target_prefix) for line in text.splitlines()):
        raise ValueError(f"depfile target does not match object: {object_path}")
    return command, text


def resolve_depfile(build_root: Path, object_path: str) -> Path:
    absolute_object = build_root / object_path
    depfile = build_root / "out/Release/.deps" / absolute_object.as_posix().lstrip("/")
    return Path(f"{depfile}.d")


def ndk_root_from_compiler(compiler: Path, revision: str) -> Path | None:
    parts = compiler.parts
    for index, part in enumerate(parts[:-1]):
        if part == "ndk" and index + 1 < len(parts) and parts[index + 1] == revision:
            return Path(*parts[: index + 2])
    return None


def canonical_input_path(path: str, build_root: Path, ndk_root: Path | None) -> tuple[str, str]:
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = build_root / "out" / candidate
    resolved = candidate.resolve(strict=True)

    try:
        relative = resolved.relative_to(build_root.resolve())
        prefix = "build" if relative.parts and relative.parts[0] == "out" else "source"
        return f"{prefix}/{relative.as_posix()}", str(resolved)
    except ValueError:
        pass

    if ndk_root is not None:
        try:
            relative = resolved.relative_to(ndk_root.resolve())
            return f"ndk/{relative.as_posix()}", str(resolved)
        except ValueError:
            pass

    return f"external/{resolved.as_posix().lstrip('/')}", str(resolved)


def load_objects(repository_root: Path, inventory_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    inventory = json.loads(inventory_path.read_text())
    sidecar = inventory.get("archiveObjectEntriesFile", {}).get("path")
    if not isinstance(sidecar, str):
        raise ValueError("static-link inventory has no archive object sidecar")
    object_path = inventory_path.parent / sidecar
    objects = [json.loads(line) for line in object_path.read_text().splitlines() if line.strip()]
    for direct in inventory.get("directObjectInputs", []):
        objects.append(
            {
                "archive": "direct-object",
                "archiveOrdinal": 1,
                "objectPath": direct["objectPath"],
                "objectSha256": direct["objectSha256"],
                "sourcePaths": direct["sourcePaths"],
                "sourceSha256": direct["sourceSha256"],
                "sourceComponentId": direct["sourceComponentId"],
                "sourceStatus": "direct-object-source",
            }
        )
    return inventory, objects


def scan_object(
    row: dict[str, Any], build_root: Path, progress_lock: threading.Lock, progress: list[int], total: int
) -> tuple[dict[str, Any], list[str], str, str]:
    object_path = build_root / row["objectPath"]
    depfile = resolve_depfile(build_root, row["objectPath"])
    command, depfile_text = recorded_object_command(depfile, object_path)
    argv = preprocessing_argv(command)
    compiler_path = Path(argv[0]).resolve(strict=True)
    completed = subprocess.run(
        argv,
        cwd=build_root / "out",
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"Clang -M failed for {row['objectPath']} ({completed.returncode}): "
            f"{completed.stderr[-1500:]}"
        )
    dependencies = dependencies_from_make_output(completed.stdout)
    if not dependencies:
        raise ValueError(f"Clang produced an empty dependency set: {row['objectPath']}")
    canonical_paths = sorted(set(dependencies))
    command_hash = sha256_bytes(command.encode())
    depfile_hash = sha256_file(depfile)
    record = {
        "archive": row["archive"],
        "archiveOrdinal": row["archiveOrdinal"],
        "objectPath": row["objectPath"],
        "objectSha256": row["objectSha256"],
        "sourcePaths": row["sourcePaths"],
        "sourceSha256": row["sourceSha256"],
        "sourceComponentId": row["sourceComponentId"],
        "sourceStatus": row.get("sourceStatus", ""),
        "depfileSha256": depfile_hash,
        "compilerCommandSha256": command_hash,
        "compilerPath": str(compiler_path),
        "preprocessorDependencyCount": len(canonical_paths),
    }
    with progress_lock:
        progress[0] += 1
        if progress[0] % 100 == 0 or progress[0] == total:
            print(f"[{progress[0]}/{total}] complete", file=sys.stderr, flush=True)
    return record, canonical_paths, command, str(compiler_path)


def build_inventory(
    repository_root: Path,
    build_root: Path,
    static_inventory_path: Path,
    jobs: int = 2,
) -> dict[str, Any]:
    repository_root = repository_root.resolve(strict=True)
    build_root = build_root.resolve(strict=True)
    static_inventory_path = static_inventory_path.resolve(strict=True)
    static_inventory, objects = load_objects(repository_root, static_inventory_path)
    candidate = static_inventory["candidate"]
    revision = candidate["ndkRevision"]

    if jobs < 1 or jobs > 8:
        raise ValueError("jobs must be between 1 and 8")

    progress = [0]
    lock = threading.Lock()
    results: list[tuple[dict[str, Any], list[str], str, str] | None] = [None] * len(objects)
    failures: list[tuple[str, str]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {
            executor.submit(scan_object, row, build_root, lock, progress, len(objects)): index
            for index, row in enumerate(objects)
        }
        for future in concurrent.futures.as_completed(futures):
            index = futures[future]
            try:
                results[index] = future.result()
            except Exception as error:  # noqa: BLE001 - report all failed object inputs.
                failures.append((objects[index]["objectPath"], str(error)))
    if failures:
        preview = "\n".join(f"- {path}: {error}" for path, error in failures[:20])
        raise RuntimeError(f"{len(failures)} object dependency scans failed:\n{preview}")

    completed_results = [result for result in results if result is not None]
    compiler_paths = sorted({result[3] for result in completed_results})
    ndk_roots = {
        root
        for compiler in compiler_paths
        if (root := ndk_root_from_compiler(Path(compiler), revision)) is not None
    }
    if len(ndk_roots) != 1:
        raise ValueError(f"expected one NDK root for revision {revision}, found {sorted(map(str, ndk_roots))}")
    ndk_root = next(iter(ndk_roots)).resolve(strict=True)

    input_paths: set[str] = set()
    object_records: list[dict[str, Any]] = []
    commands_by_compiler: dict[str, set[str]] = {}
    for record, dependencies, command, compiler in completed_results:
        normalized: list[str] = []
        for dependency in dependencies:
            display_path, absolute_path = canonical_input_path(dependency, build_root, ndk_root)
            if not Path(absolute_path).is_file():
                raise FileNotFoundError(f"dependency input is not a file: {absolute_path}")
            normalized.append(display_path)
            input_paths.add(display_path)
        normalized = sorted(set(normalized))
        record["preprocessorDependencyCount"] = len(normalized)
        record["dependencySetSha256"] = sha256_bytes("\n".join(normalized).encode())
        object_records.append(record)
        commands_by_compiler.setdefault(compiler, set()).add(command)

    # Keep source object order stable even though preprocessing is parallel.
    object_records.sort(key=lambda row: (row["archive"], row["archiveOrdinal"], row["objectPath"]))

    unique_inputs: list[dict[str, Any]] = []
    path_by_display: dict[str, Path] = {}
    for display_path in sorted(input_paths):
        if display_path.startswith("source/"):
            absolute = build_root / display_path.removeprefix("source/")
            kind = "source-or-generated"
        elif display_path.startswith("build/"):
            absolute = build_root / display_path.removeprefix("build/")
            kind = "generated-build-input"
        elif display_path.startswith("ndk/"):
            absolute = ndk_root / display_path.removeprefix("ndk/")
            kind = "ndk-package"
        else:
            absolute = Path("/") / display_path.removeprefix("external/")
            kind = "external"
        absolute = absolute.resolve(strict=True)
        path_by_display[display_path] = absolute
        unique_inputs.append(
            {
                "path": display_path,
                "kind": kind,
                "sha256": sha256_file(absolute),
                "sizeBytes": absolute.stat().st_size,
            }
        )

    compiler_records: list[dict[str, Any]] = []
    for compiler_path in compiler_paths:
        compiler = Path(compiler_path)
        version = subprocess.run(
            [str(compiler), "--version"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if version.returncode != 0:
            raise RuntimeError(f"compiler --version failed: {compiler_path}: {version.stderr[-500:]}")
        compiler_records.append(
            {
                "path": compiler.relative_to(ndk_root).as_posix(),
                "sha256": sha256_file(compiler),
                "versionOutput": version.stdout.strip(),
                "commandCount": len(commands_by_compiler.get(str(compiler), set())),
            }
        )

    package_metadata: list[dict[str, Any]] = []
    for relative in ("source.properties", "package.xml"):
        path = ndk_root / relative
        if path.is_file():
            package_metadata.append(
                {"path": relative, "sha256": sha256_file(path), "sizeBytes": path.stat().st_size}
            )

    config_files = []
    for relative in ("config.gypi", "out/Makefile", "tools/v8_gypfiles/toolchain.gypi"):
        path = build_root / relative
        if path.is_file():
            config_files.append(
                {"path": relative, "sha256": sha256_file(path), "sizeBytes": path.stat().st_size}
            )

    return {
        "format": FORMAT,
        "candidate": candidate,
        "buildTree": {
            "kind": "existing patched Node source/build tree; not a clean rebuild",
            "sourceRootAtObservation": str(build_root),
            "nodeVersion": candidate["nodeVersion"],
            "ndkRevision": revision,
            "abi": candidate["androidAbi"],
            "api": candidate["androidApi"],
            "staticLinkInventorySha256": sha256_file(static_inventory_path),
        },
        "method": {
            "commandSource": "compiler command captured in each make dependency sidecar",
            "dependencyMode": "re-run exact compiler flags with -M instead of -MMD; no object code emitted",
            "systemHeadersIncluded": True,
            "objectCount": len(object_records),
            "uniqueDependencyInputCount": len(unique_inputs),
            "dependencyRelationCount": sum(row["preprocessorDependencyCount"] for row in object_records),
            "limits": [
                "Preprocessor dependency discovery is not a compile or binary build attestation.",
                "Generator command inputs are not closed by object compiler dependency graphs.",
                "NDK implicit archive member sources and build configuration generators remain separate closure items.",
            ],
        },
        "compilerInputs": compiler_records,
        "ndkPackageMetadata": package_metadata,
        "buildConfigurationFiles": config_files,
        "objects": object_records,
        "dependencies": unique_inputs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, required=True)
    parser.add_argument("--build-root", type=Path, required=True)
    parser.add_argument("--static-inventory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()

    try:
        inventory = build_inventory(
            args.repository_root,
            args.build_root,
            args.static_inventory,
            args.jobs,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(inventory, ensure_ascii=False, indent=2) + "\n")
    except Exception as error:  # noqa: BLE001 - CLI should return one actionable failure.
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(
        f"wrote {args.output}: {inventory['method']['objectCount']} objects, "
        f"{inventory['method']['uniqueDependencyInputCount']} unique inputs"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
