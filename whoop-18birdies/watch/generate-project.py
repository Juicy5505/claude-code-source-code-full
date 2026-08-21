#!/usr/bin/env python3
"""Generate WhoopGolf.xcodeproj, so building the watch app is Open → Run.

WATCH.md's manual path works, but it is six steps where a mistake is silent:
create the project, drag in seven files with the right target membership, set
the deployment target, tick two capabilities, add four Info.plist keys, and
wire a test target with a bundled JSON fixture. Getting the deployment target
or the background modes wrong produces an app that builds and then either
refuses to install or stops recording GPS the moment your wrist drops.

So this writes the project instead.

    python3 watch/generate-project.py
    open watch/WhoopGolf.xcodeproj

Everything the manual steps configure is set here, including both background
modes, the four usage strings, the watchOS 9.0 floor a Series 5 needs, and a
test target with SwingDetector.swift and swing_vectors.json already wired.

Signing needs your Apple Developer Team ID, which this cannot invent. Either
set it once here:

    DEVELOPMENT_TEAM=ABCDE12345 python3 watch/generate-project.py

or leave it unset and pick your team in Xcode under the WhoopGolf target →
Signing & Capabilities. Setting it matters if you ever build from the command
line, where there is no dialog to click and the failure is the opaque
"Signing for \'WhoopGolf\' requires a development team".

Your Team ID is the ten-character code at developer.apple.com → Membership.

Regenerating is safe — it overwrites the project and nothing else. If you have
customised the project in Xcode, your changes live in the .xcodeproj and WILL
be lost, so re-run it only when you want the generated configuration back.
"""

from __future__ import annotations

import hashlib
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE / "WhoopGolf.xcodeproj"
APP_NAME = "WhoopGolf"
TEST_NAME = "WhoopGolfTests"
ENTITLEMENTS_FILE = "WhoopGolf.entitlements"

APP_SOURCES = [
    "WhoopGolfApp.swift",
    "SessionView.swift",
    "SettingsView.swift",
    "IngestSettings.swift",
    "SwingDetector.swift",
    "MotionManager.swift",
    "WorkoutManager.swift",
    "LocationManager.swift",
    "SessionModel.swift",
    "GPSSourceCheck.swift",
    "WatchRoundFaceView.swift",
    "WatchSessionTransfer.swift",
]

# The apple companion project made the watch sources depend on model types in
# apple/Shared. NOT globbed: Shared is a mixed bag — most of it is phone-side
# (PhoneYardageBridge references GolfCourseCandidate, an iOS-only type, and the
# first CI compile of a glob-everything list failed on exactly that). The list
# below mirrors the apple project's OWN watch target, which is the ground truth
# for what compiles on the watch; test_generate_project cross-checks the two
# and fails with a named file the moment they drift.
SHARED_DIR = HERE.parent / "apple" / "Shared"
SHARED_SOURCES = [
    "GolfImprover.swift",
    "SwingPathGuidance.swift",
    "WatchCoachingCue.swift",
    "WatchLiveFace.swift",
    "WatchRoundContext.swift",
    "WatchWristPreference.swift",
]

# The detector and the model, because the tests exercise both the swing maths
# and the haversine port. Nothing else — keeping the test target's source list
# minimal is what lets the tests run without a @testable import, and therefore
# without depending on how Xcode names the app module.
TEST_SOURCES = ["SwingDetector.swift", "SessionModel.swift", "IngestSettings.swift"]
TEST_FILE = "SwingDetectorTests.swift"
TEST_RESOURCE = "swing_vectors.json"


def uid(*parts: str) -> str:
    """A stable 24-char hex id, derived from what it identifies.

    Deterministic on purpose: regenerating the project produces byte-identical
    output, so `git diff` after a re-run is empty rather than a wall of
    reshuffled identifiers.
    """
    digest = hashlib.sha256("::".join(parts).encode()).hexdigest()
    return digest[:24].upper()


