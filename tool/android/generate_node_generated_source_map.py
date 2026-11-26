#!/usr/bin/env python3
"""Map linked generated Node sources to configured GYP make actions.

This inventory reads the existing Node/Android GYP build tree. It hashes each
generated source linked into libnode, the inputs declared by its generator
action, and recursively declared generated inputs. Generator executables are
hashed as build inputs, but this does not claim their own compile/link closure
or a clean, reproducible Node rebuild.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shlex
import sys
from pathlib import Path
from typing import Any


FORMAT = "aggregate-node-generated-source-map-v1"
PHONY_INPUTS = {"FORCE_DO_CMD", "FORCE_DO_DEPENDENCIES"}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_fingerprint(path: Path) -> tuple[str, int, int]:
    """Hash a directory by sorted relative paths and content hashes."""
    rows: list[tuple[str, str, int]] = []
    total_size = 0
    for child in sorted(path.rglob("*")):
        if child.is_dir() and not child.is_symlink():
            continue
        relative = child.relative_to(path).as_posix()
        if child.is_symlink():
            target = child.readlink().as_posix()
            content_hash = sha256_bytes(("symlink\0" + target).encode())
            size = len(target.encode())
        elif child.is_file():
            content_hash = sha256_file(child)
            size = child.stat().st_size
        else:
            continue
        rows.append((relative, content_hash, size))
        total_size += size
    payload = "\n".join(f"{rel}\0{digest}\0{size}" for rel, digest, size in rows)
    return sha256_bytes(payload.encode()), total_size, len(rows)


def parse_make_continuations(text: str) -> list[str]:
    collapsed = re.sub(r"\\\r?\n[ \t]*", " ", text)
    return collapsed.splitlines()


def action_blocks(text: str) -> list[tuple[str, list[str]]]:
    """Return GYP action rule blocks from a generated target makefile."""
    lines = parse_make_continuations(text)
    starts = [index for index, line in enumerate(lines) if line.startswith("### Rules for action ")]
    blocks: list[tuple[str, list[str]]] = []
    for offset, start in enumerate(starts):
        stop = starts[offset + 1] if offset + 1 < len(starts) else len(lines)
        title_match = re.fullmatch(r'### Rules for action "(.*)":', lines[start])
        if title_match is None:
            continue
        blocks.append((title_match.group(1), lines[start:stop]))
    return blocks


def words(text: str) -> list[str]:
    try:
        return shlex.split(text, posix=True)
    except ValueError:
        return text.split()


def parse_action_definitions(makefile: Path, build_root: Path) -> list[dict[str, Any]]:
    """Parse action outputs, commands and make-declared input prerequisites."""
    text = makefile.read_text(errors="strict")
    makefile_rel = makefile.relative_to(build_root).as_posix()
    header = text.splitlines()[:8]
    target = next((line.split(":=", 1)[1].strip() for line in header if line.startswith("TARGET :=")), "")
    toolset = next((line.split(":=", 1)[1].strip() for line in header if line.startswith("TOOLSET :=")), "")
    definitions: list[dict[str, Any]] = []
    for title, block in action_blocks(text):
        for line in block:
            match = re.match(r"action_(.+)_outputs\s*:=\s*(.*)", line)
            if match is None:
                continue
            key, output_text = match.groups()
            command_match = next(
                (
                    re.match(r"cmd_" + re.escape(key) + r"\s*=\s*(.*)", candidate)
                    for candidate in block
                    if re.match(r"cmd_" + re.escape(key) + r"\s*=\s*(.*)", candidate)
                ),
                None,
            )
            if command_match is None:
                raise ValueError(f"action has outputs but no command: {makefile_rel}:{title}")
            outputs = words(output_text)
            inputs: set[str] = set()
            for candidate in block:
                if ".intermediate:" in candidate:
                    inputs.update(words(candidate.split(":", 1)[1]))
                    continue
                if ":" not in candidate or ":=" in candidate:
                    continue
                left, right = candidate.split(":", 1)
                if set(words(left)) & set(outputs):
                    inputs.update(words(right))
            inputs.difference_update(PHONY_INPUTS)
            inputs = {item for item in inputs if not item.endswith(".intermediate")}
            definitions.append(
                {
                    "makefilePath": makefile_rel,
                    "makefileSha256": sha256_file(makefile),
                    "actionName": title,
                    "key": key,
                    "target": target,
                    "toolset": toolset,
                    "outputs": outputs,
                    "commandTemplate": command_match.group(1),
                    "declaredInputTokens": sorted(inputs),
                }
            )
    return definitions


def expand_make_token(token: str, definition: dict[str, Any], build_root: Path) -> Path:
    """Expand the path variables used by this Node GYP makefile."""
    release = build_root / "out/Release"
    source = build_root
    obj = release / "obj"
    toolset = definition["toolset"]
    replacements = [
        ("$(srcdir)", str(source)),
        ("$(abs_srcdir)", str(source)),
        ("$(builddir)", str(release)),
        ("$(abs_builddir)", str(release)),
        ("$(obj).$(TOOLSET)", str(release / f"obj.{toolset}")),
        ("$(obj).target", str(release / "obj.target")),
        ("$(obj).host", str(release / "obj.host")),
        ("$(obj)", str(obj)),
        ("$(TARGET)", definition["target"]),
        ("$(TOOLSET)", toolset),
        ("$(BUILDTYPE)", "Release"),
    ]
    expanded = token
    for variable, value in replacements:
        expanded = expanded.replace(variable, value)
    if "$(" in expanded or "${" in expanded:
        raise ValueError(f"unsupported make variable in path token {token!r}: {expanded!r}")
    path = Path(expanded)
    if not path.is_absolute():
        # Generated GYP makefiles run with out/ as their working directory.
        path = build_root / "out" / path
    return path.resolve(strict=False)


def display_path(path: Path, build_root: Path) -> tuple[str, str]:
    resolved = path.resolve(strict=True)
    try:
        rel = resolved.relative_to(build_root.resolve())
        kind = "generated-build" if rel.parts and rel.parts[0] == "out" else "source-tree"
        prefix = "build" if kind == "generated-build" else "source"
        return f"{prefix}/{rel.as_posix()}", kind
    except ValueError:
        return f"external/{resolved.as_posix().lstrip('/')}", "external"


def fingerprint_path(path: Path) -> dict[str, Any]:
    if path.is_dir() and not path.is_symlink():
        digest, size, count = tree_fingerprint(path)
        return {
            "sha256": digest,
            "sizeBytes": size,
            "entryCount": count,
            "contentType": "directory-tree",
        }
    return {"sha256": sha256_file(path), "sizeBytes": path.stat().st_size, "contentType": "file"}


def make_action_id(definition: dict[str, Any], outputs: list[str]) -> str:
    identity = "\n".join(
        [
            definition["makefilePath"],
            definition["actionName"],
            definition["toolset"],
            *sorted(outputs),
            definition["commandTemplate"],
        ]
    )
    return sha256_bytes(identity.encode())[:20]


def load_generated_objects(static_inventory_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    inventory = json.loads(static_inventory_path.read_text())
    sidecar = inventory.get("archiveObjectEntriesFile", {}).get("path")
    if not isinstance(sidecar, str):
        raise ValueError("static-link inventory has no object JSONL sidecar")
    object_file = static_inventory_path.parent / sidecar
    rows = [json.loads(line) for line in object_file.read_text().splitlines() if line.strip()]
    generated = [row for row in rows if str(row.get("sourceStatus", "")).startswith("generated-output")]
    return inventory, generated


def build_map(
    build_root: Path,
    static_inventory_path: Path,
    compile_input_inventory_path: Path | None = None,
) -> dict[str, Any]:
    build_root = build_root.resolve(strict=True)
    static_inventory_path = static_inventory_path.resolve(strict=True)
    static_inventory, generated_objects = load_generated_objects(static_inventory_path)
    source_paths = sorted({source for row in generated_objects for source in row["sourcePaths"]})
    makefiles = sorted((build_root / "out").rglob("*.mk"))
    definitions = [definition for path in makefiles for definition in parse_action_definitions(path, build_root)]

    by_output: dict[Path, list[dict[str, Any]]] = {}
    for definition in definitions:
        resolved_outputs = [expand_make_token(token, definition, build_root) for token in definition["outputs"]]
        definition["resolvedOutputs"] = resolved_outputs
        definition["outputDisplays"] = [display_path(path, build_root)[0] for path in resolved_outputs]
        definition["id"] = make_action_id(definition, definition["outputDisplays"])
        for output in resolved_outputs:
            by_output.setdefault(output, []).append(definition)

    def preferred_action(candidates: list[dict[str, Any]]) -> dict[str, Any]:
        target_candidates = [item for item in candidates if item["toolset"] == "target"]
        if target_candidates:
            candidates = target_candidates
        unique = {item["id"]: item for item in candidates}
        if len(unique) != 1:
            # Identical GYP actions can be emitted once for the host and once
            # for the target while writing the same shared output. Prefer the
            # target rule above; unresolved duplicate target definitions are
            # not silently collapsed.
            raise ValueError(
                "ambiguous generator rules for output: "
                + ", ".join(item["makefilePath"] for item in unique.values())
            )
        return next(iter(unique.values()))

    source_action: dict[str, dict[str, Any]] = {}
    for source in source_paths:
        absolute = (build_root / source).resolve(strict=True)
        candidates = by_output.get(absolute, [])
        if not candidates:
            # GYP lists the V8 snapshot assembly with uppercase .S, while the
            # compiler object sidecar also names a byte-identical lowercase
            # alias. Only accept that alias when its sibling is an explicit
            # action output and the files have identical bytes.
            sibling = absolute.with_suffix(".S") if absolute.suffix == ".s" else None
            if sibling is not None and sibling in by_output:
                if sha256_file(absolute) != sha256_file(sibling):
                    raise ValueError(f"generated source alias differs from its action output: {source}")
                candidates = by_output[sibling]
        if not candidates:
            raise ValueError(f"no configured GYP action produces linked generated source: {source}")
        source_action[source] = preferred_action(candidates)

    file_records: dict[str, dict[str, Any]] = {}
    action_records: dict[str, dict[str, Any]] = {}
    declared_input_displays: set[str] = set()
    visited_actions: set[str] = set()
    unresolved_inputs: list[dict[str, str]] = []

    def add_path(path: Path, raw_token: str, producer: dict[str, Any] | None = None) -> str:
        display, kind = display_path(path, build_root)
        if display not in file_records:
            file_records[display] = {"path": display, "kind": kind, **fingerprint_path(path)}
        return display

    def include_action(definition: dict[str, Any]) -> None:
        if definition["id"] in visited_actions:
            return
        visited_actions.add(definition["id"])
        input_rows: list[dict[str, Any]] = []
        for raw in definition["declaredInputTokens"]:
            try:
                resolved = expand_make_token(raw, definition, build_root)
            except (FileNotFoundError, ValueError) as error:
                unresolved_inputs.append(
                    {"actionId": definition["id"], "token": raw, "reason": str(error)}
                )
                continue
            producers = by_output.get(resolved, [])
            if producers:
                producer = preferred_action(producers)
                include_action(producer)
                display = add_path(resolved, raw, producer)
                declared_input_displays.add(display)
                input_rows.append({"path": display, "producerActionId": producer["id"]})
            else:
                display = add_path(resolved, raw)
                declared_input_displays.add(display)
                input_rows.append({"path": display})
        action_records[definition["id"]] = {
            "id": definition["id"],
            "actionName": definition["actionName"],
            "target": definition["target"],
            "toolset": definition["toolset"],
            "makefilePath": definition["makefilePath"],
            "makefileSha256": definition["makefileSha256"],
            "commandTemplate": definition["commandTemplate"],
            "commandTemplateSha256": sha256_bytes(definition["commandTemplate"].encode()),
            "outputPaths": definition["outputDisplays"],
            "declaredInputs": input_rows,
        }

    generated_rows: list[dict[str, Any]] = []
    for row in generated_objects:
        mapped_sources = []
        for source in row["sourcePaths"]:
            action = source_action[source]
            include_action(action)
            source_file = (build_root / source).resolve(strict=True)
            source_hash = sha256_file(source_file)
            if source_hash != row["sourceSha256"]:
                raise ValueError(f"generated source hash differs from the static-link inventory: {source}")
            display, kind = display_path(source_file, build_root)
            add_path(source_file, source)
            mapped_sources.append(
                {
                    "sourcePath": display,
                    "sourceSha256": source_hash,
                    "generatorActionId": action["id"],
                    "sourceComponentId": row.get("sourceComponentId"),
                }
            )
        generated_rows.append(
            {
                "archive": row["archive"],
                "archiveOrdinal": row["archiveOrdinal"],
                "memberName": row["memberName"],
                "objectPath": row["objectPath"],
                "objectSha256": row["objectSha256"],
                "sourceStatus": row["sourceStatus"],
                "sources": mapped_sources,
            }
        )

    compile_input_sha = None
    compile_dependency_count = None
    if compile_input_inventory_path is not None:
        compile_input_inventory_path = compile_input_inventory_path.resolve(strict=True)
        compile_inputs = json.loads(compile_input_inventory_path.read_text())
        compile_input_sha = sha256_file(compile_input_inventory_path)
        compile_dependency_count = compile_inputs.get("method", {}).get("uniqueDependencyInputCount")

    object_sidecar = static_inventory_path.parent / static_inventory["archiveObjectEntriesFile"]["path"]
    configuration_paths = [build_root / "out/Makefile"] + makefiles
    configuration_records = [
        {
            "path": path.relative_to(build_root).as_posix(),
            "sha256": sha256_file(path),
            "sizeBytes": path.stat().st_size,
        }
        for path in configuration_paths
        if path.is_file()
    ]
    unique_source_count = len(source_paths)
    mapped_source_count = sum(len(row["sources"]) for row in generated_rows)
    return {
        "format": FORMAT,
        "candidate": static_inventory["candidate"],
        "buildTree": {
            "kind": "existing configured Node Android GYP build tree; not a clean rebuild",
            "sourceRootAtObservation": str(build_root),
            "staticLinkInventorySha256": sha256_file(static_inventory_path),
            "objectSidecarSha256": sha256_file(object_sidecar),
            "compileInputInventorySha256": compile_input_sha,
        },
        "coverage": {
            "generatedSourceObjectEntries": len(generated_objects),
            "distinctGeneratedSourcePaths": unique_source_count,
            "generatedSourcePathAssociations": mapped_source_count,
            "allGeneratedSourcePathsHaveConfiguredActions": mapped_source_count == sum(
                len(row["sourcePaths"]) for row in generated_objects
            ),
            "generatorActionCount": len(action_records),
            "uniqueDeclaredInputFileCount": len(declared_input_displays),
            "uniqueHashedFileCount": len(file_records),
            "declaredInputRelationCount": sum(len(action["declaredInputs"]) for action in action_records.values()),
            "unresolvedDeclaredInputCount": len(unresolved_inputs),
            "compileInputDependencyUniqueFileCount": compile_dependency_count,
            "declaredGeneratorInputsHashed": len(unresolved_inputs) == 0,
            "generatorExecutableSourceClosure": "incomplete; generator binaries are hashed when declared, but their own compile/link inputs are not recursively mapped here",
            "pythonRuntimeAndImportedModuleClosure": "incomplete; configured script files and declared data/templates are hashed, but interpreter runtime and dynamic import closure are not reconstructed",
            "buildAttestation": "not established; this is a source/action association for an existing configured build tree",
        },
        "buildConfigurationFiles": configuration_records,
        "generatedSources": generated_rows,
        "generatorActions": [action_records[key] for key in sorted(action_records)],
        "declaredInputFiles": [file_records[key] for key in sorted(file_records)],
        "unresolvedInputs": unresolved_inputs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-root", type=Path, required=True)
    parser.add_argument("--static-inventory", type=Path, required=True)
    parser.add_argument("--compile-input-inventory", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = build_map(args.build_root, args.static_inventory, args.compile_input_inventory)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    except Exception as error:  # noqa: BLE001 - CLI should return one actionable failure.
        print(f"error: {error}", file=sys.stderr)
        return 1
    coverage = result["coverage"]
    print(
        f"wrote {args.output}: {coverage['generatedSourcePathAssociations']} generated sources, "
        f"{coverage['uniqueDeclaredInputFileCount']} declared inputs, "
        f"{coverage['unresolvedDeclaredInputCount']} unresolved inputs"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
