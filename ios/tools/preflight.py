#!/usr/bin/env python3
"""Pre-flight checks for the Xcode project, run BEFORE `xcodegen generate` (works on Linux or macOS).

    python3 ios/tools/preflight.py

It cannot run XcodeGen or Xcode. What it does is check the things that have gone wrong, or could, between
project.yml, the asset catalogs, the privacy manifest and the Swift sources:

  1. project.yml: structure, deployment target, Swift 5 mode and the concurrency pins, files it points at,
     the package product, the signing xcconfig, YAML YES/NO turned into booleans, bundle id precedence trap.
  2. Which files XcodeGen will put in Compile Sources and which in Copy Bundle Resources (simulated).
  3. Asset catalogs: Contents.json files, the app icon (1024 px PNG, no alpha channel), accent and launch colours.
  4. Privacy manifest: valid property list, known categories and reason codes, and every required-reason API the
     Swift sources use (app + NexaFixCore) is declared.
  5. Info.plist keys from project.yml against the frameworks the sources use (camera, motion, photos, ...).
  6. NexaFixCore/Package.swift: platforms not newer than the app, no dependencies or resources.
  7. .gitignore: generated files ignored, source files not.

Exit status 1 if any FAIL. WARN lines need a human look. Needs only Python 3; PyYAML is used when installed.
"""
import fnmatch
import json
import plistlib
import re
import struct
import subprocess
import sys
from pathlib import Path

IOS = Path(__file__).resolve().parent.parent
REPO = IOS.parent
fails, warns = [], []


def ok(msg):
    print(f"  ok    {msg}")


def warn(msg):
    warns.append(msg)
    print(f"  WARN  {msg}")


def fail(msg):
    fails.append(msg)
    print(f"  FAIL  {msg}")


def section(title):
    print(f"\n== {title}")


def swift_files(*roots):
    for root in roots:
        yield from sorted(Path(root).rglob("*.swift"))


def strip_comments(text):
    """Drop // and /* */ comments (keeps line numbers); good enough for API greps."""
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


# ---------------------------------------------------------------- 1. project.yml
section("project.yml")
spec = None
try:
    import yaml  # type: ignore
    spec = yaml.safe_load((IOS / "project.yml").read_text())
    ok("parses as YAML")
except ImportError:
    warn("PyYAML not installed: project.yml structure checks skipped (pip install pyyaml)")
except Exception as e:  # noqa: BLE001
    fail(f"project.yml does not parse: {e}")

