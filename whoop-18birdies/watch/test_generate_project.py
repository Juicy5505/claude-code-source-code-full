"""Tests for the Xcode project generator.

A malformed .xcodeproj is worse than no .xcodeproj: Xcode reports "the project
file cannot be parsed" and gives no clue which of a thousand lines is wrong.
Since there is no Mac here to open it on, the strongest available check is to
parse the OpenStep plist back and assert the object graph is sound.

The settings assertions are not padding. Each one corresponds to a defect that
already cost a round in this project's history — a deployment target a Series 5
cannot install, a missing background mode that stops GPS the moment a wrist
drops, an absent usage string that crashes the app on first permission request.

    python3 watch/test_generate_project.py
"""

import re
import subprocess
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent

# The generator is `generate-project.py` — a hyphen, so it cannot be imported
# by name. Loading it by path keeps the script's CLI-friendly filename.
import importlib.util

_spec = importlib.util.spec_from_file_location("gen", HERE / "generate-project.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)


# --- a minimal OpenStep plist parser, enough to validate a pbxproj -----------


class ParseError(Exception):
    pass


def parse_openstep(text: str):
    """Parse the subset of OpenStep plist that a pbxproj uses.

    Not a general implementation — it handles dicts, arrays, bare words and
    quoted strings, which is everything the generator emits. Its purpose is to
    prove the output is well formed, so it is deliberately strict: anything it
    cannot account for raises rather than being skipped.
    """
    # Strip the header comment and any /* ... */ section markers.
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    pos = 0

    def skip_space():
        nonlocal pos
        while pos < len(text) and text[pos] in " \t\r\n":
            pos += 1

    def parse_value():
        nonlocal pos
        skip_space()
        if pos >= len(text):
            raise ParseError("unexpected end of input")
        char = text[pos]
        if char == "{":
            return parse_dict()
        if char == "(":
            return parse_array()
        if char == '"':
            return parse_quoted()
        return parse_bare()

    def parse_dict():
        nonlocal pos
        pos += 1                      # consume {
        out = {}
        while True:
            skip_space()
            if pos >= len(text):
                raise ParseError("unterminated dict")
            if text[pos] == "}":
                pos += 1
                return out
            key = parse_quoted() if text[pos] == '"' else parse_bare()
            skip_space()
            if text[pos] != "=":
                raise ParseError(f"expected = after key {key!r}")
            pos += 1
            out[key] = parse_value()
            skip_space()
            if pos < len(text) and text[pos] == ";":
                pos += 1

    def parse_array():
        nonlocal pos
        pos += 1                      # consume (
        out = []
        while True:
            skip_space()
            if pos >= len(text):
                raise ParseError("unterminated array")
            if text[pos] == ")":
                pos += 1
                return out
            out.append(parse_value())
            skip_space()
            if pos < len(text) and text[pos] == ",":
                pos += 1

    def parse_quoted():
        nonlocal pos
        pos += 1                      # consume opening quote
        chars = []
        while pos < len(text):
            if text[pos] == "\\":
                chars.append(text[pos + 1])
                pos += 2
                continue
            if text[pos] == '"':
                pos += 1
                return "".join(chars)
            chars.append(text[pos])
            pos += 1
        raise ParseError("unterminated string")

    def parse_bare():
        nonlocal pos
        start = pos
        while pos < len(text) and (text[pos].isalnum() or text[pos] in "_$./-"):
            pos += 1
        if start == pos:
            raise ParseError(f"unparseable at offset {pos}: {text[pos:pos+30]!r}")
        return text[start:pos]

    result = parse_value()
    skip_space()
    if pos != len(text):
        raise ParseError(f"trailing content at offset {pos}: {text[pos:pos+40]!r}")
    return result


class ProjectCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            [sys.executable, str(HERE / "generate-project.py")],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise AssertionError(f"generator failed:\n{result.stderr}")
        cls.path = HERE / "WhoopGolf.xcodeproj" / "project.pbxproj"
        cls.text = cls.path.read_text(encoding="utf-8")
        cls.tree = parse_openstep(cls.text)
        cls.objects = cls.tree["objects"]

    def objects_of(self, isa):
        return {k: v for k, v in self.objects.items() if v.get("isa") == isa}

    def settings_for(self, scope_name):
        """Build settings from the first config of a named configuration list."""
        for obj in self.objects_of("XCBuildConfiguration").values():
            settings = obj["buildSettings"]
            if scope_name in settings:
                return settings
        self.fail(f"no build configuration carrying {scope_name}")


class TestWellFormed(ProjectCase):
    def test_the_project_parses(self):
        # The whole point: a file Xcode cannot parse gives no useful error.
        self.assertIn("objects", self.tree)
        self.assertIn("rootObject", self.tree)

    def test_it_has_the_header_xcode_requires(self):
        self.assertTrue(self.text.startswith("// !$*UTF8*$!"))

    def test_the_root_object_exists_and_is_the_project(self):
        root = self.tree["rootObject"]
        self.assertIn(root, self.objects)
        self.assertEqual(self.objects[root]["isa"], "PBXProject")

    def test_every_referenced_id_is_defined(self):
        # A dangling reference is the classic way a hand-built pbxproj fails.
        defined = set(self.objects)
        referenced = set()

        def walk(node):
            if isinstance(node, dict):
                for value in node.values():
                    walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)
            elif isinstance(node, str) and re.fullmatch(r"[0-9A-F]{24}", node):
                referenced.add(node)

        walk(self.tree)
        self.assertEqual(referenced - defined, set(),
                         "referenced but never defined")

    def test_generation_is_deterministic(self):
        # Identifiers are derived from what they identify, so regenerating
        # produces an empty diff rather than a wall of reshuffled ids.
        before = self.path.read_text(encoding="utf-8")
        subprocess.run([sys.executable, str(HERE / "generate-project.py")],
                       capture_output=True, check=True)
        self.assertEqual(before, self.path.read_text(encoding="utf-8"))


