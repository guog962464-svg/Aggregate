#!/usr/bin/env python3
"""Map Node source-generator executables to host objects and compiler inputs.

The generator binaries are read from an existing configured Node Android build
tree. This tool binds their GYP link inputs, archive members, build objects,
recorded compiler commands and full Clang dependency graphs. It does not
rebuild or attest those binaries.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import re
import shlex
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any


FORMAT = "aggregate-node-generator-tool-source-map-v1"
GENERATOR_TOOLS = (
    "gen-regexp-special-case",
    "genccode",
    "mksnapshot",
    "node_js2c",
    "torque",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collapse_make(text: str) -> list[str]:
    return re.sub(r"\\\r?\n[ \t]*", " ", text).splitlines()


def parse_archive_members(data: bytes) -> list[tuple[str, bytes]]:
    """Read Apple/BSD or GNU ar members, excluding the archive symbol table."""
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("unsupported or invalid archive format")
    raw_members: list[tuple[str, bytes]] = []
    offset = 8
    while offset < len(data):
        header = data[offset : offset + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise ValueError(f"invalid ar header at byte {offset}")
        raw_name = header[:16].decode("ascii").strip()
        try:
            size = int(header[48:58].decode("ascii").strip())
        except ValueError as error:
            raise ValueError(f"invalid ar member size at byte {offset}") from error
        start = offset + 60
        end = start + size
        if end > len(data):
            raise ValueError(f"truncated ar member at byte {offset}")
        raw_members.append((raw_name, data[start:end]))
        offset = end + (size & 1)

    string_table = next((payload for name, payload in raw_members if name == "//"), b"")
    members: list[tuple[str, bytes]] = []
    for raw_name, payload in raw_members:
        if raw_name in {"/", "//"}:
            continue
        if raw_name.startswith("/") and raw_name[1:].isdigit():
            start = int(raw_name[1:])
            end = string_table.find(b"/\n", start)
            if end < 0:
                raise ValueError(f"unterminated GNU ar long name at offset {start}")
            name = string_table[start:end].decode("utf-8")
        elif raw_name.startswith("#1/"):
            name_size = int(raw_name[3:])
            if name_size > len(payload):
                raise ValueError(f"invalid BSD ar long name length for {raw_name}")
            name = payload[:name_size].decode("utf-8").rstrip("\0")
            payload = payload[name_size:]
        else:
            name = raw_name.rstrip("/")
        if name.startswith("__.SYMDEF"):
            continue
        members.append((name, payload))
    return members


def parse_tool_makefile(makefile: Path, build_root: Path) -> dict[str, Any]:
    text = makefile.read_text(errors="strict")
    lines = collapse_make(text)
    header = text.splitlines()[:8]
    target = next((line.split(":=", 1)[1].strip() for line in header if line.startswith("TARGET :=")), "")
    toolset = next((line.split(":=", 1)[1].strip() for line in header if line.startswith("TOOLSET :=")), "")
    if not target or toolset != "host":
        raise ValueError(f"not a generated host-tool makefile: {makefile}")

    object_tokens: list[str] | None = None
    link_tokens: list[str] | None = None
    for line in lines:
        if line.startswith("OBJS :="):
            object_tokens = shlex.split(line.split(":=", 1)[1])
        if line.startswith(f"$(builddir)/{target}: LD_INPUTS :="):
            link_tokens = shlex.split(line.split(":=", 1)[1])
    if object_tokens is None or link_tokens is None:
        raise ValueError(f"host tool makefile lacks OBJS or LD_INPUTS: {makefile}")

    release = build_root / "out/Release"

    def expand(token: str) -> Path:
        expanded = token
        for variable, value in (
            ("$(obj).host", str(release / "obj.host")),
            ("$(obj).target", str(release / "obj.target")),
            ("$(obj)", str(release / "obj")),
            ("$(builddir)", str(release)),
            ("$(TARGET)", target),
            ("$(TOOLSET)", "host"),
            ("$(BUILDTYPE)", "Release"),
        ):
            expanded = expanded.replace(variable, value)
        if "$" in expanded:
            raise ValueError(f"unsupported make variable in {makefile}: {token}")
        path = Path(expanded)
        if not path.is_absolute():
            path = build_root / "out" / path
        return path.resolve(strict=True)

    object_paths = [expand(token) for token in object_tokens if token.endswith(".o")]
    link_inputs: list[Path] = []
    for token in link_tokens:
        if token == "$(OBJS)":
            link_inputs.extend(object_paths)
        elif token.endswith((".o", ".a")):
            link_inputs.append(expand(token))
    if not object_paths:
        raise ValueError(f"host tool has no direct object inputs: {makefile}")
    if not link_inputs:
        raise ValueError(f"host tool has no parsed link inputs: {makefile}")
    return {
        "name": target,
        "makefilePath": makefile.relative_to(build_root).as_posix(),
        "makefileSha256": sha256_file(makefile),
        "objectPaths": object_paths,
        "linkInputs": link_inputs,
        "binaryPath": (release / target).resolve(strict=True),
    }


def depfile_for_object(build_root: Path, object_path: Path) -> Path:
    depfile = build_root / "out/Release/.deps" / object_path.as_posix().lstrip("/")
    return Path(f"{depfile}.d")


def command_from_depfile(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("cmd_") and " := " in line:
            return line.split(" := ", 1)[1]
    raise ValueError("compiler depfile has no recorded command")


def preprocessing_argv(command: str) -> list[str]:
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
        raise ValueError("compiler dependency output has no target separator")
    _, dependency_text = collapsed.split(":", 1)
    return shlex.split(dependency_text)


def object_command(depfile: Path, object_path: Path) -> tuple[str, str]:
    text = depfile.read_text(errors="strict")
    command = command_from_depfile(text)
    target_prefix = f"{object_path}:"
    if not any(line.startswith(target_prefix) for line in text.splitlines()):
        raise ValueError(f"compiler depfile target mismatch: {object_path}")
    return command, text


def display_path(path: Path, build_root: Path) -> str:
    resolved = path.resolve(strict=True)
    try:
        relative = resolved.relative_to(build_root.resolve())
        prefix = "build" if relative.parts and relative.parts[0] == "out" else "source"
        return f"{prefix}/{relative.as_posix()}"
    except ValueError:
        return f"external/{resolved.as_posix().lstrip('/')}"


def scan_object(
    object_path: Path,
    build_root: Path,
    lock: threading.Lock,
    progress: list[int],
    total: int,
) -> tuple[dict[str, Any], list[str], str, Path]:
    depfile = depfile_for_object(build_root, object_path)
    command, depfile_text = object_command(depfile, object_path)
    argv = preprocessing_argv(command)
    compiler = Path(argv[0]).resolve(strict=True)
    result = subprocess.run(
        argv,
        cwd=build_root / "out",
        capture_output=True,
        text=True,
        errors="replace",
        timeout=120,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(
            f"Clang -M failed for {object_path} ({result.returncode}): {result.stderr[-1200:]}"
        )
    dependencies = sorted(set(result_dependencies := dependencies_from_make_output(result.stdout)))
    if not dependencies:
        raise ValueError(f"empty compiler dependency set: {object_path}")
    source = Path(dependencies[0])
    if not source.is_absolute():
        source = (build_root / "out" / source).resolve(strict=True)
    else:
        source = source.resolve(strict=True)
    if not source.is_file():
        raise ValueError(f"first compiler dependency is not a source file: {source}")
    record = {
        "objectPath": display_path(object_path, build_root),
        "objectSha256": sha256_file(object_path),
        "sourcePath": display_path(source, build_root),
        "sourceSha256": sha256_file(source),
        "depfileSha256": sha256_bytes(depfile_text.encode()),
        "compilerCommandSha256": sha256_bytes(command.encode()),
        "compilerPath": str(compiler),
        "preprocessorDependencyCount": len(result_dependencies),
    }
    with lock:
        progress[0] += 1
        if progress[0] % 100 == 0 or progress[0] == total:
            print(f"[{progress[0]}/{total}] host objects complete", file=sys.stderr, flush=True)
    return record, dependencies, command, compiler


def canonical_dependency(token: str, build_root: Path) -> tuple[str, Path]:
    path = Path(token)
    if not path.is_absolute():
        path = build_root / "out" / path
    path = path.resolve(strict=True)
    if not path.is_file():
        raise ValueError(f"compiler dependency is not a file: {path}")
    return display_path(path, build_root), path


def build_map(
    build_root: Path,
    generated_source_map_path: Path,
    jobs: int = 2,
) -> dict[str, Any]:
    build_root = build_root.resolve(strict=True)
    generated_source_map_path = generated_source_map_path.resolve(strict=True)
    if jobs < 1 or jobs > 8:
        raise ValueError("jobs must be between 1 and 8")
    generated_map = json.loads(generated_source_map_path.read_text())
    source_root = build_root / "out"
    makefiles = list(source_root.rglob("*.host.mk"))
    parsed_by_name: dict[str, dict[str, Any]] = {}
    for name in GENERATOR_TOOLS:
        matches = []
        for makefile in makefiles:
            header = makefile.read_text(errors="strict").splitlines()[:8]
            target = next(
                (line.split(":=", 1)[1].strip() for line in header if line.startswith("TARGET :=")),
                "",
            )
            if target == name:
                matches.append(parse_tool_makefile(makefile, build_root))
        if len(matches) != 1:
            raise ValueError(f"expected one host makefile for {name}, found {len(matches)}")
        parsed_by_name[name] = matches[0]

    archive_records: dict[str, dict[str, Any]] = {}
    object_memberships: dict[Path, list[dict[str, Any]]] = {}
    tool_link_inputs: dict[str, list[Path]] = {}
    for tool_name, tool in parsed_by_name.items():
        tool_link_inputs[tool_name] = tool["linkInputs"]
        for link_ordinal, path in enumerate(tool["linkInputs"], start=1):
            if path.suffix == ".o":
                object_memberships.setdefault(path, []).append(
                    {
                        "tool": tool_name,
                        "linkInputType": "direct-object",
                        "linkOrdinal": link_ordinal,
                    }
                )
            if path.suffix != ".a":
                continue
            archive_display = display_path(path, build_root)
            if archive_display not in archive_records:
                file_list = Path(str(path) + ".ar-file-list")
                object_paths = [
                    Path(line.strip()).resolve(strict=True)
                    for line in file_list.read_text(errors="strict").splitlines()
                    if line.strip()
                ]
                members = parse_archive_members(path.read_bytes())
                expected_names = [object_path.name for object_path in object_paths]
                actual_names = [name for name, _ in members]
                if actual_names != expected_names:
                    raise ValueError(f"archive member order differs from GYP ar-file-list: {path}")
                member_rows = []
                for ordinal, ((member_name, payload), object_path) in enumerate(
                    zip(members, object_paths, strict=True), start=1
                ):
                    object_bytes = object_path.read_bytes()
                    if payload != object_bytes:
                        raise ValueError(f"archive member differs from listed object: {path}({member_name})")
                    member_rows.append(
                        {
                            "ordinal": ordinal,
                            "memberName": member_name,
                            "objectPath": display_path(object_path, build_root),
                            "objectSha256": sha256_bytes(object_bytes),
                        }
                    )
                    object_memberships.setdefault(object_path, []).append(
                        {
                            "tool": tool_name,
                            "archivePath": archive_display,
                            "archiveOrdinal": ordinal,
                            "memberName": member_name,
                        }
                    )
                archive_records[archive_display] = {
                    "path": archive_display,
                    "sha256": sha256_file(path),
                    "sizeBytes": path.stat().st_size,
                    "arFileListPath": display_path(file_list, build_root),
                    "arFileListSha256": sha256_file(file_list),
                    "memberCount": len(member_rows),
                    "memberOrderMatchesFileList": True,
                    "allMemberPayloadsMatchListedObjects": True,
                    "members": member_rows,
                }
                for object_path in object_paths:
                    object_memberships.setdefault(object_path, [])
            else:
                file_list = Path(str(path) + ".ar-file-list")
                object_paths = [
                    Path(line.strip()).resolve(strict=True)
                    for line in file_list.read_text(errors="strict").splitlines()
                    if line.strip()
                ]
                for ordinal, object_path in enumerate(object_paths, start=1):
                    object_memberships.setdefault(object_path, []).append(
                        {
                            "tool": tool_name,
                            "archivePath": archive_display,
                            "archiveOrdinal": ordinal,
                            "memberName": object_path.name,
                        }
                    )

    unique_objects: set[Path] = set(object_memberships)
    for tool in parsed_by_name.values():
        unique_objects.update(tool["objectPaths"])
    object_paths = sorted(unique_objects, key=lambda path: path.as_posix())
    progress = [0]
    lock = threading.Lock()
    results: list[tuple[dict[str, Any], list[str], str, Path] | None] = [None] * len(object_paths)
    failures: list[tuple[str, str]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {
            executor.submit(scan_object, path, build_root, lock, progress, len(object_paths)): index
            for index, path in enumerate(object_paths)
        }
        for future in concurrent.futures.as_completed(futures):
            index = futures[future]
            try:
                results[index] = future.result()
            except Exception as error:  # noqa: BLE001 - collect all compiler closure failures.
                failures.append((str(object_paths[index]), str(error)))
    if failures:
        preview = "\n".join(f"- {path}: {error}" for path, error in failures[:20])
        raise RuntimeError(f"{len(failures)} host object dependency scans failed:\n{preview}")

    completed = [result for result in results if result is not None]
    compiler_paths = sorted({result[3] for result in completed}, key=str)
    dependencies_by_display: dict[str, Path] = {}
    object_rows: list[dict[str, Any]] = []
    for result, dependencies, command, compiler in completed:
        normalized = sorted({canonical_dependency(path, build_root)[0] for path in dependencies})
        for display in normalized:
            if display.startswith("source/"):
                path = build_root / display.removeprefix("source/")
            elif display.startswith("build/"):
                path = build_root / display.removeprefix("build/")
            else:
                path = Path("/") / display.removeprefix("external/")
            dependencies_by_display[display] = path.resolve(strict=True)
        result["dependencySetSha256"] = sha256_bytes("\n".join(normalized).encode())
        result["preprocessorDependencyCount"] = len(normalized)
        object_rows.append(result)

    # Keep archive object memberships precise after source-path normalization.
    membership_by_display: dict[str, list[dict[str, Any]]] = {}
    for object_path, memberships in object_memberships.items():
        membership_by_display[display_path(object_path, build_root)] = memberships
    for row in object_rows:
        row["generatorToolMemberships"] = membership_by_display.get(row["objectPath"], [])

    compiler_records: list[dict[str, Any]] = []
    for compiler in compiler_paths:
        version = subprocess.run(
            [str(compiler), "--version"],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=30,
            check=False,
        )
        if version.returncode:
            raise RuntimeError(f"compiler --version failed: {compiler}: {version.stderr[-500:]}")
        compiler_records.append(
            {
                "path": str(compiler),
                "sha256": sha256_file(compiler),
                "versionOutput": version.stdout.strip(),
                "commandCount": sum(1 for item in completed if item[3] == compiler),
            }
        )

    file_records = [
        {
            "path": display,
            "sha256": sha256_file(path),
            "sizeBytes": path.stat().st_size,
        }
        for display, path in sorted(dependencies_by_display.items())
    ]

    tools: list[dict[str, Any]] = []
    for name, parsed in parsed_by_name.items():
        binary = parsed["binaryPath"]
        display_link_inputs = [display_path(path, build_root) for path in tool_link_inputs[name]]
        tools.append(
            {
                "name": name,
                "binaryPath": display_path(binary, build_root),
                "binarySha256": sha256_file(binary),
                "binarySizeBytes": binary.stat().st_size,
                "hostMakefilePath": parsed["makefilePath"],
                "hostMakefileSha256": parsed["makefileSha256"],
                "linkInputPaths": display_link_inputs,
                "linkInputListSha256": sha256_bytes("\n".join(display_link_inputs).encode()),
                "directObjectCount": len(parsed["objectPaths"]),
                "archiveInputPaths": [path for path in display_link_inputs if path.endswith(".a")],
            }
        )

    configuration_paths = {build_root / "out/Makefile"}
    configuration_paths.update(
        build_root / tool["makefilePath"] for tool in parsed_by_name.values()
    )
    return {
        "format": FORMAT,
        "candidate": generated_map["candidate"],
        "buildTree": {
            "kind": "existing configured Node Android GYP build tree; not a clean rebuild",
            "sourceRootAtObservation": str(build_root),
            "generatedSourceMapSha256": sha256_file(generated_source_map_path),
            "staticLinkInventorySha256": generated_map["buildTree"]["staticLinkInventorySha256"],
        },
        "coverage": {
            "generatorToolCount": len(tools),
            "generatorTools": [tool["name"] for tool in tools],
            "uniqueHostObjectCount": len(object_rows),
            "hostArchiveCount": len(archive_records),
            "hostArchiveMemberCount": sum(record["memberCount"] for record in archive_records.values()),
            "allArchiveMembersMatchListedObjectBytes": all(
                record["allMemberPayloadsMatchListedObjects"] for record in archive_records.values()
            ),
            "compilerDependencyUniqueFileCount": len(file_records),
            "compilerDependencyRelationCount": sum(row["preprocessorDependencyCount"] for row in object_rows),
            "allObjectDepfilesScanned": len(object_rows) == len(unique_objects),
            "cleanGeneratorToolRebuild": "not performed",
            "buildAttestation": "not established; existing objects, make rules and executables are hashed, not rebuilt",
        },
        "buildConfigurationFiles": [
            {
                "path": path.relative_to(build_root).as_posix(),
                "sha256": sha256_file(path),
                "sizeBytes": path.stat().st_size,
            }
            for path in sorted(configuration_paths, key=lambda item: item.as_posix())
        ],
        "compilers": compiler_records,
        "generatorTools": tools,
        "hostArchives": [archive_records[key] for key in sorted(archive_records)],
        "hostObjects": sorted(object_rows, key=lambda row: row["objectPath"]),
        "compilerDependencyFiles": file_records,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-root", type=Path, required=True)
    parser.add_argument("--generated-source-map", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    try:
        result = build_map(args.build_root, args.generated_source_map, args.jobs)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    except Exception as error:  # noqa: BLE001 - CLI reports one actionable failure.
        print(f"error: {error}", file=sys.stderr)
        return 1
    coverage = result["coverage"]
    print(
        f"wrote {args.output}: {coverage['uniqueHostObjectCount']} host objects, "
        f"{coverage['compilerDependencyUniqueFileCount']} dependency files"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