target = {}
info = {}
tsettings = {}
if spec:
    known_top = {"name", "options", "settings", "packages", "targets", "schemes", "include", "configs",
                 "configFiles", "fileGroups", "settingGroups", "targetTemplates", "aggregateTargets",
                 "schemeTemplates", "attributes"}
    for k in spec:
        if k not in known_top:
            warn(f"unknown top-level key '{k}' (typo? compare with XcodeGen's project spec)")
    opts = spec.get("options", {})
    if opts.get("deploymentTarget", {}).get("iOS") == "17.0":
        ok("options.deploymentTarget.iOS = 17.0")
    else:
        fail("options.deploymentTarget.iOS must be \"17.0\" (quoted: YAML reads 17.0 as a number)")
    base = spec.get("settings", {}).get("base", {})
    for key, want in [("SWIFT_VERSION", "5.0"), ("SWIFT_STRICT_CONCURRENCY", "minimal"),
                      ("SWIFT_DEFAULT_ACTOR_ISOLATION", "nonisolated"), ("SWIFT_APPROACHABLE_CONCURRENCY", "NO"),
                      ("IPHONEOS_DEPLOYMENT_TARGET", "17.0")]:
        if base.get(key) == want:
            ok(f"{key} = {want}")
        else:
            fail(f"settings.base.{key} should be {want!r}, is {base.get(key)!r}")
    targets = spec.get("targets", {})
    if list(targets) != ["NexaFixScan"]:
        warn(f"expected exactly one target 'NexaFixScan', found {list(targets)}")
    target = targets.get("NexaFixScan", {})
    info = target.get("info", {})
    tsettings = target.get("settings", {}).get("base", {})
    # YAML 1.1 turns bare YES/NO/on/off into booleans; a bool where XcodeGen expects a build setting string is a trap.
    for where, d in [("settings.base", base), ("target settings.base", tsettings)]:
        for k, v in d.items():
            if isinstance(v, bool):
                fail(f"{where}.{k} is a YAML boolean; quote it (\"YES\" / \"NO\")")
    # sources
    for src in target.get("sources", []):
        p = src["path"] if isinstance(src, dict) else src
        if (IOS / p).is_dir():
            ok(f"source path {p}/ exists")
        else:
            fail(f"source path {p} does not exist (relative to ios/)")
    # package + product
    for name, pk in spec.get("packages", {}).items():
        pdir = IOS / pk.get("path", "")
        if (pdir / "Package.swift").is_file():
            ok(f"package {name}: {pk['path']}/Package.swift exists")
        else:
            fail(f"package {name}: no Package.swift at {pdir}")
    manifest = (IOS / "NexaFixCore/Package.swift").read_text() if (IOS / "NexaFixCore/Package.swift").exists() else ""
    for dep in target.get("dependencies", []):
        if "package" in dep:
            product = dep.get("product", dep["package"])
            if re.search(r'\.library\(\s*name:\s*"%s"' % re.escape(product), manifest):
                ok(f"dependency {dep['package']}: library product '{product}' exists in Package.swift")
            else:
                fail(f"dependency {dep['package']}: no .library(name: \"{product}\") in Package.swift")
    # config files
    cfg = target.get("configFiles", {})
    for config in ("Debug", "Release"):
        f = cfg.get(config)
        if f and (IOS / f).is_file():
            ok(f"configFiles.{config} -> {f} exists")
        elif f:
            fail(f"configFiles.{config} -> {f} is missing (XcodeGen refuses a missing config file)")
        else:
            warn(f"no configFiles entry for {config}")
    xcconfig_text = ""
    for f in set(cfg.values()):
        if (IOS / f).is_file():
            xcconfig_text += (IOS / f).read_text()
    if "PRODUCT_BUNDLE_IDENTIFIER" in tsettings and "PRODUCT_BUNDLE_IDENTIFIER" in xcconfig_text:
        fail("PRODUCT_BUNDLE_IDENTIFIER is set both in target settings and in the xcconfig; the target setting wins "
             "and Local.xcconfig could never change it")
    elif "PRODUCT_BUNDLE_IDENTIFIER" in xcconfig_text or "PRODUCT_BUNDLE_IDENTIFIER" in tsettings:
        ok("PRODUCT_BUNDLE_IDENTIFIER is defined in exactly one place")
    else:
        fail("PRODUCT_BUNDLE_IDENTIFIER is defined nowhere")
    if "bundleIdPrefix" in opts:
        warn("options.bundleIdPrefix is set: XcodeGen may then add its own PRODUCT_BUNDLE_IDENTIFIER to the target")
    if re.search(r'^#include\? "Local\.xcconfig"\s*$', xcconfig_text, re.M):
        ok("Signing.xcconfig includes the optional Local.xcconfig")
        last = [l for l in xcconfig_text.splitlines() if l.strip() and not l.strip().startswith("//")][-1]
        if not last.startswith("#include?"):
            fail("the #include? line must be the LAST statement in Signing.xcconfig so Local.xcconfig overrides")
    else:
        warn("Signing.xcconfig does not include an optional Local.xcconfig")
    # info.plist
    ipath = info.get("path")
    if ipath and tsettings.get("INFOPLIST_FILE") == ipath:
        ok(f"info.path = INFOPLIST_FILE = {ipath}")
    else:
        fail(f"info.path ({ipath}) and INFOPLIST_FILE ({tsettings.get('INFOPLIST_FILE')}) differ")
    if ipath:
        for src in target.get("sources", []):
            p = src["path"] if isinstance(src, dict) else src
            if str((IOS / ipath).resolve()).startswith(str((IOS / p).resolve()) + "/"):
                fail(f"{ipath} is inside source folder {p}: it would also be copied into the app as a resource")
        if not (IOS / ipath).parent.is_dir():
            fail(f"folder of {ipath} is missing; a fresh clone would not have it (track a file in it)")
    # schemes
    for sname, sch in spec.get("schemes", {}).items():
        missing = [t for t in sch.get("build", {}).get("targets", {}) if t not in targets]
        if missing:
            fail(f"scheme '{sname}' builds unknown target(s) {missing}")
        else:
            ok(f"scheme '{sname}': run={sch.get('run', {}).get('config')}")