class Pbx:
    """Accumulates the object graph, then renders it in OpenStep plist form."""

    def __init__(self) -> None:
        self.objects: dict[str, tuple[str, dict]] = {}

    def add(self, ident: str, isa: str, fields: dict) -> str:
        self.objects[ident] = (isa, fields)
        return ident

    @staticmethod
    def _value(value) -> str:
        if isinstance(value, list):
            inner = "".join(f"\t\t\t\t{Pbx._value(v)},\n" for v in value)
            return "(\n" + inner + "\t\t\t)"
        if isinstance(value, dict):
            inner = "".join(
                f"\t\t\t\t{k} = {Pbx._value(v)};\n" for k, v in value.items()
            )
            return "{\n" + inner + "\t\t\t}"
        text = str(value)
        # Quote anything that is not a bare word. pbxproj tolerates extra
        # quoting, so erring toward quoting is safe; erring away is not.
        if text and all(c.isalnum() or c in "_$./" for c in text):
            return text
        return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

    def render(self, root: str) -> str:
        lines = [
            "// !$*UTF8*$!",
            "{",
            "\tarchiveVersion = 1;",
            "\tclasses = {",
            "\t};",
            "\tobjectVersion = 56;",
            "\tobjects = {",
        ]
        # Grouped by isa and sorted, which is how Xcode itself writes the file
        # and keeps regenerated diffs readable.
        by_isa: dict[str, list[str]] = {}
        for ident, (isa, _) in self.objects.items():
            by_isa.setdefault(isa, []).append(ident)

        for isa in sorted(by_isa):
            lines.append(f"\n/* Begin {isa} section */")
            for ident in sorted(by_isa[isa]):
                fields = self.objects[ident][1]
                lines.append(f"\t\t{ident} = {{")
                lines.append(f"\t\t\tisa = {isa};")
                for key, value in fields.items():
                    lines.append(f"\t\t\t{key} = {self._value(value)};")
                lines.append("\t\t};")
            lines.append(f"/* End {isa} section */")

        lines += [
            "\t};",
            f"\trootObject = {root};",
            "}",
            "",
        ]
        return "\n".join(lines)


def common_settings() -> dict:
    return {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "SDKROOT": "watchos",
        "SWIFT_VERSION": "5.0",
        # watchOS 9.0, not the newest. A Series 5 tops out at watchOS 10, and
        # Xcode defaults new projects higher — which builds cleanly and then
        # refuses to install with an unhelpful "does not support the minimum OS
        # version". The code's real floor is 8.5, so 9.0 is comfortable.
        "WATCHOS_DEPLOYMENT_TARGET": "9.0",
        "TARGETED_DEVICE_FAMILY": "4",
    }


def development_team() -> str:
    """The Apple Team ID to bake into the project, from $DEVELOPMENT_TEAM.

    Validated rather than trusted. A malformed value does not fail the build
    with anything mentioning the team — Xcode reports a provisioning error
    about the bundle identifier instead, and you go looking in the wrong place.
    Apple Team IDs are exactly ten uppercase alphanumerics.
    """
    team = os.environ.get("DEVELOPMENT_TEAM", "").strip()
    if not team:
        return ""
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise SystemExit(
            f"DEVELOPMENT_TEAM={team!r} is not a Team ID.\n"
            "It is exactly ten uppercase letters and digits — find yours at\n"
            "developer.apple.com → Membership, or leave it unset and pick the\n"
            "team in Xcode under Signing & Capabilities."
        )
    return team


