#!/usr/bin/env python3
"""Generate WhoopSwingSidecar.xcodeproj for the WHOOP IMU sidecar iOS app."""

from __future__ import annotations

import hashlib
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE / "WhoopSwingSidecar.xcodeproj"
APP_NAME = "WhoopSwingSidecar"
TEST_NAME = "WhoopSwingSidecarTests"
ENTITLEMENTS_FILE = "WhoopSwingSidecar.entitlements"
APP_DIR = "WhoopSwingSidecar"
TEST_DIR = "WhoopSwingSidecarTests"

APP_SOURCES = [
    "WhoopSwingSidecarApp.swift",
    "ContentView.swift",
    "SidecarSessionView.swift",
    "SettingsView.swift",
    "IngestSettings.swift",
    "SwingDetector.swift",
    "SessionModel.swift",
    "IMUMotionManager.swift",
    "PhoneMotionManager.swift",
    "BLE/WhoopFraming.swift",
    "BLE/WhoopUUIDs.swift",
    "BLE/WhoopCommands.swift",
    "BLE/WhoopIMUDecoder.swift",
    "BLE/WhoopBLEManager.swift",
]

TEST_COMPILE = [
    "SwingDetector.swift",
    "SessionModel.swift",
    "IngestSettings.swift",
    "BLE/WhoopFraming.swift",
    "BLE/WhoopIMUDecoder.swift",
]
TEST_FILES = ["SwingDetectorTests.swift", "WhoopFramingTests.swift"]
TEST_RESOURCE = "swing_vectors.json"


def uid(*parts: str) -> str:
    return hashlib.sha256("::".join(parts).encode()).hexdigest()[:24].upper()


class Pbx:
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
        if text and all(c.isalnum() or c in "_$./" for c in text):
            return text
        return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

    def render(self, root: str) -> str:
        lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};",
                 "\tobjectVersion = 56;", "\tobjects = {"]
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
        lines += ["\t};", f"\trootObject = {root};", "}", ""]
        return "\n".join(lines)


def common_settings() -> dict:
    return {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "TARGETED_DEVICE_FAMILY": "1",
    }


def development_team() -> str:
    team = os.environ.get("DEVELOPMENT_TEAM", "").strip()
    if team and not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise SystemExit(f"DEVELOPMENT_TEAM={team!r} is not a valid Team ID")
    return team


INFO_PLIST = Path(APP_DIR) / "Info.plist"


def app_settings() -> dict:
    s = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_ENTITLEMENTS": f"{APP_DIR}/{ENTITLEMENTS_FILE}",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "1.0",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": str(INFO_PLIST),
        "PRODUCT_BUNDLE_IDENTIFIER": "com.whoopgolf.sidecar",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "INFOPLIST_KEY_CFBundleDisplayName": "WHOOP Swing",
        "INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription":
            "Connects to your WHOOP strap for swing detection.",
        "INFOPLIST_KEY_NSBluetoothPeripheralUsageDescription":
            "Connects to your WHOOP strap for swing detection.",
        "INFOPLIST_KEY_NSMotionUsageDescription": "Fallback swing detection from phone motion.",
        "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription":
            "Measures shot distances by GPS.",
        "INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription":
            "Tracks your round with the screen off.",
    }
    if development_team():
        s["DEVELOPMENT_TEAM"] = development_team()
    return s


def test_settings() -> dict:
    s = {
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "1.0",
        "GENERATE_INFOPLIST_FILE": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.whoopgolf.sidecar.tests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
    }
    if development_team():
        s["DEVELOPMENT_TEAM"] = development_team()
    return s


