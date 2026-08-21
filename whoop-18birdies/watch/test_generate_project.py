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

import os
import re
import shutil
import subprocess
import sys
import tempfile
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


def env_without_team() -> dict:
    env = dict(os.environ)
    env.pop("DEVELOPMENT_TEAM", None)
    return env


def generate_into_copy(env: dict):
    """Run the generator against a throwaway copy of watch/ and return
    (result, project_dir). Keeps a failing case from clobbering the real
    project, and lets a test assert that nothing was written at all."""
    tmp = tempfile.mkdtemp()
    fake = Path(tmp) / "watch"
    shutil.copytree(HERE, fake,
                    ignore=shutil.ignore_patterns("WhoopGolf.xcodeproj", "__pycache__"))
    # The generator now reaches across the package boundary for apple/Shared,
    # and refuses to emit a project when that directory is absent (its sources
    # would reference types that can never compile). The copy must therefore
    # look like the real checkout: watch/ and apple/Shared/ side by side.
    shutil.copytree(HERE.parent / "apple" / "Shared", Path(tmp) / "apple" / "Shared",
                    ignore=shutil.ignore_patterns("graphify-out", "__pycache__"))
    result = subprocess.run(
        [sys.executable, str(fake / "generate-project.py")],
        capture_output=True, text=True, env=env,
    )
    return result, fake / "WhoopGolf.xcodeproj"


class ProjectCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # A clean environment, deliberately. $DEVELOPMENT_TEAM changes what the
        # generator emits, so inheriting it would make every assertion below
        # depend on whoever happens to be running the suite.
        result = subprocess.run(
            [sys.executable, str(HERE / "generate-project.py")],
            capture_output=True, text=True, env=env_without_team(),
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
        # The app phase is the LARGER sources phase (app + shared vs the tests).
        # Matching on an exact count silently broke the moment the phase grew.
        app_phase = max(self.objects_of("PBXSourcesBuildPhase").values(),
                        key=lambda p: len(p["files"]))
        compiled = {refs[builds[f]["fileRef"]]["path"] for f in app_phase["files"]}
        expected = set(gen.APP_SOURCES) | {
            f"../apple/Shared/{n}" for n in gen.SHARED_SOURCES
        }
        self.assertEqual(compiled, expected)

    def test_shared_sources_are_globbed_not_listed(self):
        # WatchRoundFaceView/WatchSessionTransfer got left out of APP_SOURCES by
        # hand; the Shared list must not be able to fail the same way. It comes
        # from the directory itself, so a new Shared file is picked up on the
        # next generate — and there must be a meaningful number of them.
        on_disk = {f.name for f in (HERE.parent / "apple" / "Shared").glob("*.swift")}
        self.assertEqual(set(gen.SHARED_SOURCES), on_disk)
        self.assertGreater(len(gen.SHARED_SOURCES), 10)

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

    def test_the_background_modes_live_in_a_real_plist_not_build_settings(self):
        # Proven by CI, not assumed: INFOPLIST_KEY_WKBackgroundModes and
        # INFOPLIST_KEY_UIBackgroundModes are not names Xcode recognises, and it
        # discards unrecognised INFOPLIST_KEY_ settings without a warning. The
        # macOS job built the app and found "no background modes at all" in the
        # bundle. So they must not come back as build settings.
        for scope in self.objects_of("XCBuildConfiguration").values():
            for key in scope["buildSettings"]:
                self.assertNotIn(
                    "BackgroundModes", key,
                    "background modes as a build setting are silently dropped",
                )

    def test_the_app_target_points_at_that_plist(self):
        settings = self.settings_for("INFOPLIST_FILE")
        self.assertEqual(settings["INFOPLIST_FILE"], "WhoopGolfWatchApp/Info.plist")

    def test_generate_also_writes_the_plist(self):
        # A dangling INFOPLIST_FILE fails the build, which is at least loud —
        # but only if the generator actually emits the file it names.
        self.assertTrue((HERE / "WhoopGolfWatchApp" / "Info.plist").is_file())

    def test_the_plist_carries_each_mode_in_the_key_that_reads_it(self):
        import plistlib

        with open(HERE / "WhoopGolfWatchApp" / "Info.plist", "rb") as handle:
            plist = plistlib.load(handle)

        # watchOS reads WKBackgroundModes for background execution. Without
        # workout-processing the app is suspended the moment the wrist drops and
        # the round stops recording, with no error.
        self.assertIn("workout-processing", plist["WKBackgroundModes"])
        # Core Location reads UIBackgroundModes, on watchOS too. Without
        # location, allowsBackgroundLocationUpdates = true throws
        # NSInternalInconsistencyException and kills the app on the first tee.
        self.assertIn("location", plist["UIBackgroundModes"])

        # And not swapped: "location" is not a legal WKBackgroundModes value,
        # and workout-processing in UIBackgroundModes is what the old broken
        # configuration did.
        self.assertNotIn("location", plist["WKBackgroundModes"])
        self.assertNotIn("workout-processing", plist["UIBackgroundModes"])

    def test_generate_infoplist_file_stays_on_so_the_usage_strings_still_merge(self):
        # The plist above carries only the background modes. The usage strings
        # and WKApplication come from INFOPLIST_KEY_ settings, which Xcode merges
        # into the named file — turning this off would ship an app that quits the
        # first time it asks for HealthKit access.
        settings = self.settings_for("INFOPLIST_FILE")
        self.assertEqual(settings["GENERATE_INFOPLIST_FILE"], "YES")
        self.assertIn("INFOPLIST_KEY_NSHealthShareUsageDescription", settings)

    def test_the_build_script_verifies_the_modes_survived_into_the_bundle(self):
        # These two INFOPLIST_KEY_ settings are not in Apple's published Build
        # Settings Reference, and Xcode silently ignores INFOPLIST_KEY_ names it
        # does not recognise. Setting them correctly here is necessary and not
        # sufficient, so build.sh reads them back out of the built bundle — this
        # test pins that the check exists rather than being quietly dropped.
        script = (HERE / "build.sh").read_text(encoding="utf-8")
        self.assertIn("verify_info_plist", script)
        self.assertIn("WKBackgroundModes", script)
        self.assertIn("plutil", script)

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

    def test_healthkit_entitlement_is_wired(self):
        settings = self.settings_for("CODE_SIGN_ENTITLEMENTS")
        self.assertIn("CODE_SIGN_ENTITLEMENTS", settings)
        self.assertTrue(settings["CODE_SIGN_ENTITLEMENTS"].endswith(".entitlements"))
        entitlements = HERE / "WhoopGolfWatchApp" / gen.ENTITLEMENTS_FILE
        self.assertTrue(entitlements.is_file(), "entitlements file missing on disk")
        self.assertIn("com.apple.developer.healthkit", entitlements.read_text())

    def test_it_targets_the_watch_device_family(self):
        settings = self.settings_for("TARGETED_DEVICE_FAMILY")
        self.assertEqual(settings["TARGETED_DEVICE_FAMILY"], "4")   # 4 = watch
        self.assertEqual(settings["SDKROOT"], "watchos")


class TestNothingIsSilentlyLeftOut(ProjectCase):
    """A Swift file on disk that the generator does not know about.

    The project is GENERATED, and build.sh regenerates it before every build —
    so hand-editing WhoopGolf.xcodeproj to add a source does nothing: the edit is
    overwritten and the file is never compiled. That happened: IngestSettings.swift
    and SettingsView.swift were added to the project by hand, the regeneration
    discarded them, and the build failed with "cannot find 'IngestSettings' in
    scope" — a confusing error a long way from its cause.

    This makes the same mistake fail here, on ubuntu, in a tenth of a second,
    with a message that names the file and the fix.
    """

    def test_every_swift_file_in_the_app_directory_is_compiled(self):
        on_disk = {
            path.name
            for path in (HERE / "WhoopGolfWatchApp").glob("*.swift")
        }
        declared = set(gen.APP_SOURCES)
        missing = sorted(on_disk - declared)
        self.assertEqual(
            missing, [],
            "these Swift files exist but are not in APP_SOURCES, so they will "
            "never be compiled — add them to generate-project.py, not to the "
            ".xcodeproj (which is regenerated)",
        )

    def test_every_declared_source_exists(self):
        missing = [
            name for name in gen.APP_SOURCES
            if not (HERE / "WhoopGolfWatchApp" / name).is_file()
        ]
        self.assertEqual(missing, [], "APP_SOURCES names a file that is not there")

    def test_the_healthkit_entitlement_is_wired_in(self):
        # Without it the app builds and installs and then cannot start a workout
        # session — so it loses background execution on a real watch while
        # working perfectly in the simulator, which is where CI runs.
        settings = self.settings_for("CODE_SIGN_ENTITLEMENTS")
        self.assertEqual(
            settings["CODE_SIGN_ENTITLEMENTS"],
            "WhoopGolfWatchApp/WhoopGolf.entitlements",
        )
        self.assertTrue(
            (HERE / "WhoopGolfWatchApp" / "WhoopGolf.entitlements").is_file()
        )


class TestSigning(ProjectCase):
    """Signing is where a generated project fails for a reason nobody can see.

    "Signing for 'WhoopGolf' requires a development team" stops the build
    before a single line of Swift is compiled, and from Xcode it is one dropdown
    away. From `xcodebuild` there is no dropdown, so the Team ID has to be in
    the project — which is what $DEVELOPMENT_TEAM is for.
    """

    def test_no_team_is_baked_in_by_default(self):
        # The committed project must be team-free: a stranger's Team ID in it
        # fails to sign with an error that names provisioning, not the team.
        self.assertNotIn("DEVELOPMENT_TEAM", self.text)

    def test_a_team_id_reaches_both_the_app_and_the_tests(self):
        env = env_without_team()
        env["DEVELOPMENT_TEAM"] = "ABCDE12345"
        result, project = generate_into_copy(env)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = (project / "project.pbxproj").read_text(encoding="utf-8")
        tree = parse_openstep(text)
        scopes = [
            obj["buildSettings"]
            for obj in tree["objects"].values()
            if obj.get("isa") == "XCBuildConfiguration"
            and "PRODUCT_BUNDLE_IDENTIFIER" in obj["buildSettings"]
        ]
        self.assertTrue(scopes, "no target-level configurations found")
        for settings in scopes:
            # Both the app and the test bundle. Signing only the app makes
            # `xcodebuild test` fail after `xcodebuild build` succeeded, which
            # reads as the tests being broken rather than unsigned.
            self.assertEqual(settings.get("DEVELOPMENT_TEAM"), "ABCDE12345",
                             settings.get("PRODUCT_BUNDLE_IDENTIFIER"))

    def test_a_malformed_team_id_aborts_and_writes_nothing(self):
        env = env_without_team()
        env["DEVELOPMENT_TEAM"] = "my-team"
        result, project = generate_into_copy(env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Team ID", result.stderr)
        self.assertFalse(project.exists(),
                         "wrote a project that could never sign")


class TestRefusesToGenerateGarbage(ProjectCase):
    def test_a_missing_source_aborts_rather_than_emitting_a_broken_project(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "watch"
            shutil.copytree(HERE, fake, ignore=shutil.ignore_patterns(
                "WhoopGolf.xcodeproj", "__pycache__"))
            (fake / "WhoopGolfWatchApp" / "MotionManager.swift").unlink()
            result = subprocess.run(
                [sys.executable, str(fake / "generate-project.py")],
                capture_output=True, text=True, env=env_without_team(),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("MotionManager.swift", result.stderr)
            self.assertFalse((fake / "WhoopGolf.xcodeproj").exists(),
                             "wrote a project despite missing sources")


if __name__ == "__main__":
    unittest.main(verbosity=2)