# The two background modes, in a REAL Info.plist rather than build settings.
#
# They were INFOPLIST_KEY_WKBackgroundModes / INFOPLIST_KEY_UIBackgroundModes,
# and the macOS CI job proved Xcode drops both of them without a word: the built
# bundle came back with "no background modes at all". Neither name appears in
# Apple's published Build Settings Reference, and Xcode ignores INFOPLIST_KEY_
# names it does not recognise rather than failing.
#
# That means the ORIGINAL configuration was being dropped too, so the app has
# never carried a background mode. Both consequences are invisible until you are
# on a course: no workout-processing means watchOS suspends the app the moment
# your wrist drops and the round stops recording; no location means
# allowsBackgroundLocationUpdates = true throws
# NSInternalInconsistencyException and kills the app on the first tee.
#
# GENERATE_INFOPLIST_FILE stays YES alongside this: Xcode merges the generated
# keys (the usage strings, WKApplication, the display name) into the file named
# by INFOPLIST_FILE. build.sh verifies BOTH halves survived into the bundle,
# because that merge is exactly the kind of thing this file has already been
# wrong about once.
INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- watchOS reads this for its own background execution. An app with a live
	     HKWorkoutSession keeps running with the wrist down because of it.
	     "location" is NOT a legal value here. -->
	<key>WKBackgroundModes</key>
	<array>
		<string>workout-processing</string>
	</array>
	<!-- Core Location reads this one - the iOS-shaped key - on watchOS too.
	     Apple's watchOS 4 release notes: "To track location in the background
	     while a user is in a workout session, add UIBackgroundModes/location in
	     the Info.plist file. (29483437)". Their SpeedySloth sample ships both
	     keys, and a running workout session is not a substitute: it keeps the
	     process alive, it does not confer location authority. -->
	<key>UIBackgroundModes</key>
	<array>
		<string>location</string>
	</array>
