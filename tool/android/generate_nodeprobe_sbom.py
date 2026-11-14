#!/usr/bin/env python3
"""Generate an explicitly incomplete CycloneDX inventory from a NodeProbe APK/AAB.

The archive is the source of truth for packaged native libraries, npm package
metadata, and embedded license/notice files. Declared npm dependencies and
peer dependencies are resolved against the packaged tree. This does not verify
npm version ranges, and does not infer the full static link graph inside
libnode.so or the Android Gradle dependency graph; the output marks its
composition incomplete for those reasons.
"""

from __future__ import annotations

import argparse
import hashlib
import json
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="NodeProbe APK or AAB to inventory")
    parser.add_argument("output", type=Path, help="CycloneDX JSON output path")
    parser.add_argument("--artifact-version", required=True, help="Human-readable candidate label")
    parser.add_argument("--node-version", default="unknown")
    parser.add_argument("--node-mobile-version", default="unknown")
    parser.add_argument("--ndk-version", default="unknown")
    parser.add_argument("--source-tree-sha256", default="unknown")
    parser.add_argument("--upstream-commit", default="unknown")
    parser.add_argument("--recipe-commit", default="unknown")
    args = parser.parse_args()

    archive_hash = sha256_file(args.archive)
    artifact_kind = args.archive.suffix.lower().lstrip(".")
    if artifact_kind not in {"apk", "aab"}:
        parser.error("archive must be an APK or AAB")

    components: list[dict[str, object]] = []
    package_components: dict[str, dict[str, object]] = {}
    package_metadata: dict[str, dict[str, object]] = {}
    npm_root: str | None = None
    with zipfile.ZipFile(args.archive) as archive:
        names = archive.namelist()
        lib_prefixes = ("lib/", "base/lib/")

        for path in sorted(names):
            if path.endswith("/"):
                continue
            data = archive.read(path)
            basename = PurePosixPath(path).name

            if basename.lower().startswith(("license", "licence", "notice", "copying", "copyright")):
                components.append(file_component(path, data, "license-or-notice"))

            if path.endswith(".so") and path.startswith(lib_prefixes):
                name = basename
                component: dict[str, object] = {
                    "type": "library",
                    "bom-ref": ref_for_path(path),
                    "name": name,
                    "hashes": [{"alg": "SHA-256", "content": sha256(data)}],
                    "properties": [property_item("aggregate:archive-path", path)],
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

    # The exact archive digest gives every archive-level component a stable anchor.
    artifact_ref = f"urn:aggregate:nodeprobe-{artifact_kind}:{archive_hash}"
    metadata_properties = [
        property_item("aggregate:artifact-kind", artifact_kind),
        property_item("aggregate:artifact-sha256", archive_hash),
        property_item("aggregate:node-version", args.node_version),
        property_item("aggregate:node-mobile-version", args.node_mobile_version),
        property_item("aggregate:ndk-version", args.ndk_version),
        property_item("aggregate:node-source-tree-sha256", args.source_tree_sha256),
        property_item("aggregate:node-upstream-commit", args.upstream_commit),
        property_item("aggregate:mobile-recipe-commit", args.recipe_commit),
        property_item("aggregate:npm-dependency-edges-resolved", resolved_npm_edges),
        property_item("aggregate:npm-dependency-edges-unresolved", len(unresolved_npm_edges)),
        property_item(
            "aggregate:npm-optional-peer-dependencies-not-packaged",
            len(optional_peer_dependencies_not_packaged),
        ),
        property_item(
            "aggregate:scope-limit",
            "static libnode and Android Gradle dependency graphs are incomplete; npm version-range satisfaction is not verified by this generator",
        ),
    ]
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
    if npm_dependencies:
        bom["dependencies"] = npm_dependencies
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(bom, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(components)} components for {args.archive} ({archive_hash})")
    print(
        f"Resolved {resolved_npm_edges} npm dependency edges; "
        f"{len(unresolved_npm_edges)} required declared edges were unresolved; "
        f"{len(optional_peer_dependencies_not_packaged)} optional peer dependencies are not packaged"
    )
    print(
        "Composition: incomplete (static libnode and Android Gradle dependency "
        "graphs are not fully reconstructed)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
