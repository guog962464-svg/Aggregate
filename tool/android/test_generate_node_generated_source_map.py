import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("generate_node_generated_source_map.py")
SPEC = importlib.util.spec_from_file_location("generate_node_generated_source_map", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class MakeActionParsingTest(unittest.TestCase):
    def test_collapses_make_continuations(self) -> None:
        text = "one " + chr(92) + "\n  two\nthree\n"
        parsed = GENERATOR.parse_make_continuations(text)

        self.assertEqual(parsed, ["one  two", "three"])

    def test_reads_direct_inputs_and_ignores_make_control_edges(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            makefile = root / "out/test.target.mk"
            makefile.parent.mkdir(parents=True)
            makefile.write_text(
                "TOOLSET := target\n"
                "TARGET := test\n"
                "### Rules for action \"generate\":\n"
                "cmd_generate = python3 tools/gen.py --input source.txt\n"
                "$(obj)/gen/output.cc: obj := $(abs_obj)\n"
                "$(obj)/gen/output.cc: builddir := $(abs_builddir)\n"
                "$(obj)/gen/output.cc: $(srcdir)/source.txt $(builddir)/tools/gen.py FORCE_DO_CMD\n"
                "\t$(call do_cmd,generate)\n"
                "all_deps += $(obj)/gen/output.cc\n"
                "action_generate_outputs := $(obj)/gen/output.cc\n"
            )

            action = GENERATOR.parse_action_definitions(makefile, root)[0]

        self.assertEqual(action["actionName"], "generate")
        self.assertEqual(
            action["declaredInputTokens"],
            ["$(builddir)/tools/gen.py", "$(srcdir)/source.txt"],
        )

    def test_uses_intermediate_prerequisites_without_stamp_tokens(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            makefile = root / "out/test.target.mk"
            makefile.parent.mkdir(parents=True)
            makefile.write_text(
                "TOOLSET := target\n"
                "TARGET := test\n"
                "### Rules for action \"generate\":\n"
                "cmd_generate = python3 tools/gen.py\n"
                "$(obj)/gen/a.cc $(obj)/gen/a.h: aabb.intermediate\n"
                ".INTERMEDIATE: aabb.intermediate\n"
                "aabb.intermediate: $(srcdir)/input.idl $(builddir)/codegen FORCE_DO_CMD\n"
                "action_generate_outputs := $(obj)/gen/a.cc $(obj)/gen/a.h\n"
            )

            action = GENERATOR.parse_action_definitions(makefile, root)[0]

        self.assertEqual(
            action["declaredInputTokens"],
            ["$(builddir)/codegen", "$(srcdir)/input.idl"],
        )


class GeneratedSourceMapTest(unittest.TestCase):
    def test_maps_linked_generated_source_and_hashes_declared_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "node"
            output = root / "out/Release/obj/gen/generated.cc"
            source = root / "src/generator_input.txt"
            tool = root / "out/Release/generator.py"
            makefile = root / "out/test.target.mk"
            for path, content in (
                (output, "// generated\n"),
                (source, "input\n"),
                (tool, "print('generator')\n"),
            ):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            (root / "out/Makefile").write_text("# configured make root\n")
            makefile.write_text(
                "TOOLSET := target\n"
                "TARGET := test\n"
                "### Rules for action \"generate\":\n"
                "cmd_generate = python3 generator.py\n"
                "$(obj)/gen/generated.cc: obj := $(abs_obj)\n"
                "$(obj)/gen/generated.cc: builddir := $(abs_builddir)\n"
                "$(obj)/gen/generated.cc: $(srcdir)/src/generator_input.txt $(builddir)/generator.py FORCE_DO_CMD\n"
                "\t$(call do_cmd,generate)\n"
                "action_generate_outputs := $(obj)/gen/generated.cc\n"
            )
            static_inventory_path = root / "static-inventory.json"
            object_sidecar_path = root / "objects.jsonl"
            row = {
                "archive": "libtest.a",
                "archiveOrdinal": 1,
                "memberName": "generated.o",
                "objectPath": "out/Release/obj.target/libtest/generated.o",
                "objectSha256": "0" * 64,
                "sourcePaths": ["out/Release/obj/gen/generated.cc"],
                "sourceSha256": GENERATOR.sha256_file(output),
                "sourceStatus": "generated-output",
                "sourceComponentId": "test",
            }
            source_hash = row["sourceSha256"]
            object_sidecar_path.write_text(json.dumps(row) + "\n")
            static_inventory_path.write_text(
                json.dumps(
                    {
                        "candidate": {"nodeVersion": "test"},
                        "archiveObjectEntriesFile": {"path": "objects.jsonl"},
                    }
                )
            )

            result = GENERATOR.build_map(root, static_inventory_path)

        self.assertTrue(result["coverage"]["allGeneratedSourcePathsHaveConfiguredActions"])
        self.assertEqual(result["coverage"]["generatedSourcePathAssociations"], 1)
        self.assertEqual(result["coverage"]["unresolvedDeclaredInputCount"], 0)
        self.assertEqual(len(result["generatorActions"]), 1)
        self.assertEqual(len(result["declaredInputFiles"]), 3)
        mapped = result["generatedSources"][0]["sources"][0]
        self.assertEqual(mapped["sourceSha256"], source_hash)


if __name__ == "__main__":
    unittest.main()
