import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("generate_node_generator_tool_source_map.py")
SPEC = importlib.util.spec_from_file_location("generate_node_generator_tool_source_map", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class HostToolMakefileTest(unittest.TestCase):
    def test_parses_host_objects_and_archive_link_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "node"
            release = root / "out/Release"
            makefile = root / "out/tools/test.host.mk"
            object_path = release / "obj.host/test/src/main.o"
            archive_path = release / "obj.host/lib/libtest.a"
            binary_path = release / "test"
            for path in (object_path, archive_path, binary_path):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"fixture")
            makefile.parent.mkdir(parents=True, exist_ok=True)
            makefile.write_text(
                "TOOLSET := host\n"
                "TARGET := test\n"
                "OBJS := \\\n"
                "  $(obj).host/$(TARGET)/src/main.o\n"
                "$(builddir)/test: LD_INPUTS := $(OBJS) $(obj).host/lib/libtest.a\n"
            )

            parsed = GENERATOR.parse_tool_makefile(makefile, root)

        self.assertEqual(parsed["name"], "test")
        self.assertEqual(parsed["objectPaths"], [object_path.resolve()])
        self.assertEqual(parsed["linkInputs"], [object_path.resolve(), archive_path.resolve()])
        self.assertEqual(parsed["binaryPath"], binary_path.resolve())


class ArchiveMemberParserTest(unittest.TestCase):
    def test_reads_bsd_extended_member_name_and_payload(self) -> None:
        name = b"long-object-name.o"
        payload = b"object bytes"
        body = name + payload
        raw_name = f"#1/{len(name)}".encode().ljust(16)
        header = (
            raw_name
            + b"0".ljust(12)
            + b"0".ljust(6)
            + b"0".ljust(6)
            + b"100644".ljust(8)
            + str(len(body)).encode().ljust(10)
            + b"`\n"
        )

        members = GENERATOR.parse_archive_members(b"!<arch>\n" + header + body)

        self.assertEqual(members, [("long-object-name.o", payload)])


class CompilerInputCommandTest(unittest.TestCase):
    def test_replaces_recorded_compile_outputs_with_dependency_mode(self) -> None:
        argv = GENERATOR.preprocessing_argv(
            "/toolchain/clang++ -o out/main.o -DHOST -MMD -MF out/main.o.d -c src/main.cc"
        )

        self.assertEqual(argv, ["/toolchain/clang++", "-DHOST", "src/main.cc", "-M"])

    def test_parses_escaped_space_dependencies(self) -> None:
        output = "main.o: src/main.cc include/My\\ Header.h /sdk/stdio.h\n"

        self.assertEqual(
            GENERATOR.dependencies_from_make_output(output),
            ["src/main.cc", "include/My Header.h", "/sdk/stdio.h"],
        )


if __name__ == "__main__":
    unittest.main()
