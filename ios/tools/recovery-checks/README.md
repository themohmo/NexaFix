# Recovery checks

Regression checks for the code that decides **when a scan's safety copy may be deleted**, and what the person is told.

The worst failure in NexaFix Scan is losing a scan. Each scanned room is written to
`Application Support/ScanRecovery/<scan id>/` the moment it is built (`Capture/ScanRecoveryStore.swift`). When the
app opens, `ScanRecoveryCoordinator` (`Screens/PropertyActions.swift`, next to `ScanIntake`) offers "Unfinished scan
found", and `RootView.swift` presents the sheet. These checks run the real files, not copies of their logic, against a
real `AppModel`, `PropertyStore` and `ScanRecoveryStore` in temporary folders.

```
ios/tools/recovery-checks/run.sh                 # both suites, from anywhere (the script finds the repo itself)
ios/tools/recovery-checks/run.sh coordinator     # launch-time recovery only (about 1 minute the first time)
ios/tools/recovery-checks/run.sh controller      # the scan screen's controller only (1 to 2 minutes the first time)
python3 ios/tools/recovery-checks/mutation-check.py   # proves the coordinator checks bite (see below)
```

Needs `swiftc` and `swift build` (Swift 5.9 or newer, Linux or macOS) on `PATH`; no Xcode project, simulator or Apple
framework. Exit status 0 only if every check passed (1: a check failed, 3: a suite did not compile). Everything is
built under `${RECOVERY_CHECKS_WORK:-${TMPDIR:-/tmp}/nexafix-recovery-checks}`; the repo is never written to. A snapshot
of `ios/NexaFixCore` is copied there (without its test target) and built, and reused while Core is unchanged.

## What they guard

The rule: **a copy is deleted only when the rooms are on disk in their property, or the person discards it. Never
because it is old, and never before the save worked.**

### `coordinator/` (`run.sh coordinator`)

Compiles `AppModel`, `AppSettings`, `UserFacingError`, `MeasurementFormatting`, `PropertyActions`, `ScanResult`,
`ScanRecoveryStore` and `DeviceCapability` together with `coordinator/main.swift`.

| area | what is checked |
|---|---|
| Age never deletes | A delivered copy 8 days old, an abandoned one 31 days old and one 400 days old are all **offered**, none deleted (the old limits were 7 and 30 days). `ScanRecoveryStore.prune(root:)`, which the scan screen still calls when a scan starts, deletes nothing without proof, at any age. The reported case end to end: the property save fails, the copy is kept, the app is opened again 9 days later, and the scan is offered and recovered. |
| Redundant copies go quietly | At launch a copy whose rooms are all in the property **on disk** is deleted without a prompt, delivered or not, fresh or old. This is also what clears the copy of a scan that was saved by "Try again" on the app's "not saved" banner (which does not know about the copy). The cheap test used for this (room ids from the copy against the property) is cross-checked with `ScanCommit.apply`, the real save. |
| ...and only then | Kept and offered: only some rooms in the property; the rooms are in a different property; one capture of the copy cannot be read; no property id; the property is gone; the property reads only from its backup. |
| Retry after a failed save | After a failed save, "Try again" (or the banner, then "Try again") finds the rooms already in the property. It says "Added N rooms to Level N." and keeps the recovered-level warnings (no 3D model, no AR map), not "already saved, so nothing was added". A scan that was saved by the scan's own path still says nothing was added, with no warnings. Nothing is added twice. |
| Damaged property | Recovering into an unreadable property keeps the copy and says "This property could not be opened, so the rooms were not added. Your copy is kept. You can try again later, or ask for help." (no advice to restart). It does not make a new property. |
| Property list unreadable | If the property list could not be read at launch (nothing listed, an error waiting), nothing is offered or deleted that launch, so no second property is made next to the real one; the next launch offers the scans. An error with a readable list, and a new install with no error, do not hold the offer back. |
| Wording | The headline, explanation and confirmation texts; the date ("9 Oct, 14:32", with the year once a scan is from an earlier year: "2 Sep 2025, 14:32"), which is computed against a fixed "now" so it does not depend on the clock. |
| The flow | Newest first and one at a time; Discard and Not now; two quick taps skip nothing; a failed save keeps the copy and a retry does not duplicate; a new property made for a missing one is remembered by the retry. |