# ---------------------------------------------------------------- 2. sources classification
section("XcodeGen source classification (simulated)")
excludes = []
src_roots = []
if spec:
    for src in target.get("sources", []):
        if isinstance(src, dict):
            src_roots.append(src["path"])
            excludes += src.get("excludes", [])
        else:
            src_roots.append(src)
else:
    src_roots = ["NexaFixScan"]
compiled, resources, skipped = [], [], []
for root in src_roots:
    base_dir = IOS / root
    for p in sorted(base_dir.rglob("*")):
        rel = p.relative_to(base_dir).as_posix()
        if any(part.endswith(".xcassets") for part in p.relative_to(base_dir).parts[:-1]):
            continue  # inside an asset catalog: the catalog is one resource
        if p.is_dir():
            continue
        if any(fnmatch.fnmatch(rel, e) or fnmatch.fnmatch(rel, e.replace("**/", "")) for e in excludes):
            skipped.append(rel)
        elif p.suffix == ".swift":
            compiled.append(rel)
        else:
            resources.append(rel)
    for p in sorted(base_dir.rglob("*.xcassets")):
        resources.append(p.relative_to(base_dir).as_posix())
print(f"  {len(compiled)} Swift files -> Compile Sources; {len(skipped)} excluded")
expected_res = {".xcassets", ".xcprivacy"}
for r in resources:
    if Path(r).suffix in expected_res:
        ok(f"Copy Bundle Resources: {r}")
    else:
        fail(f"unexpected non-Swift file would be copied into the app: {r}")
names = {}
for r in compiled:
    names.setdefault(Path(r).name, []).append(r)
dups = {n: v for n, v in names.items() if len(v) > 1}
if dups:
    fail(f"duplicate Swift file names in one module (swiftc rejects these): {dups}")
else:
    ok("no duplicate Swift file names")
if not any(r.endswith("PrivacyInfo.xcprivacy") for r in resources):
    fail("PrivacyInfo.xcprivacy is not among the resources")

# ---------------------------------------------------------------- 3. asset catalogs
section("asset catalogs")


def png_check(path, size):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return "not a PNG"
    pos, chunks, ihdr = 8, [], None
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8].decode("latin1")
        if ctype == "IHDR":
            ihdr = struct.unpack(">IIBBBBB", data[pos + 8:pos + 21])
        chunks.append(ctype)
        pos += 12 + ln
    w, h, depth, color, _, _, _ = ihdr
    if (w, h) != (size, size):
        return f"is {w}x{h}, needs {size}x{size}"
    if color in (4, 6):
        return "has an alpha channel (colour type %d)" % color
    if "tRNS" in chunks:
        return "has a tRNS transparency chunk"
    return None


catalogs = [p for r in src_roots for p in (IOS / r).rglob("*.xcassets")]
if not catalogs:
    fail("no .xcassets found")
