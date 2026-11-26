#!/usr/bin/env python3
"""Map implicit Android NDK runtime archive members to pinned LLVM sources.

The NDK does not ship per-member build records for compiler-rt/libunwind.
This tool therefore records source associations reconstructed from the exact
NDK Clang source revision, its CMake source-selection rules, and archive member
names. It does not claim a reproducible NDK runtime rebuild.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import re
import shlex
import subprocess
import tarfile
import urllib.request
from pathlib import Path, PurePosixPath
from typing import Any


FORMAT = "aggregate-ndk-runtime-source-map-v1"
LLVM_GITILES_ROOT = "https://android.googlesource.com/toolchain/llvm-project"
OUTLINE_RE = re.compile(r"outline_atomic_(cas|swp|ldadd|ldclr|ldeor|ldset)(1|2|4|8|16)_([1-5])\.S\.o\Z")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_ar_members(data: bytes) -> list[tuple[str, bytes]]:
    """Read regular GNU/BSD ar archives, including GNU long-name tables."""
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
            raise ValueError(f"invalid member size at byte {offset}") from error
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
                raise ValueError(f"unterminated GNU long name at offset {start}")
            name = string_table[start:end].decode("utf-8")
        elif raw_name.startswith("#1/"):
            name_size = int(raw_name[3:])
            if name_size > len(payload):
                raise ValueError(f"invalid BSD long name length for {raw_name}")
            name = payload[:name_size].decode("utf-8")
            payload = payload[name_size:]
        else:
            name = raw_name.rstrip("/")
        members.append((name, payload))
    if len({name for name, _ in members}) != len(members):
        raise ValueError("archive has duplicate member names; explicit disambiguation is required")
    return members


def cmake_set_items(cmake: str, variable: str) -> list[str]:
    match = re.search(rf"\bset\s*\(\s*{re.escape(variable)}\b(.*?)\)", cmake, re.DOTALL)
    if not match:
        raise ValueError(f"CMake variable not found: {variable}")
    body = re.sub(r"(?m)#.*$", "", match.group(1))
    return [item for item in shlex.split(body.replace(";", " ")) if item]


def selected_aarch64_sources(cmake: str, archive_members: set[str]) -> set[str]:
    """Resolve compiler-rt's Android AArch64 source list and duplicate filter."""
    generic = cmake_set_items(cmake, "GENERIC_SOURCES")
    generic_tf = cmake_set_items(cmake, "GENERIC_TF_SOURCES")
    arch = cmake_set_items(cmake, "aarch64_SOURCES")
    selected = set(generic + generic_tf)
    selected.update(item for item in arch if not item.startswith("${"))
    selected.update(
        {
            "emutls.c",
            "enable_execute_stack.c",
            "eprintf.c",
            "clear_cache.c",
            "aarch64/arm_apple_sme_abi.s",
            "aarch64/sme-abi.S",
            "aarch64/sme-libc-mem-routines.S",
            "aarch64/sme-abi-assert.c",
            "aarch64/sme-libc-routines.c",
        }
    )
    # These source sets are guarded by compiler/build checks. Their presence in
    # the exact archive is evidence that the NDK build selected that branch.
    if "atomic.c.o" in archive_members:
        selected.add("atomic.c")
    if "gcc_personality_v0.c.o" in archive_members:
        selected.add("gcc_personality_v0.c")
    bfloat_sources = cmake_set_items(cmake, "BF16_SOURCES")
    selected.update(source for source in bfloat_sources if f"{source}.o" in archive_members)

    # Mirror filter_builtin_sources(): a subdirectory implementation replaces
    # the generic source with the same basename in an architecture's list.
    for source in tuple(selected):
        source_path = PurePosixPath(source)
        if len(source_path.parts) <= 1:
            continue
        basename = source_path.name
        generic_name = re.sub(r"\.S$", ".c", basename)
        if generic_name in selected:
            selected.remove(generic_name)
    return selected