class TestTargets(ProjectCase):
    def test_there_is_an_app_and_a_test_target(self):
        names = {t["name"] for t in self.objects_of("PBXNativeTarget").values()}
        self.assertEqual(names, {"WhoopGolf", "WhoopGolfTests"})

    def test_the_app_is_an_application_not_a_watchkit_extension(self):
        app = next(t for t in self.objects_of("PBXNativeTarget").values()
                   if t["name"] == "WhoopGolf")
        # Single-target watch apps (watchOS 7+) are plain applications; the old
        # app+extension pair does not build as an independent watch app.
        self.assertEqual(app["productType"], "com.apple.product-type.application")

    def test_the_tests_depend_on_the_app(self):
        tests = next(t for t in self.objects_of("PBXNativeTarget").values()
                     if t["name"] == "WhoopGolfTests")
        self.assertTrue(tests["dependencies"], "tests must depend on the app")

    def test_every_app_source_is_compiled(self):
        refs = self.objects_of("PBXFileReference")
        builds = self.objects_of("PBXBuildFile")
        app_phase = next(p for p in self.objects_of("PBXSourcesBuildPhase").values()
                         if len(p["files"]) == len(gen.APP_SOURCES))
        compiled = {refs[builds[f]["fileRef"]]["path"] for f in app_phase["files"]}
        self.assertEqual(compiled, set(gen.APP_SOURCES))

    def test_the_fixture_is_bundled_with_the_tests(self):
        # Without this the tests fatalError on launch: the JSON is not present.
        refs = self.objects_of("PBXFileReference")
        builds = self.objects_of("PBXBuildFile")
        bundled = set()
        for phase in self.objects_of("PBXResourcesBuildPhase").values():
            for f in phase["files"]:
                bundled.add(refs[builds[f]["fileRef"]]["path"])
        self.assertIn("swing_vectors.json", bundled)


class TestSettingsThatCostRounds(ProjectCase):
    """Each of these corresponds to a defect that already lost data here."""

    def test_deployment_target_installs_on_a_series_5(self):
        settings = self.settings_for("WATCHOS_DEPLOYMENT_TARGET")
        target = float(settings["WATCHOS_DEPLOYMENT_TARGET"])
        # A Series 5 tops out at watchOS 10. Xcode defaults new projects higher,
        # which builds cleanly and then refuses to install.
        self.assertLessEqual(target, 10.0)
        self.assertGreaterEqual(target, 8.5, "below the code's actual API floor")

    def test_both_background_modes_are_present(self):
        settings = self.settings_for("INFOPLIST_KEY_UIBackgroundModes")
        modes = settings["INFOPLIST_KEY_UIBackgroundModes"]
        # workout-processing keeps the motion loop alive with the wrist down;
        # location keeps GPS alive. Only the first means a round records two
        # yardages and then stops, with no error anywhere.
        self.assertIn("workout-processing", modes)
        self.assertIn("location", modes)

    def test_every_usage_string_is_set(self):
        settings = self.settings_for("INFOPLIST_KEY_NSMotionUsageDescription")
        for key in (
            "INFOPLIST_KEY_NSHealthShareUsageDescription",
            "INFOPLIST_KEY_NSHealthUpdateUsageDescription",
            "INFOPLIST_KEY_NSMotionUsageDescription",
            "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription",
            "INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription",
        ):
            # A missing usage string CRASHES the app the first time it asks for
            # that permission, which on a watch looks like it simply quit.
            self.assertIn(key, settings, f"{key} missing — app will crash on prompt")
            self.assertTrue(settings[key].strip(), f"{key} is empty")

    def test_it_is_an_independent_watch_app(self):
        settings = self.settings_for("INFOPLIST_KEY_WKApplication")
        self.assertEqual(settings["INFOPLIST_KEY_WKApplication"], "YES")
        self.assertEqual(settings["INFOPLIST_KEY_WKWatchOnly"], "YES")

    def test_it_targets_the_watch_device_family(self):
        settings = self.settings_for("TARGETED_DEVICE_FAMILY")
        self.assertEqual(settings["TARGETED_DEVICE_FAMILY"], "4")   # 4 = watch
        self.assertEqual(settings["SDKROOT"], "watchos")


class TestRefusesToGenerateGarbage(ProjectCase):
    def test_a_missing_source_aborts_rather_than_emitting_a_broken_project(self):
        import shutil
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "watch"
            shutil.copytree(HERE, fake, ignore=shutil.ignore_patterns(
                "WhoopGolf.xcodeproj", "__pycache__"))
            (fake / "WhoopGolfWatchApp" / "MotionManager.swift").unlink()
            result = subprocess.run(
                [sys.executable, str(fake / "generate-project.py")],
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("MotionManager.swift", result.stderr)
            self.assertFalse((fake / "WhoopGolf.xcodeproj").exists(),
                             "wrote a project despite missing sources")


if __name__ == "__main__":
    unittest.main(verbosity=2)