colorsets = set()
for cat in catalogs:
    for cj in sorted(cat.rglob("Contents.json")):
        try:
            json.loads(cj.read_text())
        except Exception as e:  # noqa: BLE001
            fail(f"{cj.relative_to(IOS)} is not valid JSON: {e}")
    ok(f"{len(list(cat.rglob('Contents.json')))} Contents.json files parse")
    for cs in sorted(cat.glob("*.colorset")):
        colorsets.add(cs.stem)
        data = json.loads((cs / "Contents.json").read_text())
        for c in data.get("colors", []):
            comps = c["color"]["components"]
            vals = [float(comps[k]) for k in ("red", "green", "blue", "alpha")]
            if not all(0.0 <= v <= 1.0 for v in vals):
                fail(f"{cs.name}: component outside 0...1")
        ok(f"colorset {cs.stem}: {len(data.get('colors', []))} colour entries")
    for ic in sorted(cat.glob("*.appiconset")):
        data = json.loads((ic / "Contents.json").read_text())
        imgs = data.get("images", [])
        if len(imgs) == 1 and imgs[0].get("idiom") == "universal" and imgs[0].get("platform") == "ios" \
                and imgs[0].get("size") == "1024x1024":
            ok(f"{ic.name}: single universal 1024x1024 iOS entry (valid for Xcode 15 and later)")
        else:
            warn(f"{ic.name}: not the single-size layout; check it against Xcode's asset catalog format")
        for im in imgs:
            f = ic / im["filename"]
            if not f.is_file():
                fail(f"{ic.name}: {im['filename']} is missing")
                continue
            problem = png_check(f, 1024)
            (fail if problem else ok)(f"{im['filename']}: " + (problem or "1024x1024 PNG, no alpha channel"))
if spec:
    icon_name = tsettings.get("ASSETCATALOG_COMPILER_APPICON_NAME")
    accent = tsettings.get("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME")
    if icon_name and any((c / f"{icon_name}.appiconset").is_dir() for c in catalogs):
        ok(f"ASSETCATALOG_COMPILER_APPICON_NAME '{icon_name}' exists")
    else:
        fail(f"app icon set '{icon_name}' not found in the asset catalog")
    if accent and accent in colorsets:
        ok(f"accent colour '{accent}' exists")
    else:
        fail(f"accent colour '{accent}' not found in the asset catalog")
    launch = info.get("properties", {}).get("UILaunchScreen", {}).get("UIColorName")
    if launch in colorsets:
        ok(f"UILaunchScreen.UIColorName '{launch}' exists")
    else:
        fail(f"UILaunchScreen colour '{launch}' not found in the asset catalog")

# ---------------------------------------------------------------- 4. privacy manifest
section("privacy manifest vs required-reason APIs")
CATEGORIES = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"3EC4.1", "54BD.1"},
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
}
# Regexes for the APIs Apple lists in "Describing use of required reason API". Strong patterns only; names the
# project defines itself are allow-listed by file below (e.g. the PDF writer's own `creationDate` property).
API_PATTERNS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage\b",
    "NSPrivacyAccessedAPICategorySystemBootTime": r"\bsystemUptime\b|\bmach_absolute_time\b|\bmach_continuous_time\b",
    "NSPrivacyAccessedAPICategoryFileTimestamp":
        r"\bcontentModificationDateKey\b|\bcreationDateKey\b|\bNSFileCreationDate\b|\bNSFileModificationDate\b"
        r"|\.fileModificationDate\b|\.fileCreationDate\b|\battributesOfItem\b|\bgetattrlist(?:bulk|at)?\b"
        r"|\b(?:f|l)?stat(?:at)?\s*\(|\.contentModificationDate\b|\.modificationDate\b|\.creationDate\b"
        r"|\.contentAccessDate\b|\.attributeModificationDate\b|\.fileSizeKey\b|\.fileSize\b|\.totalFileSize\b",
    "NSPrivacyAccessedAPICategoryDiskSpace":
        r"\bvolumeAvailableCapacity\w*|\bvolumeTotalCapacityKey\b|\bsystemFreeSize\b|\bsystemSize\b"
        r"|\battributesOfFileSystem\b|\bf?statv?fs\s*\(",
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"\bactiveInputModes\b",
}
OWN_NAMES = {  # (category, file name) -> reason this match is not the system API
    ("NSPrivacyAccessedAPICategoryFileTimestamp", "PDFWriter.swift"): "PDFDocumentInfo.creationDate is the project's own field",
    ("NSPrivacyAccessedAPICategoryFileTimestamp", "PlanPDFRenderer.swift"): "passes the project's own PDF creationDate",
}
manifests = [m for r in src_roots for m in (IOS / r).rglob("PrivacyInfo.xcprivacy")]
pm = {}
if len(manifests) != 1:
    fail(f"expected exactly one PrivacyInfo.xcprivacy under the source folders, found {len(manifests)}")