</dict>
</plist>
"""

INFO_PLIST_PATH = "WhoopGolfWatchApp/Info.plist"


def app_settings() -> dict:
    return {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        # HealthKit. Without the entitlement the app builds and installs and then
        # cannot start a workout session, so it loses background execution on a
        # real watch while working perfectly in the simulator.
        "CODE_SIGN_ENTITLEMENTS": "WhoopGolfWatchApp/WhoopGolf.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "1.0",
        # Both, together. GENERATE_INFOPLIST_FILE supplies the usage strings and
        # WKApplication; INFOPLIST_FILE supplies the background modes that the
        # build-setting route silently dropped. Xcode merges the two.
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": INFO_PLIST_PATH,
        "PRODUCT_BUNDLE_IDENTIFIER": "com.whoopgolf.watchapp",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SKIP_INSTALL": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        # An independent watch app: it runs without an iOS companion.
        "INFOPLIST_KEY_WKApplication": "YES",
        "INFOPLIST_KEY_WKWatchOnly": "YES",
        "INFOPLIST_KEY_CFBundleDisplayName": "WhoopGolf",
        # The four usage strings. Without these the app CRASHES the first time
        # it asks for the matching permission, which on a watch looks like the
        # app simply quitting.
        "INFOPLIST_KEY_NSHealthShareUsageDescription":
            "Reads heart rate during a round.",
        "INFOPLIST_KEY_NSHealthUpdateUsageDescription":
            "Records the round as a golf workout so WHOOP can import it.",
        "INFOPLIST_KEY_NSMotionUsageDescription":
            "Detects your golf swings.",
        "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription":
            "Measures shot distances by GPS.",
        "INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription":
            "Tracks your round with the screen off.",
        # The background modes are NOT here. They live in INFO_PLIST above,
        # because Xcode silently discarded them as build settings - see the
        # comment there, and the check in build.sh that caught it.
        "CODE_SIGN_ENTITLEMENTS": f"WhoopGolfWatchApp/{ENTITLEMENTS_FILE}",
        **({"DEVELOPMENT_TEAM": development_team()} if development_team() else {}),
    }


def test_settings() -> dict:
    return {
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "1.0",
        "GENERATE_INFOPLIST_FILE": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.whoopgolf.watchapp.tests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        # The test bundle needs the same team, or `xcodebuild test` fails to
        # sign it after the app itself signed cleanly — which reads as the
        # tests being broken rather than unsigned.
        **({"DEVELOPMENT_TEAM": development_team()} if development_team() else {}),
    }


def build(pbx: Pbx) -> str:
    app_dir = "WhoopGolfWatchApp"
    test_dir = "WhoopGolfWatchAppTests"

    # --- file references -----------------------------------------------------
    file_refs: dict[str, str] = {}
    for name in APP_SOURCES:
        file_refs[name] = pbx.add(
            uid("fileref", name), "PBXFileReference",
            {
                "lastKnownFileType": "sourcecode.swift",
                "path": name,
                "sourceTree": "<group>",
            },
        )
    # Shared model sources, referenced across the package boundary. The key is
    # prefixed so a Shared file may share a basename with an app file without
    # the two colliding in this dict or in the deterministic ids.
    for name in SHARED_SOURCES:
        file_refs["shared:" + name] = pbx.add(
            uid("fileref", "shared:" + name), "PBXFileReference",
            {
                "lastKnownFileType": "sourcecode.swift",
                "name": name,
                "path": f"../apple/Shared/{name}",
                "sourceTree": "SOURCE_ROOT",
            },
        )
    file_refs[TEST_FILE] = pbx.add(
        uid("fileref", TEST_FILE), "PBXFileReference",
        {"lastKnownFileType": "sourcecode.swift", "path": TEST_FILE,
         "sourceTree": "<group>"},
    )
    file_refs[TEST_RESOURCE] = pbx.add(
        uid("fileref", TEST_RESOURCE), "PBXFileReference",
        {"lastKnownFileType": "text.json", "path": TEST_RESOURCE,
         "sourceTree": "<group>"},
    )
    file_refs[ENTITLEMENTS_FILE] = pbx.add(
        uid("fileref", ENTITLEMENTS_FILE), "PBXFileReference",
        {"lastKnownFileType": "text.plist.entitlements", "path": ENTITLEMENTS_FILE,
         "sourceTree": "<group>"},
    )

    app_product = pbx.add(
        uid("product", APP_NAME), "PBXFileReference",
        {"explicitFileType": "wrapper.application",
         "includeInIndex": 0,
         "path": f"{APP_NAME}.app",
         "sourceTree": "BUILT_PRODUCTS_DIR"},
    )
    test_product = pbx.add(
        uid("product", TEST_NAME), "PBXFileReference",
        {"explicitFileType": "wrapper.cfbundle",
         "includeInIndex": 0,
         "path": f"{TEST_NAME}.xctest",
         "sourceTree": "BUILT_PRODUCTS_DIR"},
    )

    # --- build files ---------------------------------------------------------
    app_build = [
        pbx.add(uid("build", "app", n), "PBXBuildFile", {"fileRef": file_refs[n]})
        for n in APP_SOURCES
    ] + [
        pbx.add(uid("build", "app", "shared:" + n), "PBXBuildFile",
                {"fileRef": file_refs["shared:" + n]})
        for n in SHARED_SOURCES
    ]
    test_build = [
        pbx.add(uid("build", "test", n), "PBXBuildFile", {"fileRef": file_refs[n]})
        for n in TEST_SOURCES + [TEST_FILE]
    ]
    test_resource_build = pbx.add(
        uid("build", "res", TEST_RESOURCE), "PBXBuildFile",
        {"fileRef": file_refs[TEST_RESOURCE]},
    )

    # --- groups --------------------------------------------------------------
    app_group = pbx.add(
        uid("group", "app"), "PBXGroup",
        {"children": [file_refs[n] for n in APP_SOURCES] + [file_refs[ENTITLEMENTS_FILE]],
         "path": app_dir, "sourceTree": "<group>"},
    )
    shared_group = pbx.add(
        uid("group", "shared"), "PBXGroup",
        {"children": [file_refs["shared:" + n] for n in SHARED_SOURCES],
         "name": "Shared", "sourceTree": "<group>"},
    )
    test_group = pbx.add(
        uid("group", "test"), "PBXGroup",
        {"children": [file_refs[TEST_FILE], file_refs[TEST_RESOURCE]],
         "path": test_dir, "sourceTree": "<group>"},
    )
    products_group = pbx.add(
        uid("group", "products"), "PBXGroup",
        {"children": [app_product, test_product],
         "name": "Products", "sourceTree": "<group>"},
    )
    root_group = pbx.add(
        uid("group", "root"), "PBXGroup",
        {"children": [app_group, shared_group, test_group, products_group],
         "sourceTree": "<group>"},
    )

    # --- phases --------------------------------------------------------------
    app_sources_phase = pbx.add(
        uid("phase", "appsrc"), "PBXSourcesBuildPhase",
        {"buildActionMask": 2147483647, "files": app_build, "runOnlyForDeploymentPostprocessing": 0},
    )
    app_frameworks = pbx.add(
        uid("phase", "appfw"), "PBXFrameworksBuildPhase",
        {"buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0},
    )
    app_resources = pbx.add(
        uid("phase", "appres"), "PBXResourcesBuildPhase",
        {"buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0},
    )
    test_sources_phase = pbx.add(
        uid("phase", "testsrc"), "PBXSourcesBuildPhase",
        {"buildActionMask": 2147483647, "files": test_build, "runOnlyForDeploymentPostprocessing": 0},
    )
    test_frameworks = pbx.add(
        uid("phase", "testfw"), "PBXFrameworksBuildPhase",
        {"buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0},
    )
    test_resources = pbx.add(
        uid("phase", "testres"), "PBXResourcesBuildPhase",
        {"buildActionMask": 2147483647, "files": [test_resource_build],
         "runOnlyForDeploymentPostprocessing": 0},
    )

    # --- configurations ------------------------------------------------------
    def config_list(scope: str, settings_for: dict) -> str:
        configs = []
        for name in ("Debug", "Release"):
            settings = dict(settings_for)
            if scope == "project":
                settings["ONLY_ACTIVE_ARCH"] = "YES" if name == "Debug" else "NO"
                settings["SWIFT_OPTIMIZATION_LEVEL"] = (
                    "-Onone" if name == "Debug" else "-O"
                )
                settings["ENABLE_TESTABILITY"] = "YES" if name == "Debug" else "NO"
            configs.append(pbx.add(
                uid("config", scope, name), "XCBuildConfiguration",
                {"buildSettings": settings, "name": name},
            ))
        return pbx.add(
            uid("configlist", scope), "XCConfigurationList",
            {"buildConfigurations": configs,
             "defaultConfigurationIsVisible": 0,
             "defaultConfigurationName": "Release"},
        )

    project_configs = config_list("project", common_settings())
    app_configs = config_list("app", app_settings())
    test_configs = config_list("test", test_settings())

    # --- targets -------------------------------------------------------------
    app_target = pbx.add(
        uid("target", APP_NAME), "PBXNativeTarget",
        {"buildConfigurationList": app_configs,
         "buildPhases": [app_sources_phase, app_frameworks, app_resources],
         "buildRules": [],
         "dependencies": [],
         "name": APP_NAME,
         "productName": APP_NAME,
         "productReference": app_product,
         "productType": "com.apple.product-type.application"},
    )
    dependency_proxy = pbx.add(
        uid("proxy", APP_NAME), "PBXContainerItemProxy",
        {"containerPortal": uid("project", APP_NAME),
         "proxyType": 1,
         "remoteGlobalIDString": app_target,
         "remoteInfo": APP_NAME},
    )
    test_dependency = pbx.add(
        uid("dep", TEST_NAME), "PBXTargetDependency",
        {"target": app_target, "targetProxy": dependency_proxy},
    )
    test_target = pbx.add(
        uid("target", TEST_NAME), "PBXNativeTarget",
        {"buildConfigurationList": test_configs,
         "buildPhases": [test_sources_phase, test_frameworks, test_resources],
         "buildRules": [],
         "dependencies": [test_dependency],
         "name": TEST_NAME,
         "productName": TEST_NAME,
         "productReference": test_product,
         "productType": "com.apple.product-type.bundle.unit-test"},
    )

    project = pbx.add(
        uid("project", APP_NAME), "PBXProject",
        {"attributes": {"BuildIndependentTargetsInParallel": 1,
                        "LastSwiftUpdateCheck": 1500,
                        "LastUpgradeCheck": 1500},
         "buildConfigurationList": project_configs,
         "compatibilityVersion": "Xcode 14.0",
         "developmentRegion": "en",
         "hasScannedForEncodings": 0,
         "knownRegions": ["en", "Base"],
         "mainGroup": root_group,
         "productRefGroup": products_group,
         "projectDirPath": "",
         "projectRoot": "",
         "targets": [app_target, test_target]},
    )
    return project


def validate(text: str) -> list[str]:
    """Cheap structural checks. Not a pbxproj parser — just enough to catch the
    mistakes that produce an unopenable project rather than a build error."""
    problems = []
    if text.count("{") != text.count("}"):
        problems.append(f"unbalanced braces ({text.count('{')} vs {text.count('}')})")
    if text.count("(") != text.count(")"):
        problems.append(f"unbalanced parens ({text.count('(')} vs {text.count(')')})")
    if not text.startswith("// !$*UTF8*$!"):
        problems.append("missing the UTF8 header comment Xcode requires")
    for required in ("rootObject", "objectVersion", "PBXProject", "PBXNativeTarget"):
        if required not in text:
            problems.append(f"missing {required}")
    # Every referenced id must be defined somewhere.
    import re
    defined = set(re.findall(r"^\t\t([0-9A-F]{24}) = \{", text, re.M))
    referenced = set(re.findall(r"\b([0-9A-F]{24})\b", text))
    dangling = referenced - defined
    if dangling:
        problems.append(f"{len(dangling)} referenced id(s) never defined: "
                        f"{sorted(dangling)[:3]}")
    return problems


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES"
                           buildForProfiling = "YES" buildForArchiving = "YES"
                           buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "{app}.app" BlueprintName = "{app}"
               ReferencedContainer = "container:{app}.xcodeproj" />
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = ""
               selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.PosixSpawn"
               shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target}"
               BuildableName = "{test}.xctest" BlueprintName = "{test}"
               ReferencedContainer = "container:{app}.xcodeproj" />
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug"
                 selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
                 selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
                 launchStyle = "0" useCustomWorkingDirectory = "NO"
                 ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES"
                 debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{app}.app" BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj" />
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES"
                  savedToolIdentifier = "" useCustomWorkingDirectory = "NO"
                  debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{app}.app" BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj" />
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug" />
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES" />
</Scheme>
"""

