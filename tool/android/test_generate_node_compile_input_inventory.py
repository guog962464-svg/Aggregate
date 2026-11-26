import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("generate_node_compile_input_inventory.py")
SPEC = importlib.util.spec_from_file_location(
    "generate_node_compile_input_inventory", MODULE_PATH
)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class PreprocessorCommandTest(unittest.TestCase):
    def test_replaces_compile_outputs_with_full_dependency_mode(self) -> None:
        command = (
            "/ndk/bin/clang++ -o out/object.o -DANDROID -Iinclude "
            "-MMD -MF out/object.o.d -c ../src/main.cc"
        )

        self.assertEqual(
            GENERATOR.preprocessing_argv(command),
            [
                "/ndk/bin/clang++",
                "-DANDROID",
                "-Iinclude",
                "../src/main.cc",
                "-M",
            ],
        )

    def test_reads_make_continuations_and_escaped_spaces(self) -> None:
        output = (
            "object.o: ../src/main.cc "
            + chr(92)
            + "\n  ../include/My"
            + chr(92)
            + " Header.h /ndk/sysroot/include/stdint.h\n"
        )

        self.assertEqual(
            GENERATOR.dependencies_from_make_output(output),
            [
                "../src/main.cc",
                "../include/My Header.h",
                "/ndk/sysroot/include/stdint.h",
            ],
        )


class DependencyRecordTest(unittest.TestCase):
    def test_requires_recorded_command_and_matching_object_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            object_path = root / "out/Release/obj.target/libnode/main.o"
            depfile = root / "main.o.d"
            depfile.write_text(
                f"cmd_{object_path} := /ndk/bin/clang++ -c main.cc\n"
                f"{object_path}: main.cc header.h\n"
                "main.cc:\nheader.h:\n"
            )

            command, text = GENERATOR.recorded_object_command(depfile, object_path)

            self.assertEqual(command, "/ndk/bin/clang++ -c main.cc")
            self.assertIn("header.h", text)
            with self.assertRaisesRegex(ValueError, "does not match"):
                GENERATOR.recorded_object_command(depfile, root / "other.o")

    def test_resolves_object_depfile_under_release_deps_tree(self) -> None:
        root = Path("/node-build")

        self.assertEqual(
            GENERATOR.resolve_depfile(
                root, "out/Release/obj.target/libnode/src/main.o"
            ),
            Path(
                "/node-build/out/Release/.deps/node-build/out/Release/"
                "obj.target/libnode/src/main.o.d"
            ),
        )

    def test_canonicalizes_source_generated_ndk_and_external_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "node"
            ndk = Path(directory) / "ndk"
            (root / "deps").mkdir(parents=True)
            (root / "out/generated").mkdir(parents=True)
            (ndk / "sysroot/include").mkdir(parents=True)
            outside = Path(directory) / "outside.h"
            source = root / "deps/source.h"
            generated = root / "out/generated/header.h"
            ndk_header = ndk / "sysroot/include/header.h"
            for path in (outside, source, generated, ndk_header):
                path.write_text("header\n")

            self.assertEqual(
                GENERATOR.canonical_input_path(str(source), root, ndk)[0],
                "source/deps/source.h",
            )
            self.assertEqual(
                GENERATOR.canonical_input_path(str(generated), root, ndk)[0],
                "build/out/generated/header.h",
            )
            self.assertEqual(
                GENERATOR.canonical_input_path(str(ndk_header), root, ndk)[0],
                "ndk/sysroot/include/header.h",
            )
            self.assertEqual(
                GENERATOR.canonical_input_path(str(outside), root, ndk)[0],
                f"external/{outside.resolve().as_posix().lstrip('/')}",
            )


if __name__ == "__main__":
    unittest.main()