else:
    try:
        pm = plistlib.loads(manifests[0].read_bytes())
        ok("PrivacyInfo.xcprivacy is a valid property list")
    except Exception as e:  # noqa: BLE001
        fail(f"PrivacyInfo.xcprivacy does not parse: {e}")
declared = {}
if pm:
    for k, t in [("NSPrivacyTracking", bool), ("NSPrivacyTrackingDomains", list),
                 ("NSPrivacyCollectedDataTypes", list), ("NSPrivacyAccessedAPITypes", list)]:
        if isinstance(pm.get(k), t):
            ok(f"{k} present ({t.__name__})")
        else:
            fail(f"{k} missing or not a {t.__name__}")
    if pm.get("NSPrivacyTracking") and not pm.get("NSPrivacyTrackingDomains"):
        warn("NSPrivacyTracking is true but no tracking domains are listed")
    for entry in pm.get("NSPrivacyAccessedAPITypes", []):
        cat = entry.get("NSPrivacyAccessedAPIType")
        reasons = set(entry.get("NSPrivacyAccessedAPITypeReasons", []))
        if cat not in CATEGORIES:
            fail(f"unknown category {cat}")
        elif not reasons or not reasons <= CATEGORIES[cat]:
            fail(f"{cat}: reasons {sorted(reasons)} are not all valid for this category ({sorted(CATEGORIES[cat])})")
        else:
            declared[cat] = reasons
            ok(f"declared {cat} {sorted(reasons)}")
used = {}
code_files = list(swift_files(IOS / "NexaFixScan", IOS / "NexaFixCore/Sources"))
for f in code_files:
    text = strip_comments(f.read_text())
    for cat, pat in API_PATTERNS.items():
        for m in re.finditer(pat, text):
            if (cat, f.name) in OWN_NAMES:
                continue
            line = text.count("\n", 0, m.start()) + 1
            used.setdefault(cat, []).append(f"{f.relative_to(IOS)}:{line} {m.group(0).strip()}")
for cat in CATEGORIES:
    if cat in used and cat not in declared:
        fail(f"{cat} is used but not declared: " + "; ".join(used[cat][:4]))
    elif cat in declared and cat not in used:
        warn(f"{cat} is declared but no use was found in the sources (declare only what is used)")
    elif cat in used:
        ok(f"{cat}: {len(used[cat])} use(s) in the sources, declared")
for (cat, name), why in OWN_NAMES.items():
    print(f"        (not counted: {name}: {why})")