def cmake_generated_outline_names() -> set[str]:
    generated: set[str] = set()
    for pattern in ("cas", "swp", "ldadd", "ldclr", "ldeor", "ldset"):
        for size in (1, 2, 4, 8, 16):
            for model in range(1, 6):
                if pattern == "cas" or size != 16:
                    generated.add(f"outline_atomic_{pattern}{size}_{model}.S.o")
    return generated


def source_tree(revision: str, subtree: str) -> tuple[dict[str, bytes], str]:
    url = f"{LLVM_GITILES_ROOT}/+archive/{revision}/{subtree}.tar.gz"
    request = urllib.request.Request(url, headers={"User-Agent": "Aggregate-NDK-source-map/1"})
    archive_bytes = urllib.request.urlopen(request, timeout=60).read()
    files: dict[str, bytes] = {}
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            name = PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts:
                raise ValueError(f"unsafe source path in Gitiles response: {member.name}")
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError(f"unreadable source file in Gitiles response: {member.name}")
            files[name.as_posix()] = stream.read()
    return files, url


def source_file(revision: str, path: str) -> tuple[bytes, str]:
    url = f"{LLVM_GITILES_ROOT}/+/{revision}/{path}?format=TEXT"
    request = urllib.request.Request(url, headers={"User-Agent": "Aggregate-NDK-source-map/1"})
    encoded = urllib.request.urlopen(request, timeout=60).read()
    return base64.b64decode(encoded), url


def map_archive(
    *,
    archive_name: str,
    archive_path: Path,
    expected: dict[str, Any],
    source_files: dict[str, bytes],
    cmake_files: dict[str, str],
    selected_sources: set[str] | None,
) -> dict[str, Any]:
    archive_bytes = archive_path.read_bytes()
    archive_hash = sha256_bytes(archive_bytes)
    if archive_hash != expected["sha256"]:
        raise ValueError(f"NDK archive hash mismatch for {archive_name}")
    members = parse_ar_members(archive_bytes)
    if len(members) != expected["archiveMemberEntries"]:
        raise ValueError(f"NDK archive member count mismatch for {archive_name}: {len(members)}")

    basename_candidates: dict[str, list[str]] = {}
    for path in source_files:
        basename_candidates.setdefault(PurePosixPath(path).name, []).append(path)
    selected: list[dict[str, Any]] = []
    for member_name, object_bytes in members:
        source_name = member_name[:-2] if member_name.endswith(".o") else member_name
        candidates = basename_candidates.get(source_name, [])
        match_kind = "exact-source-basename"
        generator: dict[str, Any] | None = None
        if archive_name == "libclang_rt.builtins-aarch64-android.a" and OUTLINE_RE.fullmatch(member_name):
            if member_name not in cmake_generated_outline_names():
                raise ValueError(f"outline helper is not generated by the pinned CMake rule: {member_name}")
            source_path = "aarch64/lse.S"
            match_kind = "cmake-generated-outline-atomic-copy"
            generated_match = OUTLINE_RE.fullmatch(member_name)
            assert generated_match is not None
            generator = {
                "cmakeFile": "CMakeLists.txt",
                "cmakeRule": "outline atomic helper generation",
                "pattern": generated_match.group(1),
                "size": int(generated_match.group(2)),
                "model": int(generated_match.group(3)),
                "command": "cmake -E create_symlink or copy aarch64/lse.S",
            }
        else:
            if selected_sources is not None:
                candidates = [candidate for candidate in candidates if candidate in selected_sources]
            if len(candidates) != 1:
                raise ValueError(
                    f"expected one selected source for {archive_name}:{member_name}; got {candidates}"
                )
            source_path = candidates[0]
        if source_path not in source_files:
            raise ValueError(f"source path missing from pinned tree: {source_path}")
        if selected_sources is not None and generator is None and source_path not in selected_sources:
            raise ValueError(f"source is not selected by pinned Android target rules: {source_path}")
        rule_paths = (
            [
                "compiler-rt/lib/builtins/CMakeLists.txt",
                "compiler-rt/cmake/Modules/CompilerRTUtils.cmake",
            ]
            if selected_sources is not None
            else ["libunwind/src/CMakeLists.txt"]
        )
        selected.append(
            {
                "member": member_name,
                "memberSha256": sha256_bytes(object_bytes),
                "sourcePath": source_path,
                "sourceSha256": sha256_bytes(source_files[source_path]),
                "mappingBasis": match_kind,
                "sourceRuleFiles": [
                    {"path": path, "sha256": sha256_bytes(cmake_files[path].encode())}
                    for path in rule_paths
                ],
                "generator": generator,
                "linkerMapHasOutputSection": member_name in expected.get("memberNamesWithLinkerMapOutputSections", []),
            }
        )
    if selected_sources is None:
        listed = set()
        for variable in ("LIBUNWIND_CXX_SOURCES", "LIBUNWIND_C_SOURCES", "LIBUNWIND_ASM_SOURCES"):
            listed.update(
                f"src/{path}"
                for path in cmake_set_items(cmake_files["libunwind/src/CMakeLists.txt"], variable)
            )
        for item in selected:
            if item["sourcePath"] not in listed:
                raise ValueError(f"libunwind source absent from CMake source lists: {item['sourcePath']}")
    return {
        "name": archive_name,
        "path": expected["path"],
        "sha256": archive_hash,
        "sizeBytes": len(archive_bytes),
        "memberCount": len(selected),
        "members": selected,
    }