def build(pbx: Pbx) -> tuple[str, str, str]:
    file_refs: dict[str, str] = {}

    def swift_ref(name: str, path: str) -> str:
        return pbx.add(uid("fileref", name), "PBXFileReference",
                       {"lastKnownFileType": "sourcecode.swift", "path": path,
                        "sourceTree": "<group>"})

    for name in APP_SOURCES:
        file_refs[name] = swift_ref(name, name)
    file_refs[ENTITLEMENTS_FILE] = pbx.add(
        uid("fileref", ENTITLEMENTS_FILE), "PBXFileReference",
        {"lastKnownFileType": "text.plist.entitlements", "path": ENTITLEMENTS_FILE,
         "sourceTree": "<group>"})
    for name in TEST_FILES:
        file_refs[name] = swift_ref(name, name)
    file_refs[TEST_RESOURCE] = pbx.add(
        uid("fileref", TEST_RESOURCE), "PBXFileReference",
        {"lastKnownFileType": "text.json", "path": TEST_RESOURCE, "sourceTree": "<group>"})

    app_product = pbx.add(uid("product", APP_NAME), "PBXFileReference",
                          {"explicitFileType": "wrapper.application", "includeInIndex": 0,
                           "path": f"{APP_NAME}.app", "sourceTree": "BUILT_PRODUCTS_DIR"})
    test_product = pbx.add(uid("product", TEST_NAME), "PBXFileReference",
                           {"explicitFileType": "wrapper.cfbundle", "includeInIndex": 0,
                            "path": f"{TEST_NAME}.xctest", "sourceTree": "BUILT_PRODUCTS_DIR"})

    app_build = [pbx.add(uid("b", "a", n), "PBXBuildFile", {"fileRef": file_refs[n]})
                 for n in APP_SOURCES]
    test_build = [pbx.add(uid("b", "t", n), "PBXBuildFile", {"fileRef": file_refs[n]})
                  for n in TEST_COMPILE + TEST_FILES]
    test_res = pbx.add(uid("b", "r", TEST_RESOURCE), "PBXBuildFile",
                       {"fileRef": file_refs[TEST_RESOURCE]})

    app_group = pbx.add(uid("g", "app"), "PBXGroup",
                        {"children": [file_refs[n] for n in APP_SOURCES]
                         + [file_refs[ENTITLEMENTS_FILE]],
                         "path": APP_DIR, "sourceTree": "<group>"})
    test_group = pbx.add(uid("g", "test"), "PBXGroup",
                         {"children": [file_refs[n] for n in TEST_FILES + [TEST_RESOURCE]],
                          "path": TEST_DIR, "sourceTree": "<group>"})
    products = pbx.add(uid("g", "prod"), "PBXGroup",
                       {"children": [app_product, test_product], "name": "Products",
                        "sourceTree": "<group>"})
    root = pbx.add(uid("g", "root"), "PBXGroup",
                   {"children": [app_group, test_group, products], "sourceTree": "<group>"})

    def phases(name: str, files: list[str], resources: list[str] | None = None):
        return (
            pbx.add(uid("p", name, "src"), "PBXSourcesBuildPhase",
                    {"buildActionMask": 2147483647, "files": files,
                     "runOnlyForDeploymentPostprocessing": 0}),
            pbx.add(uid("p", name, "fw"), "PBXFrameworksBuildPhase",
                    {"buildActionMask": 2147483647, "files": [],
                     "runOnlyForDeploymentPostprocessing": 0}),
            pbx.add(uid("p", name, "res"), "PBXResourcesBuildPhase",
                    {"buildActionMask": 2147483647,
                     "files": resources or [], "runOnlyForDeploymentPostprocessing": 0}),
        )

    app_phases = phases("app", app_build)
    test_phases = phases("test", test_build, [test_res])

    def configs(scope: str, base: dict) -> str:
        cfgs = []
        for n in ("Debug", "Release"):
            st = dict(base)
            if scope == "project":
                st["ONLY_ACTIVE_ARCH"] = "YES" if n == "Debug" else "NO"
                st["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if n == "Debug" else "-O"
                st["ENABLE_TESTABILITY"] = "YES" if n == "Debug" else "NO"
            cfgs.append(pbx.add(uid("c", scope, n), "XCBuildConfiguration",
                                {"buildSettings": st, "name": n}))
        return pbx.add(uid("cl", scope), "XCConfigurationList",
                       {"buildConfigurations": cfgs, "defaultConfigurationIsVisible": 0,
                        "defaultConfigurationName": "Release"})

    proj_cf = configs("project", common_settings())
    app_cf = configs("app", app_settings())
    test_cf = configs("test", test_settings())

    app_target = pbx.add(uid("t", APP_NAME), "PBXNativeTarget",
                         {"buildConfigurationList": app_cf,
                          "buildPhases": list(app_phases), "buildRules": [],
                          "dependencies": [], "name": APP_NAME, "productName": APP_NAME,
                          "productReference": app_product,
                          "productType": "com.apple.product-type.application"})
    proxy = pbx.add(uid("px", APP_NAME), "PBXContainerItemProxy",
                    {"containerPortal": uid("proj", APP_NAME), "proxyType": 1,
                     "remoteGlobalIDString": app_target, "remoteInfo": APP_NAME})
    dep = pbx.add(uid("d", TEST_NAME), "PBXTargetDependency",
                  {"target": app_target, "targetProxy": proxy})
    test_target = pbx.add(uid("t", TEST_NAME), "PBXNativeTarget",
                          {"buildConfigurationList": test_cf,
                           "buildPhases": list(test_phases), "buildRules": [],
                           "dependencies": [dep], "name": TEST_NAME,
                           "productName": TEST_NAME, "productReference": test_product,
                           "productType": "com.apple.product-type.bundle.unit-test"})
    project = pbx.add(uid("proj", APP_NAME), "PBXProject",
                        {"attributes": {"BuildIndependentTargetsInParallel": 1,
                                        "LastSwiftUpdateCheck": 1500,
                                        "LastUpgradeCheck": 1500},
                         "buildConfigurationList": proj_cf,
                         "compatibilityVersion": "Xcode 14.0",
                         "developmentRegion": "en", "hasScannedForEncodings": 0,
                         "knownRegions": ["en", "Base"], "mainGroup": root,
                         "productRefGroup": products, "projectDirPath": "",
                         "projectRoot": "", "targets": [app_target, test_target]})
    return project, app_target, test_target


def main() -> int:
    pbx = Pbx()
    project, app_target, test_target = build(pbx)
    text = pbx.render(project)
    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(text)
    scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / f"{APP_NAME}.xcscheme").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
   <BuildAction buildImplicitDependencies="YES" parallelizeBuildables="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForAnalyzing="YES" buildForArchiving="YES"
            buildForProfiling="YES" buildForRunning="YES" buildForTesting="YES">
            <BuildableReference BuildableIdentifier="primary"
               BlueprintIdentifier="{app_target}"
               BuildableName="{APP_NAME}.app" BlueprintName="{APP_NAME}"
               ReferencedContainer="container:{APP_NAME}.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug">
      <Testables>
         <TestableReference skipped="NO">
            <BuildableReference BuildableIdentifier="primary"
               BlueprintIdentifier="{test_target}"
               BuildableName="{TEST_NAME}.xctest" BlueprintName="{TEST_NAME}"
               ReferencedContainer="container:{APP_NAME}.xcodeproj"/>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary"
            BlueprintIdentifier="{app_target}"
            BuildableName="{APP_NAME}.app" BlueprintName="{APP_NAME}"
            ReferencedContainer="container:{APP_NAME}.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>
""")
    print(f"Wrote {PROJECT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
