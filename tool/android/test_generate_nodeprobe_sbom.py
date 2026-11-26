import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("generate_nodeprobe_sbom.py")
SPEC = importlib.util.spec_from_file_location("generate_nodeprobe_sbom", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class SpdxExpressionSyntaxTest(unittest.TestCase):
    def test_accepts_grouped_composite_license_candidate(self) -> None:
        expression = (
            "Apache-2.0 AND (Apache-2.0 WITH LLVM-exception) AND "
            "(BSD-2-Clause OR CC0-1.0) AND BSD-3-Clause AND "
            "(BSD-3-Clause AND LicenseRef-V8-fdlibm-Sun) AND "
            "LicenseRef-SQLite-public-domain-dedication AND MIT AND "
            "(MIT AND BSD-2-Clause AND ISC) AND (NCSA OR MIT) AND "
            "Unicode-3.0 AND Zlib"
        )
        self.assertTrue(GENERATOR.is_spdx_expression(expression))

    def test_accepts_with_custom_document_reference(self) -> None:
        self.assertTrue(
            GENERATOR.is_spdx_expression(
                "GPL-2.0-only WITH Autoconf-exception-3.0 OR "
                "DocumentRef-third-party:LicenseRef-custom"
            )
        )

    def test_accepts_and_precedence_over_or(self) -> None:
        self.assertTrue(
            GENERATOR.is_spdx_expression("MIT OR Apache-2.0 AND BSD-3-Clause")
        )

    def test_rejects_incomplete_or_unbalanced_expressions(self) -> None:
        for expression in (
            "",
            "MIT AND",
            "MIT OR (BSD-3-Clause",
            "(MIT) WITH LLVM-exception",
            "MIT && BSD-3-Clause",
        ):
            with self.subTest(expression=expression):
                self.assertFalse(GENERATOR.is_spdx_expression(expression))


class BinaryLicenseInventoryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.archive_path = self.root / "candidate.apk"
        self.binary_path = "lib/arm64-v8a/libc++_shared.so"
        self.evidence_path = "assets/NOTICE-NDK-toolchain"
        self.binary = b"candidate native library"
        self.evidence = b"libc++ is dual licensed under NCSA OR MIT"
        with zipfile.ZipFile(self.archive_path, "w") as archive:
            archive.writestr(self.binary_path, self.binary)
            archive.writestr(self.evidence_path, self.evidence)
        self.archive_hash = GENERATOR.sha256_file(self.archive_path)
        self.inventory = {
            "format": "aggregate-nodeprobe-binary-license-inventory-v1",
            "archive": {
                "sha256": self.archive_hash,
                "sizeBytes": self.archive_path.stat().st_size,
            },
            "binaries": [
                {
                    "archivePath": self.binary_path,
                    "sha256": GENERATOR.sha256(self.binary),
                    "licenseCandidate": {
                        "status": "candidate",
                        "expression": "NCSA OR MIT",
                    },
                    "evidence": [
                        {
                            "path": self.evidence_path,
                            "sha256": GENERATOR.sha256(self.evidence),
                        }
                    ],
                    "provenance": {
                        "source": "NDK arm64 sysroot libc++_shared.so",
                        "sourceSha256": "a" * 64,
                        "transform": "llvm-strip --strip-unneeded",
                        "outputSha256": GENERATOR.sha256(self.binary),
                    },
                }
            ],
        }

    def validate(self, inventory: dict[str, object] | None = None):
        with zipfile.ZipFile(self.archive_path) as archive:
            return GENERATOR.validate_binary_license_inventory(
                inventory if inventory is not None else self.inventory,
                archive.namelist(),
                archive,
                self.archive_hash,
                self.archive_path.stat().st_size,
                ("lib/", "base/lib/"),
            )

    def test_binds_license_candidate_to_archive_binary_and_notice(self) -> None:
        mappings = self.validate()
        mapping = mappings[self.binary_path]
        self.assertEqual(mapping["_licenseEntries"], [{"expression": "NCSA OR MIT"}])
        self.assertIn(
            {
                "name": "aggregate:license-candidate-status",
                "value": "candidate; legal review pending",
            },
            mapping["_licenseProperties"],
        )
        self.assertEqual(
            mapping["evidence"],
            [{"path": self.evidence_path, "sha256": GENERATOR.sha256(self.evidence)}],
        )

    def test_rejects_wrong_archive_identity(self) -> None:
        inventory = dict(self.inventory)
        inventory["archive"] = {
            "sha256": "0" * 64,
            "sizeBytes": self.archive_path.stat().st_size,
        }
        with self.assertRaisesRegex(ValueError, "archive SHA-256"):
            self.validate(inventory)

    def test_rejects_wrong_packaged_binary_hash(self) -> None:
        inventory = json.loads(json.dumps(self.inventory))
        inventory["binaries"][0]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "packaged binary hash"):
            self.validate(inventory)

    def test_rejects_wrong_embedded_notice_hash(self) -> None:
        inventory = json.loads(json.dumps(self.inventory))
        inventory["binaries"][0]["evidence"][0]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "license evidence hash"):
            self.validate(inventory)

    def test_rejects_unsafe_archive_paths_and_duplicate_mappings(self) -> None:
        inventory = json.loads(json.dumps(self.inventory))
        inventory["binaries"][0]["archivePath"] = "lib/../lib/arm64-v8a/libc++_shared.so"
        with self.assertRaisesRegex(ValueError, "safe archive-relative path"):
            self.validate(inventory)

        inventory = json.loads(json.dumps(self.inventory))
        inventory["binaries"].append(dict(inventory["binaries"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate binary-license mapping"):
            self.validate(inventory)

    def test_rejects_provenance_output_that_does_not_match_binary(self) -> None:
        inventory = json.loads(json.dumps(self.inventory))
        inventory["binaries"][0]["provenance"]["outputSha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "output hash"):
            self.validate(inventory)


if __name__ == "__main__":
    unittest.main()
