#!/usr/bin/env python3
"""Generate the dependency-free Xcode project deterministically on Windows or macOS."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def uid(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:24].upper()


def quoted(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def render() -> dict[Path, str]:
    sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "DuoCue").rglob("*.swift"))
    tests = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "DuoCueTests").rglob("*.swift"))
    resources = ["DuoCue/Assets.xcassets", "DuoCue/PrivacyInfo.xcprivacy"]
    p, target, test_target = uid("project"), uid("app"), uid("tests")
    lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {};", "\tobjectVersion = 56;", "\tobjects = {"]

    def obj(key: str, value: str) -> None:
        lines.append(f"\t\t{uid(key)} = {{ {value} }};")

    def ids(values: list[str]) -> str:
        return "(" + ", ".join(uid(x) for x in values) + ("," if values else "") + ")"

    for path in sources + tests + resources + ["DuoCue/Info.plist"]:
        kind = "sourcecode.swift" if path.endswith(".swift") else "folder.assetcatalog" if path.endswith(".xcassets") else "text.plist.xml"
        obj("file:" + path, f"isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(path)}; sourceTree = SOURCE_ROOT;")
    for path in sources + tests + resources:
        obj("build:" + path, f"isa = PBXBuildFile; fileRef = {uid('file:' + path)};")

    obj("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DuoCue.app; sourceTree = BUILT_PRODUCTS_DIR;')
    if tests:
        obj("test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = DuoCueTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    obj("main-group", f"isa = PBXGroup; children = {ids(['source-group', 'resource-group'] + (['test-group'] if tests else []) + ['products-group'])}; sourceTree = \"<group>\";")
    obj("source-group", f"isa = PBXGroup; name = Sources; children = {ids(['file:' + x for x in sources])}; sourceTree = \"<group>\";")
    obj("resource-group", f"isa = PBXGroup; name = Resources; children = {ids(['file:' + x for x in resources + ['DuoCue/Info.plist']])}; sourceTree = \"<group>\";")
    obj("products-group", f"isa = PBXGroup; name = Products; children = {ids(['product'] + (['test-product'] if tests else []))}; sourceTree = \"<group>\";")
    if tests:
        obj("test-group", f"isa = PBXGroup; name = Tests; children = {ids(['file:' + x for x in tests])}; sourceTree = \"<group>\";")

    for name, kind, files in [("sources-phase", "PBXSourcesBuildPhase", sources), ("resources-phase", "PBXResourcesBuildPhase", resources), ("frameworks-phase", "PBXFrameworksBuildPhase", [])]:
        obj(name, f"isa = {kind}; buildActionMask = 2147483647; files = {ids(['build:' + x for x in files])}; runOnlyForDeploymentPostprocessing = 0;")
    obj("app", f"isa = PBXNativeTarget; buildConfigurationList = {uid('app-configs')}; buildPhases = {ids(['sources-phase', 'frameworks-phase', 'resources-phase'])}; buildRules = (); dependencies = (); name = DuoCue; productName = DuoCue; productReference = {uid('product')}; productType = \"com.apple.product-type.application\";")
    if tests:
        obj("test-sources-phase", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {ids(['build:' + x for x in tests])}; runOnlyForDeploymentPostprocessing = 0;")
        obj("test-frameworks-phase", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
        obj("test-proxy", f"isa = PBXContainerItemProxy; containerPortal = {p}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = DuoCue;")
        obj("test-dependency", f"isa = PBXTargetDependency; target = {target}; targetProxy = {uid('test-proxy')};")
        obj("tests", f"isa = PBXNativeTarget; buildConfigurationList = {uid('test-configs')}; buildPhases = {ids(['test-sources-phase', 'test-frameworks-phase'])}; buildRules = (); dependencies = {ids(['test-dependency'])}; name = DuoCueTests; productName = DuoCueTests; productReference = {uid('test-product')}; productType = \"com.apple.product-type.bundle.unit-test\";")

    project_base = "ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; CLANG_WARN_DOCUMENTATION_COMMENTS = YES; COPY_PHASE_STRIP = NO; ENABLE_STRICT_OBJC_MSGSEND = YES; GCC_C_LANGUAGE_STANDARD = gnu17; GCC_NO_COMMON_BLOCKS = YES; IPHONEOS_DEPLOYMENT_TARGET = 27.1; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; SWIFT_STRICT_CONCURRENCY = minimal;"
    app_base = 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; DEVELOPMENT_TEAM = ""; ENABLE_PREVIEWS = YES; ENABLE_USER_SCRIPT_SANDBOXING = YES; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = DuoCue/Info.plist; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks"; MARKETING_VERSION = 0.1.0; PRODUCT_BUNDLE_IDENTIFIER = com.reluctant2828.duocue; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; SWIFT_EMIT_LOC_STRINGS = YES; TARGETED_DEVICE_FAMILY = 1;'
    test_base = 'BUNDLE_LOADER = "$(TEST_HOST)"; CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.reluctant2828.duocue.tests; PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/DuoCue.app/DuoCue";'
    for name, base in [("project", project_base), ("app", app_base)] + ([("test", test_base)] if tests else []):
        for mode in ["Debug", "Release"]:
            extra = ""
            if name == "project":
                extra = ' DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; GCC_OPTIMIZATION_LEVEL = 0; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ONLY_ACTIVE_ARCH = YES;' if mode == "Debug" else ' DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O"; VALIDATE_PRODUCT = YES;'
            obj(f"{name}-{mode}", f"isa = XCBuildConfiguration; buildSettings = {{ {base}{extra} }}; name = {mode};")
        obj(name + "-configs", f"isa = XCConfigurationList; buildConfigurations = {ids([name + '-Debug', name + '-Release'])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    attributes = f"{target} = {{ CreatedOnToolsVersion = 27.1; }};"
    if tests:
        attributes += f" {test_target} = {{ CreatedOnToolsVersion = 27.1; TestTargetID = {target}; }};"
    obj("project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2710; TargetAttributes = {{ {attributes} }}; }}; buildConfigurationList = {uid('project-configs')}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = \"zh-Hans\"; hasScannedForEncodings = 0; knownRegions = (\"zh-Hans\", en, Base); mainGroup = {uid('main-group')}; productRefGroup = {uid('products-group')}; projectDirPath = \"\"; projectRoot = \"\"; targets = {ids(['app'] + (['tests'] if tests else []))};")
    lines.extend(["\t};", f"\trootObject = {p};", "}", ""])

    def ref(identifier: str, product: str, target_name: str) -> str:
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{product}" BlueprintName="{target_name}" ReferencedContainer="container:DuoCue.xcodeproj"/>'

    app_ref = ref(target, "DuoCue.app", "DuoCue")
    testables = f'<TestableReference skipped="NO">{ref(test_target, "DuoCueTests.xctest", "DuoCueTests")}</TestableReference>' if tests else ""
    test_build_entry = f'<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{ref(test_target, "DuoCueTests.xctest", "DuoCueTests")}</BuildActionEntry>' if tests else ""
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>{test_build_entry}</BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{testables}</Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    workspace = '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"/></Workspace>\n'
    return {ROOT / "DuoCue.xcodeproj/project.pbxproj": "\n".join(lines), ROOT / "DuoCue.xcodeproj/xcshareddata/xcschemes/DuoCue.xcscheme": scheme, ROOT / "DuoCue.xcodeproj/project.xcworkspace/contents.xcworkspacedata": workspace}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Read-only: fail if the checked-in project is stale")
    args = parser.parse_args()
    expected = render()
    stale = []
    for path, content in expected.items():
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                stale.append(path.relative_to(ROOT).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if stale:
        print("Project is stale; run python scripts/generate_project.py:\n" + "\n".join(stale))
        return 1
    print("Xcode project matches current sources." if args.check else "Generated DuoCue.xcodeproj.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