def build_source_map(ndk_root: Path, static_inventory_path: Path) -> dict[str, Any]:
    inventory = json.loads(static_inventory_path.read_text())
    candidate = inventory["candidate"]
    host_prebuilt = ndk_root / "toolchains/llvm/prebuilt/darwin-x86_64"
    clang = host_prebuilt / "bin/clang"
    clang_source_info = host_prebuilt / "clang_source_info.md"
    compiler_output = subprocess.run([str(clang), "--version"], check=True, capture_output=True, text=True).stdout
    compiler_revision = re.search(r"toolchain/llvm-project\s+([0-9a-f]{40})", compiler_output)
    base_revision = re.search(r"Base revision:.*?\[([0-9a-f]{40})\]", clang_source_info.read_text())
    if compiler_revision is None or base_revision is None:
        raise ValueError("could not identify NDK LLVM fork and upstream base revisions")
    revision = compiler_revision.group(1)
    source_info_text = clang_source_info.read_text()
    trees = {
        "compiler-rt/lib/builtins": source_tree(revision, "compiler-rt/lib/builtins"),
        "libunwind": source_tree(revision, "libunwind"),
    }
    builtin_files, builtin_url = trees["compiler-rt/lib/builtins"]
    unwind_files, unwind_url = trees["libunwind"]
    builtin_cmake = builtin_files["CMakeLists.txt"].decode()
    unwind_cmake = unwind_files["src/CMakeLists.txt"].decode()
    compiler_rt_utils_bytes, compiler_rt_utils_url = source_file(
        revision, "compiler-rt/cmake/Modules/CompilerRTUtils.cmake"
    )
    compiler_rt_utils = compiler_rt_utils_bytes.decode()
    builtin_archive = ndk_root / inventory["implicitNdkArchives"][1]["path"]
    builtin_member_names = {name for name, _ in parse_ar_members(builtin_archive.read_bytes())}
    selected_aarch64 = selected_aarch64_sources(builtin_cmake, builtin_member_names)
    compiler_rt_meta = {f"compiler-rt/lib/builtins/{path}": data for path, data in builtin_files.items()}
    unwind_meta = {f"libunwind/{path}": data for path, data in unwind_files.items()}
    files = {**compiler_rt_meta, **unwind_meta}
    files["compiler-rt/cmake/Modules/CompilerRTUtils.cmake"] = compiler_rt_utils_bytes
    cmake_text = {
        "compiler-rt/lib/builtins/CMakeLists.txt": builtin_cmake,
        "compiler-rt/cmake/Modules/CompilerRTUtils.cmake": compiler_rt_utils,
        "libunwind/src/CMakeLists.txt": unwind_cmake,
    }
    mapped_archives: list[dict[str, Any]] = []
    for archive in inventory["implicitNdkArchives"]:
        archive_path = ndk_root / archive["path"]
        if archive["name"] == "libclang_rt.builtins-aarch64-android.a":
            source_files = builtin_files
            selected_sources: set[str] | None = selected_aarch64
        elif archive["name"] == "libunwind.a":
            source_files = unwind_files
            selected_sources = None
        else:
            raise ValueError(f"unrecognized implicit archive: {archive['name']}")
        mapped_archives.append(
            map_archive(
                archive_name=archive["name"],
                archive_path=archive_path,
                expected=archive,
                source_files=source_files,
                cmake_files=cmake_text,
                selected_sources=selected_sources,
            )
        )
    source_file_records = [
        {"path": path, "sha256": sha256_bytes(data)} for path, data in sorted(files.items())
    ]
    return {
        "format": FORMAT,
        "candidate": {
            "nodeVersion": candidate["nodeVersion"],
            "androidAbi": candidate["androidAbi"],
            "ndkRevision": candidate["ndkRevision"],
            "sourcePropertiesSha256": sha256_file(ndk_root / "source.properties"),
            "apkSha256": candidate["apkSha256"],
            "unstrippedLibnodeSha256": candidate["unstrippedLibnodeSha256"],
            "staticLinkInventorySha256": sha256_file(static_inventory_path),
        },
        "ndkToolchain": {
            "clangVersionOutput": compiler_output.strip().splitlines()[0],
            "androidLLVMCommit": revision,
            "upstreamBaseRevision": base_revision.group(1),
            "clangSourceInfoPath": str(clang_source_info),
            "clangSourceInfoSha256": sha256_file(clang_source_info),
            "clangBinarySha256": sha256_file(clang),
            "androidLLVMCommitUrl": f"{LLVM_GITILES_ROOT}/+/{revision}/",
            "upstreamBaseRevisionUrl": f"https://github.com/llvm/llvm-project/tree/{base_revision.group(1)}",
            "sourceInfoPatchSetIncluded": True,
        },
        "method": {
            "summary": "Archive member names are associated with source files selected by the pinned NDK LLVM CMake rules. GNU ar member hashes bind the mapping to the exact local NDK archives.",
            "compilerRtSelection": "CMake GENERIC_SOURCES + GENERIC_TF_SOURCES + aarch64_SOURCES, Android conditional sources, and filter_builtin_sources duplicate-source rules.",
            "outlineAtomics": "The 125 outline_atomic_* objects are generated by the pinned CMake loop as symlink/copy variants of aarch64/lse.S with pattern, size, and model compile definitions.",
            "limits": [
                "The NDK package does not provide per-member compile commands or source-object manifests; source associations are reconstructed from exact member labels and pinned build rules.",
                "Configure-time compiler-rt branches are inferred from archive member presence when the packaged NDK omits its CMake cache.",
                "This mapping does not reproduce object code or prove all compiler flags, toolchain patches, package provenance, license obligations, or legal approval.",
                "The Node build tree's compiler include-input closure is recorded separately; this file maps only the two implicit NDK archives.",
            ],
        },
        "sourceTrees": [
            {
                "subtree": "compiler-rt/lib/builtins",
                "url": builtin_url,
                "commit": revision,
                "fileCount": len(builtin_files),
                "cmakeSha256": sha256_bytes(builtin_files["CMakeLists.txt"]),
            },
            {
                "subtree": "libunwind",
                "url": unwind_url,
                "commit": revision,
                "fileCount": len(unwind_files),
                "cmakeSha256": sha256_bytes(unwind_files["src/CMakeLists.txt"]),
            },
        ],
        "supportingSourceFiles": [
            {
                "path": "compiler-rt/cmake/Modules/CompilerRTUtils.cmake",
                "url": compiler_rt_utils_url,
                "sha256": sha256_bytes(compiler_rt_utils_bytes),
            }
        ],
        "sourceFiles": source_file_records,
        "archives": mapped_archives,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk-root", type=Path, required=True)
    parser.add_argument("--static-inventory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build_source_map(args.ndk_root, args.static_inventory)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {args.output} ({sum(a['memberCount'] for a in result['archives'])} archive members)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
