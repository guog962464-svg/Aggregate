import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("generate_ndk_runtime_source_map.py")
SPEC = importlib.util.spec_from_file_location(
    "generate_ndk_runtime_source_map", MODULE_PATH
)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


def ar_header(name: str, payload: bytes) -> bytes:
    fields = (
        name.encode("ascii").ljust(16)
        + b"0".ljust(12)
        + b"0".ljust(6)
        + b"0".ljust(6)
        + b"100644".ljust(8)
        + str(len(payload)).encode("ascii").ljust(10)
        + b"`\n"
    )
    assert len(fields) == 60
    return fields + payload + (b"\n" if len(payload) & 1 else b"")


class ArArchiveTest(unittest.TestCase):
    def test_reads_gnu_long_names_and_ignores_symbol_tables(self) -> None:
        long_name = b"outline_atomic_ldadd8_4.S.o/\n"
        archive = (
            b"!<arch>\n"
            + ar_header("/", b"symbol index")
            + ar_header("//", long_name)
            + ar_header("/0", b"object bytes")
        )

        self.assertEqual(
            GENERATOR.parse_ar_members(archive),
            [("outline_atomic_ldadd8_4.S.o", b"object bytes")],
        )

    def test_rejects_duplicate_member_labels(self) -> None:
        archive = (
            b"!<arch>\n"
            + ar_header("same.o/", b"first")
            + ar_header("same.o/", b"second")
        )

        with self.assertRaisesRegex(ValueError, "duplicate member names"):
            GENERATOR.parse_ar_members(archive)


class CMakeSourceSelectionTest(unittest.TestCase):
    def test_architecture_source_replaces_generic_duplicate(self) -> None:
        cmake = """
        set(GENERIC_SOURCES
          fp_mode.c
          divtc3.c
          clear_cache.c
        )
        set(GENERIC_TF_SOURCES
          divtf3.c
        )
        set(BF16_SOURCES
          extendbfsf2.c
        )
        set(aarch64_SOURCES
          ${GENERIC_TF_SOURCES}
          ${GENERIC_SOURCES}
          cpu_model/aarch64.c
          aarch64/fp_mode.c
        )
        """

        selected = GENERATOR.selected_aarch64_sources(cmake, set())

        self.assertIn("divtc3.c", selected)
        self.assertIn("cpu_model/aarch64.c", selected)
        self.assertIn("aarch64/fp_mode.c", selected)
        self.assertNotIn("fp_mode.c", selected)

    def test_models_the_pinned_outline_atomic_generation_loop(self) -> None:
        generated = GENERATOR.cmake_generated_outline_names()

        self.assertEqual(len(generated), 125)
        self.assertIn("outline_atomic_cas16_5.S.o", generated)
        self.assertIn("outline_atomic_ldset8_4.S.o", generated)
        self.assertNotIn("outline_atomic_ldset16_4.S.o", generated)


if __name__ == "__main__":
    unittest.main()