ENTITLEMENTS_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.healthkit</key>
\t<true/>
</dict>
</plist>
"""


def write_entitlements() -> None:
    path = HERE / "WhoopGolfWatchApp" / ENTITLEMENTS_FILE
    path.write_text(ENTITLEMENTS_PLIST, encoding="utf-8")


def main() -> int:
    missing = [n for n in APP_SOURCES + [TEST_FILE]
               if not (HERE / "WhoopGolfWatchApp" / n).exists()
               and not (HERE / "WhoopGolfWatchAppTests" / n).exists()]
    missing += [f"../apple/Shared/{n}" for n in SHARED_SOURCES
                if not (SHARED_DIR / n).exists()]
    if missing:
        print("Missing source files, refusing to generate a broken project:",
              file=sys.stderr)
        for name in missing:
            print(f"  {name}", file=sys.stderr)
        return 1

    write_entitlements()

    pbx = Pbx()
    root = build(pbx)
    text = pbx.render(root)

    problems = validate(text)
    if problems:
        print("Generated project failed validation:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1

    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(text, encoding="utf-8")

    # Written next to the sources, where INFOPLIST_FILE points.
    (HERE / INFO_PLIST_PATH).write_text(INFO_PLIST, encoding="utf-8")

    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / f"{APP_NAME}.xcscheme").write_text(
        SCHEME.format(app=APP_NAME, test=TEST_NAME,
                      app_target=uid("target", APP_NAME),
                      test_target=uid("target", TEST_NAME)),
        encoding="utf-8",
    )

    print(f"Wrote {PROJECT.relative_to(HERE.parent)}")
    print(f"  {len(APP_SOURCES)} app sources, {len(TEST_SOURCES) + 1} test sources")
    print(f"  watchOS 9.0 floor, both background modes, HealthKit entitlement")
    print(f"  (run ./build.sh to verify the modes survived into the built bundle)")
    print()
    print("Next:")
    print(f"  open {PROJECT.relative_to(HERE.parent)}")
    if development_team():
        print(f"  signing team {development_team()} is already set")
    else:
        print("  select the WhoopGolf target → Signing & Capabilities → pick your team")
        print("  (or re-run with DEVELOPMENT_TEAM=<your ten-character Team ID>)")
    print("  choose your watch as the destination and press Run")
    return 0


if __name__ == "__main__":
    sys.exit(main())
