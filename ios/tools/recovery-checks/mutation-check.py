#!/usr/bin/env python3
"""Proves the coordinator checks bite: puts each recovery fix back, one at a time, in a scratch copy of the app's
files and shows that run.sh's coordinator suite then fails (and fails in the check that guards that fix).

    python3 ios/tools/recovery-checks/mutation-check.py            # every mutation (about 1 to 2 minutes each)
    python3 ios/tools/recovery-checks/mutation-check.py NAME ...   # only these (names are printed by --list)
    python3 ios/tools/recovery-checks/mutation-check.py --list

The real sources are never written to. A mutation is a text replacement that must match exactly once; if the code
has moved on and the text is gone, the mutation is reported as BROKEN and the run fails, so this file cannot
quietly stop testing anything. Exit status 0 only if the unmodified copy passes and every mutation is KILLED, that
is: the suite failed, and failed in the tests (named in the "FAIL [test] ..." lines) that guard that fix.

Needs a Swift toolchain on PATH and python3 (standard library only).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
IOS = HERE.parent.parent
APP = IOS / "NexaFixScan"
RUN = HERE / "run.sh"

# The files run.sh compiles for the coordinator suite.
FILES = [
    "App/AppModel.swift", "App/AppSettings.swift", "App/UserFacingError.swift", "App/MeasurementFormatting.swift",
    "Screens/PropertyActions.swift",
    "Capture/ScanResult.swift", "Capture/ScanRecoveryStore.swift", "Capture/DeviceCapability.swift",
]
PA = "Screens/PropertyActions.swift"
STORE = "Capture/ScanRecoveryStore.swift"

# name -> (fix it guards, file, old text, new text, tests that must fail)
MUTATIONS = {
    "age-deletes-at-launch": (
        "1: a copy is never deleted at launch because of its age",
        PA,
        """            ScanRecoveryStore.prune(root: root) { scan in
                ScanRecoveryCoordinator.isSafelyStored(scan, root: root, store: store)
            }""",
        """            ScanRecoveryStore.prune(root: root) { scan in
                let limit: TimeInterval = scan.delivered ? 7 * 24 * 3600 : 30 * 24 * 3600
                return Date().timeIntervalSince(scan.updatedAt) > limit
                    || ScanRecoveryCoordinator.isSafelyStored(scan, root: root, store: store)
            }""",
        ("testOldCopiesAreOfferedNotDropped", "testFailedSaveThenRelaunchWeeksLaterStillOffersTheScan"),
    ),
    "prune-default-deletes-by-age": (
        "1: prune(root:), still called when a scan starts, deletes nothing by itself",
        STORE,
        "isSaved: (RecoverableScan) -> Bool = { _ in false }) -> [UUID] {",
        "isSaved: (RecoverableScan) -> Bool = { Date().timeIntervalSince($0.updatedAt) > 7 * 24 * 3600 }) -> [UUID] {",
        ("testPruneNeverDeletesByAge", "testOldCopiesAreOfferedNotDropped"),
    ),
    "redundant-copy-kept": (
        "1/3: a copy whose rooms are on disk is deleted silently at launch",
        PA,
        "        guard let propertyID = scan.propertyID,\n              let ids = ScanRecoveryStore.roomIDs",
        "        guard false, let propertyID = scan.propertyID,\n              let ids = ScanRecoveryStore.roomIDs",
        ("testRedundantCopyIsDeletedSilentlyAtLaunch", "testBannerRetryThenNextLaunchClearsTheCopySilently"),
    ),
    "partly-saved-counts-as-redundant": (
        "1: a copy with only some of its rooms in the property is kept",
        PA,
        "return plan.isNoOp && Set(plan.skippedRoomIDs) == Set(ids)",
        "return !plan.skippedRoomIDs.isEmpty",
        ("testACopyThatIsNotProvenRedundantIsKeptAndOffered",),
    ),
    "property-from-backup-counts": (
        "1: rooms found only in the property's backup do not make a copy redundant",
        PA,
        "              !loaded.recoveredFromBackup else { return false }",
        "              true else { return false }",
        ("testACopyThatIsNotProvenRedundantIsKeptAndOffered",),
    ),
    "incomplete-copy-counts": (
        "1: a copy that cannot be read completely is never judged redundant",
        STORE,
        "                  let raw = decode(RawCapture.self, from: data) else { return nil }\n            ids.append(raw.id)",
        "                  let raw = decode(RawCapture.self, from: data) else { continue }\n            ids.append(raw.id)",
        ("testACopyThatIsNotProvenRedundantIsKeptAndOffered",),
    ),
    "year-missing-from-old-dates": (
        "1: the date of a scan from an earlier year carries its year",
        PA,
        'formatter.dateFormat = sameYear ? "d MMM, HH:mm" : "d MMM yyyy, HH:mm"',
        'formatter.dateFormat = "d MMM, HH:mm"',
        ("testPromptWording",),
    ),
    "retry-says-already-saved": (
        "2: a retry after a failed save says what was added",
        PA,
        "if let earlier = failedSaves.removeValue(forKey: scanID) {",
        "if let earlier = failedSaves.removeValue(forKey: UUID()) {",
        ("testFailedSaveKeepsTheCopyAndRetryDoesNotDuplicate", "testBannerRetryThenTheSheetsTryAgainSaysAdded",
         "testFailedNewPropertyIsRememberedForTheRetry"),
    ),
    "retry-drops-warnings": (
        "2: ...and keeps the recovered-level warnings",
        PA,
        "phase = .done(target, Report(summary: earlier.summary, warnings: earlier.warnings, propertyID: propertyID))",
        "phase = .done(target, Report(summary: earlier.summary, warnings: [], propertyID: propertyID))",
        ("testFailedSaveKeepsTheCopyAndRetryDoesNotDuplicate", "testBannerRetryThenTheSheetsTryAgainSaysAdded",
         "testFailedNewPropertyIsRememberedForTheRetry"),
    ),
    "restart-advice-back": (
        "4: the damaged-property text does not tell the person to restart",
        PA,
        """            return Failure(message: "This property could not be opened, so the rooms were not added.",
                           recovery: "Your copy is kept. You can try again later, or ask for help.")""",
        """            return Failure(message: "The property could not be opened, so the rooms were not added.",
                           recovery: "The recovered copy is still on this iPhone. Restart the app, then try again.")""",
        ("testUnreadablePropertyIsNotReplacedByANewOne",),
    ),
    "failed-list-offers-anyway": (
        "4: nothing is offered when the property list could not be read",
        PA,
        "        guard !ScanRecoveryCoordinator.propertyListUnreadable(in: model) else { return }\n",
        "",
        ("testUnreadablePropertyListSkipsTheOffer",),
    ),
    "any-empty-list-skips-offer": (
        "4: a new install (empty list, no error) is not mistaken for a failed list",
        PA,
        "        model.summaries.isEmpty && model.presentedError != nil",
        "        model.summaries.isEmpty",
        ("testAnUnrelatedErrorDoesNotHoldBackTheOffer", "testRecoverMakesANewPropertyWhenTheOldOneIsGone"),
    ),
}


def run_suite(app_dir: Path, work: Path) -> "tuple[int, str]":
    env = dict(os.environ, APP_DIR=str(app_dir), RECOVERY_CHECKS_WORK=str(work), RECOVERY_CHECKS_OPT="-Onone")
    proc = subprocess.run([str(RUN), "coordinator"], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True)
    return proc.returncode, proc.stdout


def copy_app(dest: Path) -> None:
    for rel in FILES:
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(APP / rel, target)


def main(argv: "list[str]") -> int:
    if "--list" in argv:
        for name, (fix, *_rest) in MUTATIONS.items():
            print(f"{name:34s} fix {fix}")
        return 0
    names = [a for a in argv if not a.startswith("-")] or list(MUTATIONS)
    unknown = [n for n in names if n not in MUTATIONS]
    if unknown:
        print("unknown mutation(s):", ", ".join(unknown), "(see --list)", file=sys.stderr)
        return 2

    base = os.environ.get("RECOVERY_CHECKS_WORK") or os.path.join(
        os.environ.get("TMPDIR", tempfile.gettempdir()), "nexafix-recovery-checks")
    work = Path(base)
    scratch = work / "mutants"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    status = 0

    print("baseline: the unmodified files")
    copy_app(scratch / "baseline")
    code, out = run_suite(scratch / "baseline", work)
    last = [line for line in out.splitlines() if line.startswith("checks:")]
    print("  ", last[-1] if last else out[-400:])
    if code != 0:
        print("  baseline FAILED; nothing else can be concluded\n" + out[-2000:])
        return 1

    results = []
    for name in names:
        fix, rel, old, new, expect = MUTATIONS[name]
        mutant = scratch / name
        copy_app(mutant)
        path = mutant / rel
        text = path.read_text()
        if text.count(old) != 1:
            results.append((name, "BROKEN", f"the text to replace matches {text.count(old)} times, expected 1"))
            status = 1
            continue
        path.write_text(text.replace(old, new))
        code, out = run_suite(mutant, work)
        if code == 3:
            results.append((name, "BROKEN", "the mutated code does not compile"))
            status = 1
        elif code == 0:
            results.append((name, "SURVIVED", "every check still passed"))
            status = 1
        else:
            fails = [l for l in out.splitlines() if l.startswith("FAIL")]
            failing = {m.group(1) for l in fails if (m := re.match(r"FAIL \[(\w+)\]", l))}
            missing = [t for t in expect if t not in failing]
            if missing:
                results.append((name, "WRONG", f"failed, but not in {', '.join(missing)}; failing tests: {sorted(failing)}"))
                status = 1
            else:
                first = re.sub(r"^FAIL \[\w+\] line \d+: ", "", fails[0])
                results.append((name, "KILLED", f"{len(fails)} check(s) failed in {len(failing)} test(s) ({', '.join(expect)}); e.g. {first[:90]}"))
        print(f"{name:34s} {results[-1][1]:8s} {results[-1][2]}", flush=True)

    print("\nsummary")
    for name, verdict, detail in results:
        print(f"  {verdict:8s} {name:34s} (fix {MUTATIONS[name][0]})")
    killed = sum(1 for r in results if r[1] == "KILLED")
    print(f"{killed} of {len(results)} mutations killed")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
