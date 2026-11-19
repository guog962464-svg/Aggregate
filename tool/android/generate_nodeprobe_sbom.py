#!/usr/bin/env python3
"""Generate an explicitly incomplete CycloneDX inventory from a NodeProbe APK/AAB.

The archive is the source of truth for packaged native libraries, npm package
metadata, and embedded license/notice files. Packaged ELF dynamic requirements
and declared npm dependencies/peer dependencies are recorded. A Gradle runtime
manifest embedded in the archive or supplied separately records resolved Maven
artifacts and their dependency edges. An optional candidate-specific static-link inventory
can add linker archive components and direct link edges after matching the
inventory to the exact APK/AAB and packaged libnode.so. Platform library
versions and legal approval remain outside this generator; the output keeps
its composition marked incomplete.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import uuid
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import quote

LICENSE_FILE_PREFIXES = ("license", "licence", "notice", "copying", "copyright")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def elf_needed_libraries(data: bytes) -> list[str]:
    if len(data) < 16 or data[:4] != b"\x7fELF":
        raise ValueError("packaged shared library is not an ELF file")
    elf_class = data[4]
    byte_order = data[5]
    if byte_order not in (1, 2):
        raise ValueError(f"unsupported ELF byte order: {byte_order}")
    endian = "<" if byte_order == 1 else ">"
    if elf_class == 2:
        if len(data) < 64:
            raise ValueError("truncated ELF64 header")
        phoff = struct.unpack_from(endian + "Q", data, 32)[0]
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 54)
        ph_format = endian + "IIQQQQQQ"
        dynamic_format = endian + "qQ"
        minimum_phentsize = struct.calcsize(ph_format)
    elif elf_class == 1:
        if len(data) < 52:
            raise ValueError("truncated ELF32 header")
        phoff = struct.unpack_from(endian + "I", data, 28)[0]
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 42)
        ph_format = endian + "IIIIIIII"
        dynamic_format = endian + "iI"
        minimum_phentsize = struct.calcsize(ph_format)
    else:
        raise ValueError(f"unsupported ELF class: {elf_class}")
    if phentsize < minimum_phentsize or phoff + phentsize * phnum > len(data):
        raise ValueError("invalid ELF program header table")

    load_segments: list[tuple[int, int, int]] = []
    dynamic_segment: tuple[int, int] | None = None
    for index in range(phnum):
        entry = struct.unpack_from(ph_format, data, phoff + index * phentsize)
        if elf_class == 2:
            segment_type, _, offset, virtual_address, _, file_size, _, _ = entry
        else:
            segment_type, offset, virtual_address, _, file_size, _, _, _ = entry
        if segment_type == 1:
            load_segments.append((virtual_address, offset, file_size))
        elif segment_type == 2:
            dynamic_segment = (offset, file_size)
    if dynamic_segment is None:
        return []

    dynamic_offset, dynamic_size = dynamic_segment
    dynamic_entry_size = struct.calcsize(dynamic_format)
    if dynamic_offset + dynamic_size > len(data) or dynamic_size % dynamic_entry_size:
        raise ValueError("invalid ELF dynamic segment")
    needed_offsets: list[int] = []
    string_table_address: int | None = None
    string_table_size: int | None = None
    for offset in range(dynamic_offset, dynamic_offset + dynamic_size, dynamic_entry_size):
        tag, value = struct.unpack_from(dynamic_format, data, offset)
        if tag == 0:
            break
        if tag == 1:
            needed_offsets.append(value)
        elif tag == 5:
            string_table_address = value
        elif tag == 10:
            string_table_size = value
    if not needed_offsets:
        return []
    if string_table_address is None or string_table_size is None:
        raise ValueError("ELF DT_NEEDED entries have no complete string table metadata")

    string_table_offset: int | None = None
    for virtual_address, file_offset, file_size in load_segments:
        if virtual_address <= string_table_address < virtual_address + file_size:
            string_table_offset = file_offset + string_table_address - virtual_address
            break
    if string_table_offset is None or string_table_offset + string_table_size > len(data):
        raise ValueError("ELF dynamic string table is outside file-backed PT_LOAD data")
    string_table = data[string_table_offset : string_table_offset + string_table_size]
    needed: list[str] = []
    for name_offset in needed_offsets:
        if name_offset >= len(string_table):
            raise ValueError("ELF DT_NEEDED name offset exceeds its string table")
        terminator = string_table.find(b"\0", name_offset)
        if terminator < 0:
            raise ValueError("unterminated ELF DT_NEEDED library name")
        needed.append(string_table[name_offset:terminator].decode("utf-8"))
    return needed


def ref_for_path(path: str) -> str:
    return f"urn:aggregate:archive-entry:{sha256(path.encode('utf-8'))}"


def property_item(name: str, value: object) -> dict[str, str]:
    return {"name": name, "value": str(value)}


def file_component(path: str, data: bytes, category: str) -> dict[str, object]:
    return {
        "type": "file",
        "bom-ref": ref_for_path(path),
        "name": PurePosixPath(path).name,
        "hashes": [{"alg": "SHA-256", "content": sha256(data)}],
        "properties": [
            property_item("aggregate:archive-path", path),
            property_item("aggregate:inventory-category", category),
        ],
    }


def npm_license_entry(value: object) -> dict[str, object] | None:
    if isinstance(value, str) and value.strip():
        text = value.strip()
        if any(operator in text for operator in (" AND ", " OR ", " WITH ")):
            return {"expression": text}
        if all(char.isalnum() or char in ".-+" for char in text):
            return {"license": {"id": text}}
        return {"license": {"name": text}}
    if isinstance(value, dict):
        license_type = value.get("type")
        if not isinstance(license_type, str) or not license_type.strip():
            license_type = value.get("name")
        if isinstance(license_type, str) and license_type.strip():
            license_data: dict[str, str] = {"name": license_type.strip()}
            license_url = value.get("url")
            if isinstance(license_url, str) and license_url.strip():
                license_data["url"] = license_url.strip()
            return {"license": license_data}
    return None


def package_component(
    path: str,
    package: dict[str, object],
    data: bytes,
    license_paths: list[str],
) -> dict[str, object] | None:
    name = package.get("name")
    version = package.get("version")
    if not isinstance(name, str) or not isinstance(version, str):
        return None

    encoded_name = quote(name, safe="/")
    encoded_version = quote(version, safe=".+-")
    component: dict[str, object] = {
        "type": "library",
        "bom-ref": ref_for_path(path),
        "name": name,
        "version": version,
        "purl": f"pkg:npm/{encoded_name}@{encoded_version}",
        "properties": [
            property_item("aggregate:archive-package-json-path", path),
            property_item("aggregate:package-json-sha256", sha256(data)),
        ],
    }

    license_value = package.get("license")
    license_source = "license"
    if license_value is None and "licenses" in package:
        license_value = package.get("licenses")
        license_source = "licenses"
    if license_value is None:
        component["properties"].append(property_item("aggregate:license-metadata", "missing"))
    else:
        values = license_value if isinstance(license_value, list) else [license_value]
        license_entries = [
            entry for value in values if (entry := npm_license_entry(value)) is not None
        ]
        if license_entries:
            component["licenses"] = license_entries
            if license_source == "licenses":
                component["properties"].append(
                    property_item("aggregate:license-metadata-source", "licenses")
                )
        else:
            component["properties"].append(
                property_item("aggregate:license-metadata", json.dumps(license_value, sort_keys=True))
            )

    if license_paths:
        for license_path in sorted(license_paths):
            component["properties"].append(property_item("aggregate:license-file-path", license_path))
    else:
        component["properties"].append(property_item("aggregate:license-file", "not found beside package.json"))
    return component


def gradle_component_ref(group: str, name: str, version: str) -> str:
    namespace = quote(group, safe=".-")
    artifact = quote(name, safe=".-")
    artifact_version = quote(version, safe=".+-")
    return f"pkg:maven/{namespace}/{artifact}@{artifact_version}"


def gradle_runtime_components(
    manifest: dict[str, object], archive_names: list[str], archive: zipfile.ZipFile
) -> tuple[list[dict[str, object]], dict[str, str]]:
    if not isinstance(manifest, dict):
        raise ValueError("NodeProbe Gradle runtime manifest must be a JSON object")
    if manifest.get("format") != "aggregate-nodeprobe-gradle-runtime-v1":
        raise ValueError("unsupported NodeProbe Gradle runtime manifest format")
    configuration = manifest.get("configuration")
    if not isinstance(configuration, str) or not configuration:
        raise ValueError("Gradle runtime manifest has no configuration name")
    raw_components = manifest.get("components")
    if not isinstance(raw_components, list):
        raise ValueError("Gradle runtime manifest components must be a list")

    components: list[dict[str, object]] = []
    refs_by_coordinate: dict[str, str] = {}
    for raw in raw_components:
        if not isinstance(raw, dict):
            raise ValueError("Gradle runtime component must be an object")
        group = raw.get("group")
        name = raw.get("name")
        version = raw.get("version")
        coordinate = raw.get("coordinate")
        artifact_sha256 = raw.get("artifact_sha256")
        license_id = raw.get("license_id")
        license_asset_path = raw.get("license_asset_path")
        license_asset_sha256 = raw.get("license_asset_sha256")
        verified_dex_packages = raw.get("verified_dex_packages")
        if not all(isinstance(value, str) and value for value in (group, name, version)):
            raise ValueError("Gradle runtime component is missing Maven coordinates")
        expected_coordinate = f"{group}:{name}:{version}"
        if coordinate != expected_coordinate:
            raise ValueError(f"Gradle runtime coordinate does not match fields: {coordinate}")
        if coordinate in refs_by_coordinate:
            raise ValueError(f"duplicate Gradle runtime component: {coordinate}")
        if (
            not isinstance(artifact_sha256, str)
            or len(artifact_sha256) != 64
            or any(char not in "0123456789abcdef" for char in artifact_sha256.lower())
        ):
            raise ValueError(f"invalid source artifact SHA-256 for {coordinate}")
        if not isinstance(license_id, str) or not license_id:
            raise ValueError(f"missing license id for {coordinate}")
        if not isinstance(license_asset_path, str) or not isinstance(license_asset_sha256, str):
            raise ValueError(f"missing bundled license asset metadata for {coordinate}")
        license_path = PurePosixPath(license_asset_path.removeprefix("assets/"))
        if license_path.is_absolute() or ".." in license_path.parts:
            raise ValueError(f"unsafe license asset path for {coordinate}")
        if len(license_asset_sha256) != 64 or any(
            char not in "0123456789abcdef" for char in license_asset_sha256.lower()
        ):
            raise ValueError(f"invalid license asset SHA-256 for {coordinate}")
        if not isinstance(verified_dex_packages, list) or not all(
            isinstance(package, str) for package in verified_dex_packages
        ):
            raise ValueError(f"invalid DEX package evidence for {coordinate}")

        normalized_license_path = license_path.as_posix()
        matching_paths = [
            path
            for path in archive_names
            if path.endswith("/assets/" + normalized_license_path)
            or path == "assets/" + normalized_license_path
        ]
        if len(matching_paths) != 1:
            raise ValueError(
                f"expected one bundled license file for {coordinate}, found {len(matching_paths)}"
            )
        packaged_license_path = matching_paths[0]
        if sha256(archive.read(packaged_license_path)) != license_asset_sha256:
            raise ValueError(f"bundled license hash does not match manifest for {coordinate}")

        purl = gradle_component_ref(group, name, version)
        refs_by_coordinate[coordinate] = purl
        components.append(
            {
                "type": "library",
                "bom-ref": purl,
                "name": name,
                "group": group,
                "version": version,
                "purl": purl,
                "hashes": [{"alg": "SHA-256", "content": artifact_sha256}],
                "licenses": [{"license": {"id": license_id}}],
                "properties": [
                    property_item("aggregate:gradle-configuration", configuration),
                    property_item("aggregate:maven-coordinate", coordinate),
                    property_item("aggregate:source-artifact-sha256", artifact_sha256),
                    property_item(
                        "aggregate:artifact-representation",
                        "resolved source JAR; runtime classes merged into Android DEX",
                    ),
                    property_item(
                        "aggregate:verified-dex-packages",
                        json.dumps(sorted(verified_dex_packages)),
                    ),
                    property_item("aggregate:license-file-path", packaged_license_path),
                ],
            }
        )
    return components, refs_by_coordinate


def resolve_npm_dependency(
    package_dir: str,
    npm_root: str,
    dependency_name: str,
    package_refs: dict[str, dict[str, object]],
) -> str | None:
    current = PurePosixPath(package_dir)
    root = PurePosixPath(npm_root)
    while current == root or root in current.parents:
        candidate = (current / "node_modules" / dependency_name).as_posix()
        if candidate in package_refs:
            return candidate
        if current == root:
            break
        current = current.parent
    return None


def load_static_link_inventory(path: Path) -> dict[str, object]:
    inventory = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(inventory, dict):
        raise ValueError("static-link inventory must be a JSON object")
    if inventory.get("format") != "aggregate-node-static-link-inventory-v1":
        raise ValueError("unsupported static-link inventory format")
    candidate = inventory.get("candidate")
    link_map = inventory.get("linkMap")
    if not isinstance(candidate, dict) or not isinstance(link_map, dict):
        raise ValueError("static-link inventory is missing candidate or linkMap data")
    if not isinstance(inventory.get("sourceComponents"), list):
        raise ValueError("static-link inventory sourceComponents must be a list")
    if not isinstance(candidate.get("releaseArtifacts"), dict):
        raise ValueError("static-link inventory is missing releaseArtifacts")
    if not isinstance(link_map.get("explicitArchiveInputs"), list):
        raise ValueError("static-link inventory explicitArchiveInputs must be a list")
    if not isinstance(link_map.get("implicitNdkToolchainArchives"), list):
        raise ValueError("static-link inventory implicitNdkToolchainArchives must be a list")
    return inventory


def validate_inventory_digest(value: object, field: str) -> str:
    if (not isinstance(value, str) or len(value) != 64 or
            any(char not in "0123456789abcdefABCDEF" for char in value)):
        raise ValueError(f"{field} must be a SHA-256 hex digest")
    return value.lower()


def static_link_components(
    inventory: dict[str, object],
) -> tuple[list[dict[str, object]], list[dict[str, object]], list[str], dict[str, int]]:
    source_rows = inventory["sourceComponents"]
    link_map = inventory["linkMap"]
    assert isinstance(source_rows, list)
    assert isinstance(link_map, dict)

    components: list[dict[str, object]] = []
    source_refs: dict[str, str] = {}
    source_by_id: dict[str, dict[str, object]] = {}
    for raw in source_rows:
        if not isinstance(raw, dict):
            raise ValueError("static-link source component must be an object")
        component_id = raw.get("id")
        name = raw.get("name")
        version = raw.get("version")
        if not isinstance(component_id, str) or not component_id:
            raise ValueError("static-link source component requires an id")
        if component_id in source_refs:
            raise ValueError(f"duplicate static-link source component id: {component_id}")
        if not isinstance(name, str) or not name or not isinstance(version, str) or not version:
            raise ValueError(f"static-link source component {component_id} needs name and version")
        tree_id = raw.get("sourceGitTreeObjectId")
        if tree_id is not None and not isinstance(tree_id, str):
            raise ValueError(f"invalid source Git tree object ID for {component_id}")
        ref_suffix = tree_id or f"version-{sha256(version.encode('utf-8'))[:16]}"
        source_ref = f"urn:aggregate:node-static-source:{component_id}:{ref_suffix}"
        source_refs[component_id] = source_ref
        source_by_id[component_id] = raw
        properties = [
            property_item("aggregate:static-link-source-component-id", component_id),
            property_item("aggregate:source-version-evidence", json.dumps(raw.get("versionEvidence", []), sort_keys=True)),
            property_item("aggregate:source-license-evidence", json.dumps(raw.get("licenseEvidence", []), sort_keys=True)),
        ]
        source_root = raw.get("sourceRoot")
        if isinstance(source_root, str):
            properties.append(property_item("aggregate:source-root", source_root))
        if tree_id:
            properties.append(property_item("aggregate:source-git-tree-object-id", tree_id))
        notes = raw.get("notes")
        if isinstance(notes, list):
            properties.extend(
                property_item("aggregate:source-review-note", note)
                for note in notes
                if isinstance(note, str)
            )
        components.append(
            {
                "type": "library",
                "bom-ref": source_ref,
                "name": name,
                "version": version,
                "properties": properties,
            }
        )

    explicit_archives = link_map["explicitArchiveInputs"]
    implicit_archives = link_map["implicitNdkToolchainArchives"]
    assert isinstance(explicit_archives, list)
    assert isinstance(implicit_archives, list)
    zero_retained_names_raw = link_map.get("archivesWithNoRetainedSections", [])
    zero_retained_names = (
        {name for name in zero_retained_names_raw if isinstance(name, str)}
        if isinstance(zero_retained_names_raw, list)
        else set()
    )
    archive_names: set[str] = set()
    archive_dependency_nodes: list[dict[str, object]] = []
    retained_archive_refs: list[str] = []
    retained_archive_count = 0
    explicit_member_count = 0

    for raw in explicit_archives:
        if not isinstance(raw, dict):
            raise ValueError("static-link archive input must be an object")
        name = raw.get("name")
        component_id = raw.get("sourceComponentId")
        if not isinstance(name, str) or not name.endswith(".a") or name in archive_names:
            raise ValueError(f"invalid or duplicate static-link archive input: {name!r}")
        archive_names.add(name)
        if not isinstance(component_id, str) or component_id not in source_refs:
            raise ValueError(f"static-link archive {name} references an unknown source component")
        digest = validate_inventory_digest(raw.get("sha256"), f"{name} sha256")
        member_count = raw.get("archiveMemberCount")
        retained_members = raw.get("membersWithRetainedSections")
        if (not isinstance(member_count, int) or member_count < 0 or
                not isinstance(retained_members, int) or retained_members < 0 or
                retained_members > member_count):
            raise ValueError(f"invalid member counts for static-link archive {name}")
        explicit_member_count += member_count
        source_row = source_by_id[component_id]
        source_tree = source_row.get("sourceGitTreeObjectId")
        archive_ref = f"urn:aggregate:node-static-archive:{name}:sha256:{digest}"
        properties = [
            property_item("aggregate:component-role", "static-link build archive; object code may be compiled into libnode.so"),
            property_item("aggregate:source-component-id", component_id),
            property_item("aggregate:source-component-ref", source_refs[component_id]),
            property_item("aggregate:archive-member-count", member_count),
            property_item("aggregate:members-with-retained-sections", retained_members),
            property_item("aggregate:archive-make-input", raw.get("makeInput", "")),
        ]
        if isinstance(source_tree, str):
            properties.append(property_item("aggregate:source-git-tree-object-id", source_tree))
        components.append(
            {
                "type": "library",
                "bom-ref": archive_ref,
                "name": name,
                "version": str(source_row["version"]),
                "hashes": [{"alg": "SHA-256", "content": digest}],
                "properties": properties,
            }
        )
        archive_dependency_nodes.append({"ref": archive_ref, "dependsOn": []})
        if retained_members > 0:
            retained_archive_count += 1
            retained_archive_refs.append(archive_ref)
        elif name not in zero_retained_names:
            raise ValueError(f"zero-retained archive {name} is missing from inventory summary")

    if link_map.get("explicitStaticArchiveCount") != len(explicit_archives):
        raise ValueError("explicit static archive count does not match its entries")
    if link_map.get("explicitArchiveMemberCount") != explicit_member_count:
        raise ValueError("explicit archive member count does not match its entries")
    if link_map.get("archivesWithRetainedSections") != retained_archive_count:
        raise ValueError("retained archive count does not match its entries")
    if not isinstance(link_map.get("retainedArchiveObjectPairs"), int):
        raise ValueError("static-link inventory is missing retained archive object-pair count")
    actual_zero_names = {
        raw["name"] for raw in explicit_archives
        if isinstance(raw, dict) and raw.get("membersWithRetainedSections") == 0
    }
    if zero_retained_names != actual_zero_names:
        raise ValueError("zero-retained archive names do not match their entries")

    for raw in implicit_archives:
        if not isinstance(raw, dict):
            raise ValueError("implicit NDK archive must be an object")
        name = raw.get("name")
        component_id = raw.get("sourceComponentId")
        if not isinstance(name, str) or not name.endswith(".a"):
            raise ValueError("implicit NDK archive requires a .a name")
        if name in archive_names:
            raise ValueError(f"duplicate static-link archive input: {name}")
        archive_names.add(name)
        if not isinstance(component_id, str) or component_id not in source_refs:
            raise ValueError(f"implicit NDK archive {name} references an unknown source component")
        digest = validate_inventory_digest(raw.get("sha256"), f"{name} sha256")
        retained_members = raw.get("members_with_retained_sections_in_link_map")
        if not isinstance(retained_members, int) or retained_members <= 0:
            raise ValueError(f"implicit NDK archive {name} has no retained member evidence")
        source_row = source_by_id[component_id]
        source_tree = source_row.get("sourceGitTreeObjectId")
        archive_ref = f"urn:aggregate:node-static-archive:{name}:sha256:{digest}"
        properties = [
            property_item("aggregate:component-role", "implicit NDK static runtime archive linked into libnode.so"),
            property_item("aggregate:source-component-id", component_id),
            property_item("aggregate:source-component-ref", source_refs[component_id]),
            property_item("aggregate:members-with-retained-sections", retained_members),
            property_item("aggregate:ndk-relative-path", raw.get("ndkRelativePath", "")),
        ]
        if isinstance(source_tree, str):
            properties.append(property_item("aggregate:source-git-tree-object-id", source_tree))
        components.append(
            {
                "type": "library",
                "bom-ref": archive_ref,
                "name": name,
                "version": str(source_row["version"]),
                "hashes": [{"alg": "SHA-256", "content": digest}],
                "properties": properties,
            }
        )
        archive_dependency_nodes.append({"ref": archive_ref, "dependsOn": []})
        retained_archive_refs.append(archive_ref)

    return components, archive_dependency_nodes, retained_archive_refs, {
        "sourceComponents": len(source_rows),
        "explicitArchives": len(explicit_archives),
        "explicitArchiveMembers": explicit_member_count,
        "explicitRetainedArchives": retained_archive_count,
        "retainedArchiveObjectPairs": link_map["retainedArchiveObjectPairs"],
        "zeroRetainedArchives": len(zero_retained_names),
        "implicitNdkArchives": len(implicit_archives),
        "retainedArchiveEdges": len(retained_archive_refs),
    }


def archive_member_by_suffix(names: list[str], suffix: str) -> str:
    matches = [name for name in names if name == suffix or name.endswith("/" + suffix)]
    if len(matches) != 1:
        raise ValueError(
            f"expected one packaged archive entry ending in {suffix!r}; found {len(matches)}"
        )
    return matches[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="NodeProbe APK or AAB to inventory")
    parser.add_argument("output", type=Path, help="CycloneDX JSON output path")
    parser.add_argument("--artifact-version", required=True, help="Human-readable candidate label")
    parser.add_argument("--node-version", default="unknown")
    parser.add_argument("--node-mobile-version", default="unknown")
    parser.add_argument("--ndk-version", default="unknown")
    parser.add_argument(
        "--source-git-tree",
        "--source-tree-sha256",
        dest="source_git_tree",
        default="unknown",
        help=(
            "Git tree object ID (SHA-1) for the exact Node source tree; "
            "the old option name is kept as an alias"
        ),
    )
    parser.add_argument("--upstream-commit", default="unknown")
    parser.add_argument("--recipe-commit", default="unknown")
    parser.add_argument(
        "--static-link-inventory",
        type=Path,
        help="candidate-specific JSON with Node source and linker archive evidence",
    )
    parser.add_argument(
        "--gradle-runtime-manifest",
        type=Path,
        help=(
            "resolved Gradle runtime manifest JSON; use this when the archive "
            "does not embed one"
        ),
    )
    args = parser.parse_args()

    archive_hash = sha256_file(args.archive)
    artifact_kind = args.archive.suffix.lower().lstrip(".")
    if artifact_kind not in {"apk", "aab"}:
        parser.error("archive must be an APK or AAB")

    static_inventory: dict[str, object] | None = None
    static_components: list[dict[str, object]] = []
    static_archive_dependency_nodes: list[dict[str, object]] = []
    static_archive_refs: list[str] = []
    static_inventory_stats: dict[str, int] = {}
    if args.static_link_inventory is not None:
        static_inventory = load_static_link_inventory(args.static_link_inventory)
        candidate = static_inventory["candidate"]
        assert isinstance(candidate, dict)
        release_artifacts = candidate["releaseArtifacts"]
        assert isinstance(release_artifacts, dict)
        artifact_record = release_artifacts.get(artifact_kind)
        if not isinstance(artifact_record, dict):
            parser.error(f"static-link inventory has no {artifact_kind.upper()} artifact record")
        if artifact_record.get("sha256") != archive_hash:
            parser.error("archive SHA-256 does not match the static-link inventory candidate")
        if artifact_record.get("sizeBytes") != args.archive.stat().st_size:
            parser.error("archive size does not match the static-link inventory candidate")

        inventory_values = {
            "node_version": candidate.get("nodeVersion"),
            "node_mobile_version": candidate.get("nodeMobileVersion"),
            "ndk_version": candidate.get("ndkRevision"),
            "source_git_tree": candidate.get("nodeSourceGitTreeObjectId"),
            "upstream_commit": candidate.get("upstreamNodeCommit"),
            "recipe_commit": candidate.get("mobileRecipeCommit"),
        }
        for argument_name, inventory_value in inventory_values.items():
            if not isinstance(inventory_value, str) or not inventory_value:
                parser.error(f"static-link inventory has no candidate value for {argument_name}")
            supplied_value = getattr(args, argument_name)
            if supplied_value != "unknown" and supplied_value != inventory_value:
                parser.error(f"--{argument_name.replace('_', '-')} does not match the static-link inventory")
            setattr(args, argument_name, inventory_value)

        static_components, static_archive_dependency_nodes, static_archive_refs, static_inventory_stats = (
            static_link_components(static_inventory)
        )

    components: list[dict[str, object]] = []
    package_components: dict[str, dict[str, object]] = {}
    package_metadata: dict[str, dict[str, object]] = {}
    native_library_refs: dict[str, str] = {}
    native_needed_libraries: dict[str, list[str]] = {}
    static_node_ref: str | None = None
    npm_root: str | None = None
    gradle_runtime_manifest: dict[str, object] | None = None
    gradle_runtime_manifest_bytes: bytes | None = None
    gradle_runtime_manifest_source: str | None = None
    gradle_runtime_refs: dict[str, str] = {}
    with zipfile.ZipFile(args.archive) as archive:
        names = archive.namelist()
        lib_prefixes = ("lib/", "base/lib/")
        gradle_manifest_paths = [
            path
            for path in names
            if PurePosixPath(path).name == "nodejs-mobile-gradle-runtime-manifest.json"
        ]
        if len(gradle_manifest_paths) > 1:
            raise ValueError("archive contains multiple NodeProbe Gradle runtime manifests")
        if gradle_manifest_paths and args.gradle_runtime_manifest is not None:
            parser.error(
                "--gradle-runtime-manifest cannot be combined with a manifest embedded in the archive"
            )
        if gradle_manifest_paths:
            gradle_runtime_manifest_bytes = archive.read(gradle_manifest_paths[0])
            gradle_runtime_manifest = json.loads(gradle_runtime_manifest_bytes)
            gradle_runtime_manifest_source = "archive"
        elif args.gradle_runtime_manifest is not None:
            gradle_runtime_manifest_bytes = args.gradle_runtime_manifest.read_bytes()
            gradle_runtime_manifest = json.loads(gradle_runtime_manifest_bytes)
            gradle_runtime_manifest_source = "external"
        if gradle_runtime_manifest is not None:
            if not isinstance(gradle_runtime_manifest, dict):
                raise ValueError("NodeProbe Gradle runtime manifest must be a JSON object")
            gradle_components, gradle_runtime_refs = gradle_runtime_components(
                gradle_runtime_manifest, names, archive
            )
            components.extend(gradle_components)

        if static_inventory is not None:
            candidate = static_inventory["candidate"]
            assert isinstance(candidate, dict)
            abi = candidate.get("abi")
            if not isinstance(abi, str) or not abi:
                raise ValueError("static-link inventory candidate ABI is missing")
            packaged_node_paths = [
                path for path in names if PurePosixPath(path).name == "libnode.so"
            ]
            if len(packaged_node_paths) != 1:
                raise ValueError(
                    f"expected one packaged libnode.so for candidate; found {len(packaged_node_paths)}"
                )
            node_path = archive_member_by_suffix(names, f"{abi}/libnode.so")
            if packaged_node_paths[0] != node_path:
                raise ValueError("packaged libnode.so ABI does not match the static-link inventory")
            node_hash = sha256(archive.read(node_path))
            if node_hash != candidate.get("libnodePackagedStrippedSha256"):
                raise ValueError("packaged libnode.so SHA-256 does not match the static-link inventory")

            manifest_hash = validate_inventory_digest(
                candidate.get("licenseManifestSha256"), "license manifest sha256"
            )
            manifest_path = archive_member_by_suffix(
                names, "nodejs-mobile-static-licenses/native-licenses-manifest.json"
            )
            if sha256(archive.read(manifest_path)) != manifest_hash:
                raise ValueError("packaged static license manifest hash does not match the inventory")

            for source_row in static_inventory["sourceComponents"]:
                if not isinstance(source_row, dict):
                    raise ValueError("static-link source component must be an object")
                for evidence in source_row.get("licenseEvidence", []):
                    if not isinstance(evidence, dict) or not isinstance(evidence.get("packagedAsset"), str):
                        continue
                    packaged_asset = evidence["packagedAsset"]
                    packaged_path = archive_member_by_suffix(names, packaged_asset)
                    if sha256(archive.read(packaged_path)) != evidence.get("sha256"):
                        raise ValueError(f"packaged static license asset hash mismatch: {packaged_path}")
                    continue
                if evidence.get("path") == "LICENSE" and evidence.get("status") == "source-project license file":
                    expected_source_license = validate_inventory_digest(
                        evidence.get("sha256"), "Node source license sha256"
                    )
                    matching_source_licenses = [
                        path for path in names
                        if PurePosixPath(path).name == "nodejs-mobile-LICENSE.txt"
                        and sha256(archive.read(path)) == expected_source_license
                    ]
                    if len(matching_source_licenses) != 1:
                        raise ValueError("packaged Node source license does not match the inventory")
            for notice in static_inventory.get("embeddedNdkNotices", []):
                if not isinstance(notice, dict) or not isinstance(notice.get("path"), str):
                    continue
                notice_path = notice["path"]
                if not notice_path.startswith("assets/"):
                    continue
                packaged_path = archive_member_by_suffix(names, notice_path)
                if sha256(archive.read(packaged_path)) != notice.get("sha256"):
                    raise ValueError(f"packaged NDK notice hash mismatch: {packaged_path}")

        for path in sorted(names):
            if path.endswith("/"):
                continue
            data = archive.read(path)
            basename = PurePosixPath(path).name

            if basename.lower().startswith(("license", "licence", "notice", "copying", "copyright")):
                components.append(file_component(path, data, "license-or-notice"))

            if path.endswith(".so") and path.startswith(lib_prefixes):
                name = basename
                needed_libraries = elf_needed_libraries(data)
                native_ref = ref_for_path(path)
                native_library_refs[path] = native_ref
                native_needed_libraries[path] = needed_libraries
                component: dict[str, object] = {
                    "type": "library",
                    "bom-ref": native_ref,
                    "name": name,
                    "hashes": [{"alg": "SHA-256", "content": sha256(data)}],
                    "properties": [
                        property_item("aggregate:archive-path", path),
                        *[
                            property_item("aggregate:needed-library", needed)
                            for needed in needed_libraries
                        ],
                    ],
                }
                if name == "libnode.so":
                    component["name"] = "Node.js mobile runtime"
                    component["version"] = args.node_version
                    component["purl"] = f"pkg:generic/nodejs-mobile@{quote(args.node_version, safe='.+-')}"
                    component["properties"].append(property_item("aggregate:node-mobile-version", args.node_mobile_version))
                elif name == "libc++_shared.so":
                    component["name"] = "Android NDK libc++ shared runtime"
                    component["version"] = args.ndk_version
                    component["purl"] = f"pkg:generic/android-ndk-libcxx@{quote(args.ndk_version, safe='.+-')}"
                elif name == "libaggregate_node_probe.so":
                    component["name"] = "Aggregate NodeProbe JNI bridge"
                components.append(component)

            if path.endswith(".node") or path.endswith(".tgz"):
                components.append(file_component(path, data, "packaged-test-fixture"))

            path_parts = path.split("/")
            is_package_manifest = path.endswith("/package.json") and (
                "node_modules" in path_parts
                or path.endswith(("/a4-npm-cli/package.json", "/a4-json5/package.json"))
            )
            if is_package_manifest:
                try:
                    package = json.loads(data)
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
                package_dir = path.rsplit("/", 1)[0]
                direct_license_paths = [
                    candidate
                    for candidate in names
                    if candidate.startswith(package_dir + "/")
                    and "/" not in candidate[len(package_dir) + 1 :]
                    and PurePosixPath(candidate).name.lower().startswith(LICENSE_FILE_PREFIXES)
                ]
                component = package_component(path, package, data, direct_license_paths)
                if component is not None:
                    components.append(component)
                    package_components[package_dir] = component
                    package_metadata[package_dir] = package
                    if path.endswith("/a4-npm-cli/package.json"):
                        npm_root = package_dir

            if path.endswith(("-manifest.json", "-package-lock.json")) or basename == "a4-ncm-package.json":
                components.append(file_component(path, data, "packaged-manifest-or-lock"))

    if static_inventory is not None:
        candidate = static_inventory["candidate"]
        assert isinstance(candidate, dict)
        abi = candidate["abi"]
        node_paths = [
            path for path in native_library_refs
            if path.endswith(f"/{abi}/libnode.so")
        ]
        if len(node_paths) != 1:
            raise ValueError(f"expected one packaged libnode.so for {abi}; found {len(node_paths)}")
        static_node_ref = native_library_refs[node_paths[0]]
        components.extend(static_components)

    npm_dependencies: list[dict[str, object]] = []
    resolved_npm_edges = 0
    unresolved_npm_edges: list[tuple[str, str, object]] = []
    optional_peer_dependencies_not_packaged: list[tuple[str, str, object]] = []
    if npm_root is not None:
        for package_dir in sorted(package_components):
            if package_dir != npm_root and not package_dir.startswith(npm_root + "/node_modules/"):
                continue
            manifest = package_metadata[package_dir]
            declared: dict[str, object] = {}
            for field in ("dependencies", "optionalDependencies"):
                values = manifest.get(field)
                if isinstance(values, dict):
                    declared.update(values)
            regular_dependency_names = set(declared)
            peer_dependencies = manifest.get("peerDependencies")
            peer_dependency_names = set(peer_dependencies) if isinstance(peer_dependencies, dict) else set()
            if isinstance(peer_dependencies, dict):
                declared.update(peer_dependencies)
            peer_metadata = manifest.get("peerDependenciesMeta")
            targets: set[str] = set()
            for dependency_name, version_range in sorted(declared.items()):
                target = resolve_npm_dependency(
                    package_dir, npm_root, dependency_name, package_components
                )
                if target is None:
                    peer_details = peer_metadata.get(dependency_name) if isinstance(peer_metadata, dict) else None
                    is_optional_peer = (
                        dependency_name in peer_dependency_names
                        and dependency_name not in regular_dependency_names
                        and isinstance(peer_details, dict)
                        and peer_details.get("optional") is True
                    )
                    if is_optional_peer:
                        optional_peer_dependencies_not_packaged.append(
                            (package_dir, dependency_name, version_range)
                        )
                        continue
                    unresolved_npm_edges.append((package_dir, dependency_name, version_range))
                    continue
                targets.add(str(package_components[target]["bom-ref"]))
                resolved_npm_edges += 1
            npm_dependencies.append(
                {
                    "ref": package_components[package_dir]["bom-ref"],
                    "dependsOn": sorted(targets),
                }
            )

    native_dependencies: list[dict[str, object]] = []
    native_packaged_edges = 0
    native_unbundled_edges: list[tuple[str, str]] = []
    for path, needed_libraries in sorted(native_needed_libraries.items()):
        abi_directory = path.rsplit("/", 1)[0]
        targets: set[str] = set()
        for needed in needed_libraries:
            target_path = f"{abi_directory}/{needed}"
            target_ref = native_library_refs.get(target_path)
            if target_ref is None:
                native_unbundled_edges.append((path, needed))
                continue
            targets.add(target_ref)
            native_packaged_edges += 1
        native_dependencies.append(
            {
                "ref": native_library_refs[path],
                "dependsOn": sorted(targets),
            }
        )

    if static_inventory is not None:
        assert static_node_ref is not None
        for dependency in native_dependencies:
            if dependency["ref"] == static_node_ref:
                dependency["dependsOn"] = sorted(
                    set(dependency["dependsOn"]) | set(static_archive_refs)
                )
                break
        else:
            raise ValueError("packaged libnode.so has no native dependency node")
        native_dependencies.extend(static_archive_dependency_nodes)

    # The exact archive digest gives every archive-level component a stable anchor.
    artifact_ref = f"urn:aggregate:nodeprobe-{artifact_kind}:{archive_hash}"
    gradle_dependency_map: dict[str, set[str]] = {
        ref: set() for ref in gradle_runtime_refs.values()
    }
    if gradle_runtime_manifest is not None:
        raw_dependencies = gradle_runtime_manifest.get("dependencies")
        if not isinstance(raw_dependencies, list):
            raise ValueError("Gradle runtime manifest dependencies must be a list")
        for raw_dependency in raw_dependencies:
            if not isinstance(raw_dependency, dict):
                raise ValueError("Gradle runtime dependency must be an object")
            source = raw_dependency.get("from")
            target = raw_dependency.get("to")
            if not isinstance(source, str) or not isinstance(target, str):
                raise ValueError("Gradle runtime dependency requires from/to coordinates")
            source_ref = artifact_ref if source == "application" else gradle_runtime_refs.get(source)
            target_ref = gradle_runtime_refs.get(target)
            if source_ref is None or target_ref is None:
                raise ValueError(f"Gradle runtime dependency references an unknown component: {raw_dependency}")
            gradle_dependency_map.setdefault(source_ref, set()).add(target_ref)
    gradle_dependencies = [
        {"ref": ref, "dependsOn": sorted(targets)}
        for ref, targets in sorted(gradle_dependency_map.items())
    ]

    gradle_configuration = (
        gradle_runtime_manifest.get("configuration", "")
        if gradle_runtime_manifest is not None
        else ""
    )
    gradle_edge_count = sum(len(item["dependsOn"]) for item in gradle_dependencies)
    if static_inventory is None:
        scope_limit = (
            "static libnode link closure is not included; platform-provided dynamic libraries are named but not versioned; npm version-range satisfaction is not verified by this generator"
        )
    else:
        scope_limit = (
            "candidate-specific static archives and direct linker edges are included; source and license evidence is not legal approval; platform-provided dynamic libraries are named but not versioned; npm version-range satisfaction is not verified by this generator"
        )
    if gradle_runtime_manifest is not None:
        scope_limit += "; Android Gradle runtime graph is limited to the supplied resolved configuration manifest"
    metadata_properties = [
        property_item("aggregate:artifact-kind", artifact_kind),
        property_item("aggregate:artifact-sha256", archive_hash),
        property_item("aggregate:node-version", args.node_version),
        property_item("aggregate:node-mobile-version", args.node_mobile_version),
        property_item("aggregate:ndk-version", args.ndk_version),
        property_item("aggregate:node-source-git-tree", args.source_git_tree),
        property_item("aggregate:node-upstream-commit", args.upstream_commit),
        property_item("aggregate:mobile-recipe-commit", args.recipe_commit),
        property_item("aggregate:npm-dependency-edges-resolved", resolved_npm_edges),
        property_item("aggregate:npm-dependency-edges-unresolved", len(unresolved_npm_edges)),
        property_item(
            "aggregate:npm-optional-peer-dependencies-not-packaged",
            len(optional_peer_dependencies_not_packaged),
        ),
        property_item("aggregate:native-packaged-dynamic-edges", native_packaged_edges),
        property_item("aggregate:native-unbundled-dynamic-edges", len(native_unbundled_edges)),
        property_item(
            "aggregate:native-unbundled-needed-libraries",
            json.dumps(sorted({name for _, name in native_unbundled_edges})),
        ),
        property_item(
            "aggregate:scope-limit",
            scope_limit,
        ),
    ]
    if static_inventory is not None:
        metadata_properties.extend(
            [
                property_item("aggregate:static-link-inventory-format", static_inventory["format"]),
                property_item("aggregate:static-link-source-components", static_inventory_stats["sourceComponents"]),
                property_item("aggregate:static-link-explicit-archives", static_inventory_stats["explicitArchives"]),
                property_item("aggregate:static-link-explicit-archive-members", static_inventory_stats["explicitArchiveMembers"]),
                property_item("aggregate:static-link-retained-archives", static_inventory_stats["explicitRetainedArchives"]),
                property_item("aggregate:static-link-retained-archive-object-pairs", static_inventory_stats["retainedArchiveObjectPairs"]),
                property_item("aggregate:static-link-zero-retained-archives", static_inventory_stats["zeroRetainedArchives"]),
                property_item("aggregate:static-link-implicit-ndk-archives", static_inventory_stats["implicitNdkArchives"]),
                property_item("aggregate:static-link-libnode-archive-edges", static_inventory_stats["retainedArchiveEdges"]),
            ]
        )
    if gradle_runtime_manifest is None:
        metadata_properties.append(
            property_item("aggregate:android-gradle-runtime-graph", "not provided")
        )
    else:
        metadata_properties.extend(
            [
                property_item("aggregate:gradle-runtime-configuration", gradle_configuration),
                property_item("aggregate:gradle-runtime-components", len(gradle_runtime_refs)),
                property_item("aggregate:gradle-runtime-edges", gradle_edge_count),
                property_item("aggregate:android-gradle-runtime-graph", "resolved manifest included"),
                property_item(
                    "aggregate:android-gradle-runtime-manifest-source",
                    gradle_runtime_manifest_source or "unknown",
                ),
                property_item(
                    "aggregate:android-gradle-runtime-manifest-sha256",
                    sha256(gradle_runtime_manifest_bytes or b""),
                ),
            ]
        )
    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, archive_hash)}",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": artifact_ref,
                "name": "Aggregate Android NodeProbe (experimental)",
                "version": args.artifact_version,
                "hashes": [{"alg": "SHA-256", "content": archive_hash}],
                "properties": metadata_properties,
            }
        },
        "components": sorted(components, key=lambda item: (str(item.get("name", "")), str(item.get("bom-ref", "")))),
        "compositions": [{"aggregate": "incomplete"}],
    }
    dependencies = npm_dependencies + native_dependencies + gradle_dependencies
    if dependencies:
        bom["dependencies"] = sorted(dependencies, key=lambda item: str(item.get("ref", "")))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(bom, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(components)} components for {args.archive} ({archive_hash})")
    print(
        f"Resolved {resolved_npm_edges} npm dependency edges; "
        f"{len(unresolved_npm_edges)} required declared edges were unresolved; "
        f"{len(optional_peer_dependencies_not_packaged)} optional peer dependencies are not packaged"
    )
    print(
        f"Recorded {native_packaged_edges} packaged native dynamic edges; "
        f"{len(native_unbundled_edges)} Android/platform dynamic requirements are unbundled"
    )
    print(
        "Composition: incomplete (platform-library versions and legal approval "
        "are not included)"
    )
    if static_inventory is not None:
        print(
            f"Recorded {static_inventory_stats['sourceComponents']} static source components, "
            f"{static_inventory_stats['explicitArchives']} explicit archives, "
            f"{static_inventory_stats['implicitNdkArchives']} implicit NDK archives, and "
            f"{static_inventory_stats['retainedArchiveEdges']} direct libnode archive edges"
        )
    if gradle_runtime_manifest is not None:
        print(
            f"Recorded {len(gradle_runtime_refs)} Gradle runtime components and "
            f"{gradle_edge_count} runtime dependency edges for {gradle_configuration}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