Not covered here (needs UIKit or SwiftUI): `RootView.swift`'s sheet. Its one change in this area, opening at the
large detent at accessibility text sizes, is checked only by the whole-app typecheck (`ios/tools/typecheck/run.sh`).

### `controller/` (`run.sh controller`)

`ScanSessionController` (the scan screen's state machine) against stub ARKit, RoomPlan, UIKit, AVFoundation and simd
modules (`controller/stubs/`, about 22 KB; the documentation-verified shims for the whole app live in
`ios/tools/typecheck`). It guards the part that **writes and ends the copy**: every room is on disk before it is named;
a rescanned room leaves the copy; the finished scan is marked delivered and the copy is kept until the app confirms the
save; leaving on purpose removes the copy; tearing the view down keeps it; the rebuilt rooms have the same ids as the
delivered result (which is what lets the launch check recognise a saved scan). It also covers the scan flow's error,
timeout and interruption paths (361 checks).

`controller/run.sh` stages the app's real `ScanResult`, `DeviceCapability`, `CapturedRoomMapper`,
`ScanSessionController` and `ScanRecoveryStore` next to a copy of Core's sources. It makes two edits to the staged copy
of `ScanSessionController.swift` that the Linux stubs need (the optional-delegate `?(` and `ForegroundClock` being
`private`), and fails if they did not apply.

### `mutation-check.py`

Puts each fix back, one at a time, in a scratch copy of the app files, and runs the coordinator suite against it:

```
age-deletes-at-launch            launch deletes by age again                      -> "no copy was deleted because of its age"
prune-default-deletes-by-age     prune(root:) deletes by age again                -> "no proof, no deletion, at any age"
redundant-copy-kept              redundant copies are no longer recognised        -> "both redundant copies were deleted"
partly-saved-counts-as-redundant any room in the property is enough               -> "copy kept: only some rooms in the property"
property-from-backup-counts      a property read from its backup is enough        -> "copy kept: rooms only in the backup"
incomplete-copy-counts           an unreadable room is skipped, not fatal         -> "copy kept: a capture of the copy cannot be read"
year-missing-from-old-dates      old dates lose their year                        -> "2 Sep 2025, 14:32"
retry-says-already-saved         the retry forgets the failed save                -> "a retry after a failed save says what was added"
retry-drops-warnings             ...and drops the recovered-level warnings        -> "recovered-level warning"
restart-advice-back              the old "Restart the app" text                   -> "This property could not be opened"
failed-list-offers-anyway        no guard for an unreadable property list         -> "nothing is offered this launch"
any-empty-list-skips-offer       the guard fires on a new install too             -> "an empty list with no error is a new install"
```

A mutation that no longer matches the code (`BROKEN`), compiles no more, survives, or fails in a different check than
intended makes the script exit non-zero. `--list` prints the names; pass names to run only those.

## When to run them

After any change to `ScanRecoveryStore.swift`, the coordinator, `ScanIntake` or `ScanCommit` in `PropertyActions.swift`,
`ScanSessionController.swift`, `AppModel.save/update/retryUnsavedSaves`, or the part of `RootView.finishScan` that
decides when the copy is discarded. If you change what deletes a copy, add the check first.

## What this does not prove

* That it works on a device: ARKit, RoomPlan, file protection, the iOS lifecycle (when the system really ends the app),
  and the sheet itself are not exercised. The controller stubs are small and written to let the controller run; they
  are not Apple's behaviour.
* A full disk or a killed process is simulated by turning a property's folder into a plain file, and by creating a new
  model on the same folders. That models "the write failed" and "the app opened again", not every way storage fails.
* Foundation here is swift-corelibs-foundation on Linux.