# ---------------------------------------------------------------- 5. Info.plist vs frameworks used
section("Info.plist keys vs what the sources use")
props = info.get("properties", {}) if spec else {}
alltext = "\n".join(strip_comments(f.read_text()) for f in code_files)
NEEDS = [  # (regex in code, Info.plist keys that satisfy it, why)
    (r"\bimport ARKit\b|\bimport RoomPlan\b|AVCaptureDevice\.(?:authorizationStatus|requestAccess)\(for: \.video\)",
     ["NSCameraUsageDescription"], "ARKit / RoomPlan / camera access"),
    (r"\bCMMotionActivityManager\b|\bCMPedometer\b|\bCMSensorRecorder\b|\bCMMovementDisorderManager\b",
     ["NSMotionUsageDescription"], "Core Motion activity APIs"),
    (r"\bCLLocationManager\b|\bimport CoreLocation\b", ["NSLocationWhenInUseUsageDescription"], "location"),
    (r"\bPHPhotoLibrary\b|\bUIImageWriteToSavedPhotosAlbum\b|\bPHAssetChangeRequest\b",
     ["NSPhotoLibraryAddUsageDescription", "NSPhotoLibraryUsageDescription"], "photo library"),
    (r"\bAVAudioSession\b|\bAVAudioRecorder\b|\brequestRecordPermission\b|\bAVAudioApplication\b",
     ["NSMicrophoneUsageDescription"], "microphone"),
    (r"\bLAContext\b", ["NSFaceIDUsageDescription"], "Face ID"),
    (r"\bCNContactStore\b|\bimport ContactsUI\b", ["NSContactsUsageDescription"], "contacts"),
    (r"\bCBCentralManager\b|\bCBPeripheralManager\b", ["NSBluetoothAlwaysUsageDescription"], "Bluetooth"),
    (r"\bNWBrowser\b|\bNetService\b|\bimport MultipeerConnectivity\b", ["NSLocalNetworkUsageDescription"], "local network"),
    (r"\bEKEventStore\b", ["NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription"], "calendars"),
    (r"\bATTrackingManager\b", ["NSUserTrackingUsageDescription"], "tracking"),
]
for pat, keys, why in NEEDS:
    hit = re.search(pat, alltext)
    have = [k for k in keys if props.get(k)]
    if hit and not have:
        fail(f"sources use {why} ({hit.group(0)}) but Info.plist has none of {keys}")
    elif hit:
        ok(f"{why}: {have[0]} present")
    elif any(props.get(k) for k in keys):
        warn(f"Info.plist has {keys[0]} but no use of {why} was found (remove unneeded privacy strings)")
if spec:
    cam = props.get("NSCameraUsageDescription", "")
    if len(cam) < 20:
        fail("NSCameraUsageDescription is empty or too short to explain the use")
    if "UILaunchScreen" in props and props["UILaunchScreen"] is not None:
        ok("UILaunchScreen present (full-screen layout on current iPhones)")
    else:
        fail("UILaunchScreen missing: the app would be letterboxed")
    iph = props.get("UISupportedInterfaceOrientations", [])
    ipad = props.get("UISupportedInterfaceOrientations~ipad", [])
    family = str(tsettings.get("TARGETED_DEVICE_FAMILY", ""))
    if "2" in family.split(",") and len(set(ipad)) < 4:
        fail("iPad is targeted but UISupportedInterfaceOrientations~ipad lacks the four orientations iPad multitasking requires")
    if iph:
        ok(f"iPhone orientations: {', '.join(o.replace('UIInterfaceOrientation', '') for o in iph)}; family {family}")
    docs_use = re.search(r"\.documentDirectory", alltext)
    if docs_use and not props.get("UIFileSharingEnabled"):
        warn("the app writes to Documents but UIFileSharingEnabled is off (Files app will not show the data)")
    crypto = re.search(r"\bCryptoKit\b|\bCommonCrypto\b|\bURLSession\b|\bSecKey\w*\b|\bimport Network\b", alltext)
    if crypto and props.get("ITSAppUsesNonExemptEncryption") is False:
        warn(f"ITSAppUsesNonExemptEncryption is false but the sources use {crypto.group(0)}; re-check export compliance")
    elif props.get("ITSAppUsesNonExemptEncryption") is False:
        ok("ITSAppUsesNonExemptEncryption = false and no networking/crypto API in the sources")
    if "UIRequiredDeviceCapabilities" in props and "arm64" in props["UIRequiredDeviceCapabilities"] \
            and "arkit" not in props["UIRequiredDeviceCapabilities"]:
        ok("UIRequiredDeviceCapabilities = [arm64] (no arkit: the app still opens without LiDAR)")
    else:
        warn("UIRequiredDeviceCapabilities should be [arm64] without arkit (demo mode must run on non-LiDAR devices)")

