import importlib.util
import unittest
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


if __name__ == "__main__":
    unittest.main()