# ---------------------------------------------------------------- 6. package
section("NexaFixCore/Package.swift")
pkg = (IOS / "NexaFixCore/Package.swift").read_text()
m = re.search(r"swift-tools-version:\s*([0-9.]+)", pkg)
ok(f"tools version {m.group(1)}") if m else fail("no swift-tools-version line")
mi = re.search(r"\.iOS\(\.v(\d+)\)", pkg)
if mi and spec and int(mi.group(1)) <= 17:
    ok(f"package iOS platform .v{mi.group(1)} is not newer than the app's 17.0")
elif mi:
    fail(f"package requires iOS {mi.group(1)}, newer than the app's deployment target")
else:
    warn("package declares no iOS platform (defaults to a low version, which is fine for Xcode)")
if re.search(r"\.package\(", pkg):
    warn("package has dependencies: Xcode will need network access to resolve them")
else:
    ok("package has no dependencies (nothing to download, no Package.resolved)")
if "resources:" in pkg or "unsafeFlags" in pkg:
    warn("package declares resources or unsafeFlags; review how Xcode will build it")
else:
    ok("no resources, no unsafeFlags")
core_imports = set(re.findall(r"^\s*import (\w+)", "\n".join(f.read_text() for f in swift_files(IOS / "NexaFixCore/Sources")), re.M))
(ok if core_imports <= {"Foundation"} else warn)(f"Core imports: {sorted(core_imports)}")

# ---------------------------------------------------------------- 7. gitignore
section(".gitignore")
try:
    def ignored(path):
        return subprocess.run(["git", "-C", str(REPO), "check-ignore", "-q", path],
                              stdout=subprocess.DEVNULL).returncode == 0

    for path in ["ios/NexaFixScan.xcodeproj", "ios/NexaFixScan.xcodeproj/project.pbxproj", "ios/Config/Info.plist",
                 "ios/Config/Local.xcconfig", "ios/NexaFixCore/.build/x", "ios/build/x", "ios/NexaFixCore/Package.resolved"]:
        (ok if ignored(path) else fail)(f"{path} is " + ("ignored" if ignored(path) else "NOT ignored"))
    must_track = ["ios/project.yml", "ios/Config/Signing.xcconfig", "ios/Config/Local.xcconfig.example",
                  "ios/NexaFixCore/Package.swift", "ios/NexaFixScan/Resources/PrivacyInfo.xcprivacy",
                  "ios/NexaFixScan/Resources/Assets.xcassets/Contents.json",
                  "ios/NexaFixScan/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"]
    must_track += [f"ios/{f.relative_to(IOS).as_posix()}" for f in code_files]
    bad = [p for p in must_track if ignored(p)]
    (fail if bad else ok)("source files are not ignored" if not bad else f"source files ignored by .gitignore: {bad}")
    tracked = subprocess.run(["git", "-C", str(REPO), "ls-files", "ios/Config", "ios/NexaFixScan.xcodeproj"],
                             capture_output=True, text=True).stdout.split()
    if "ios/Config/Info.plist" in tracked or any(".xcodeproj" in t for t in tracked):
        fail("generated files are tracked by git: " + ", ".join(t for t in tracked if "Info.plist" in t or ".xcodeproj" in t))
    if not any(t.startswith("ios/Config/") for t in tracked):
        warn("no file under ios/Config is tracked yet (git add ios/Config so a fresh clone has the folder)")
except FileNotFoundError:
    warn("git not available: .gitignore checks skipped")

print(f"\n{len(fails)} FAIL, {len(warns)} WARN")
sys.exit(1 if fails else 0)
