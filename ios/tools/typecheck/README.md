# Whole-app typecheck (no Xcode needed)

`run.sh` typechecks **every file under `ios/NexaFixScan` together** (one module, like Xcode does) against

* the **real** `NexaFixCore` (built from the working tree with SwiftPM), and
* **shims** of the Apple modules the app imports, whose signatures are copied from Apple's own documentation.

It runs on Linux with the open-source Swift toolchain, in Swift 5 language mode with minimal concurrency checking
(the project's `SWIFT_VERSION 5.0` / `SWIFT_STRICT_CONCURRENCY minimal`). It exists because the app is written on
machines that cannot build it: a cross-file mismatch (a label, a missing member, an optional) should not wait for the
first Xcode build to be found.

Read **"What this does NOT prove"** below before relying on a green run.

## Run it

```
ios/tools/typecheck/run.sh                 # Core build + shim modules + 3 typecheck passes + audits (~2 min after the first run)
ios/tools/typecheck/run.sh --strict        # also report -strict-concurrency=complete (information only)
ios/tools/typecheck/run.sh --quick         # device Debug pass only
ios/tools/typecheck/prove_bites.sh         # (~4 min) injects 9 faults into a copy (5 cross-file + 4 against Apple's APIs), shows each is caught
APP_DIR=/path/to/copy ios/tools/typecheck/run.sh --quick
```

Needs `swiftc` 6.0 or newer on `PATH` (or `SWIFT_BIN=<toolchain>/usr/bin`; the toolchain must include `lib/swift/host`,
i.e. SwiftSyntax, for the `#Preview` stand-in) and `python3` (3.9+, standard library only). Built here with the
swift.org Swift 6.0.3 tarball on Ubuntu 24.04 x86_64. Everything it builds goes to `.build/` (git-ignored).
Exit status 0 means "no errors in any pass and every audit passed".

### What a run does

| step | what | decides the exit status |
|---|---|---|
| Core | `swift build` of a copy of `ios/NexaFixCore` | yes |
| shim modules | `shims/*` compiled in the order of `shims/MODULES` | yes |
| `device-debug` | all app files, `-D DEBUG` (previews and debug helpers included) | yes |
| `device-release` | all app files, no `DEBUG` | yes |
| `simulator-debug` | a copy of the app where `targetEnvironment(simulator)` reads `os(Linux)`, so the `#if` simulator branches are compiled (Linux cannot take a simulator target triple) | yes |
| `--strict` | `-strict-concurrency=complete` | no (information) |
| shims vs docs | `docs/verify_shims.py verify` (offline) | yes |
| name collisions | `docs/framework_names.py collisions` | yes |
| environment | `audit/check_environment.py` | yes |
| availability | `audit/check_availability.py` | yes |

`triage.py` classifies every `error:` of a pass. The only thing it lets through is the harness artifact below.

## What it found (state when this README was written)

* 49 swift files, **0 errors** in `device-debug`, `device-release` and `simulator-debug`; 41 warnings per pass (see
  "Warnings"). No edit to `ios/NexaFixScan` was needed: the first whole-app run reported 250 errors (103 distinct), and every
  one was a gap or an ambiguity in the shims (a missing type or overload, two documented overloads that accept the same
  call, a missing `import Observation` in the shim). One of them, `ARReviewController.swift` (`UIAccessibility.post` from a
  class that is not `@MainActor`), passed only through a modelling decision, not a documented fact: see
  "`@preconcurrency`" below. The app no longer depends on that decision: `announce` now goes through
  `MainActor.assumeIsolated`, and it also compiles against a shim in which `UIAccessibility.post` is `@MainActor`.
* `--strict` (complete checking): 84 warnings, all "an error in the Swift 6 language mode"; none matters for Swift 5.
* Fault injection (`prove_bites.sh`): 9 of 9 faults caught (the five required: wrong argument label across files, removed
  member, duplicate type name, missing import, optional misuse; plus a wrong `ForEach`, `ARSession.run`,
  `RoomCaptureSession.run` and `AVCaptureDevice.requestAccess` call, which only fail if the shims carry the documented
  signatures); each fault goes into a fresh copy and the real sources are unchanged (tree hash compared before/after).
* Availability: the app uses 2 APIs newer than the iOS 17.0 target (`glassEffect` with `Glass.regular`, iOS 26;
  `PerspectiveCameraComponent.fieldOfViewOrientation`, iOS 18). Both sit inside `if #available`. The glass one has an
  `else` fallback (a material and a hand-drawn edge); the camera one has no `else`: on iOS 17 the orientation is simply not
  set, so it relies on the iOS 17 default being the vertical one the code wants (not stated by the documentation text I could read).
* Environment: `AppModel` and `AppRouter` are read with `@Environment(X.self)` in 11 types; the app scene injects the model,
  `RootView` injects the router after its `.sheet` / `.navigationDestination` presentations, and every `#Preview` that
  builds such a view injects what it needs.
* Name collisions: none between Core's or the app's top-level types and the 5515 module-level types of the 21 imported
  Apple frameworks (list from Apple's documentation index, `docs/framework-types.json`).

### Warnings

40 of the 41 are `Binding(get:set:)` closures (ExportSheet, PropertiesListView, PropertyView, RootView, ScanFlowView,
SettingsView, Viewer3DView) and 1 is a `.task` body calling a stored closure (`RootView.swift:386`). The shim copies Apple's
documented `@isolated(any) @Sendable` closure types, and Swift 6.0.3 then warns "main actor-isolated property ... from a
Sendable closure; this is an error in the Swift 6 language mode". Whether the compiler of Xcode 27 infers the isolation of
those closures and stays silent could not be checked. They are warnings in Swift 5 mode either way.

### Harness artifact

With Objective-C interop switched on, the Linux standard library (which has no `AutoreleasingUnsafeMutablePointer`) makes
the compiler reject every inout-to-pointer argument: "broken standard library: cannot find intrinsic operations on
`UnsafeMutablePointer<T>`". `Viewer/ModelBridge.swift:66` (`getRed(&r, green: &g, blue: &b, alpha: &a)`) is the one such
site in the app. `known-harness-artifacts.tsv` pins it by file, line and a hash of the line's text; `triage.py` ignores
exactly those diagnostics, so a second `&x` argument, or an edit of that line, fails the run until someone looks at it.
The types at that site were checked by hand (four `CGFloat` variables to four `UnsafeMutablePointer<CGFloat>?`
parameters of the documented `UIColor.getRed(_:green:blue:alpha:)`). This is one place where a mistake would not be caught.

## How the shims stay faithful

Every declaration in `shims/` carries a tag on the line above it:

```
// doc: SwiftUI/View/padding(_:_:)               copied from that Apple documentation page
// doc-fixed: <page> | <old> => <new> | <why>    copied, except for the one stated substring (the docs are lossy there)
// doc-unconfirmed: <reason>                     the documentation does not show this signature (listed below)
// shim: <reason>                                scaffolding that is not an Apple API (bodies, witnesses, builder plumbing)
```

`docs/verify_shims.py verify` compares each `doc:` declaration with the declaration stored in `docs/declarations.json`
(extracted from the documentation JSON by `sync`, so verification is offline): labels, generics, `where` clauses,
optionality, defaults, `@MainActor`, `@Sendable`, `@escaping`, result-builder attributes, protocol requirements,
conformances (a conformance must be listed on the page, or the type on the protocol's page). It ignores access modifiers,
bodies, `@inlinable`/`@export(implementation)`, `@_disfavoredOverload`, `@objc(...)`, and `nonisolated` on the docs side (a
shim member may omit it; it may not add it). An untagged declaration is an error. At the time of writing: about 3300 shim
declarations, about 2900 `doc`, 6 `doc-fixed`, 18 `doc-unconfirmed`, 238 `shim`, 130 conformance/extension containers, 0 problems.

The documentation is Apple's current documentation JSON (`developer.apple.com/tutorials/data/documentation/...`),
i.e. the iOS 26/27 SDK era. Availability, `@MainActor`, `@preconcurrency` and `nonisolated` come from the same pages.

The generated parts (`shims/SwiftUI/Gen_*.swift`, most of UIKit/ARKit/RealityKit/RoomPlan/CoreGraphics/small modules) come
from the generators in `docs/gen/`; `Core.swift`, `Protocols.swift`, `simd`, `Darwin` and `_macros` are hand-written.
A declaration the shim could not compile (it names a type the shim does not define, e.g. `LocalizedStringResource`,
`ImageResource`, `AppIntent`, `OutlineGroup`) was **dropped, not weakened**: 553 entries, each with the compiler's reason,
in `docs/gen/prune.txt`. A dropped declaration can make a valid call fail to compile; it cannot make an invalid call pass.

### Where a signature could not be confirmed or had to be changed

`doc-unconfirmed` (18; `docs/verify_shims.py report` prints them with reasons):

* `ViewBuilder.buildBlock<each Content>` (the parameter-pack form with no child limit), `buildLimitedAvailability`: the docs
  show only the zero- and one-child `buildBlock`; the pack form is copied from the documented `SceneBuilder.buildBlock`.
* `ToolbarContentBuilder` (`buildBlock`, `buildIf`, `buildEither` x2): not listed on its page in this snapshot.
* `_ConditionalContent`, `ViewModifier.Body`, `ShapeStyle.Resolved`: named by documented signatures but without a page.
* `CGAffineTransform` members (3): the page lists only the C functions.
* `ARCamera.projectPoint(_:orientation:viewportSize:)`: only an Objective-C page exists (iOS 11.0, deprecated 27.0); the Swift
  signature is the importer's rendering of it.
* `ARError.code`, `MeshDescriptor.positions/normals` (2), `UIResponder.isAccessibilityElement/accessibilityElementsHidden` (2):
  members the pages do not list.

`doc-fixed` (6): `ViewBuilder.buildBlock(_:)`, `buildEither` x2, `buildIf` (the docs drop the `View` constraint of these
inlinable methods), `PresentationDetent.Context` (`@dynamicMemberLookup` removed: it needs a subscript the docs do not
list), and `View.toolbar(content:)` for `ToolbarContent` (the docs print `@ContentBuilder`; a `ToolbarItem` cannot be built
by `ViewBuilder`, so the shim uses `@ToolbarContentBuilder`).

Other judgement calls, all outside what the pages state:

* **Overload ranking.** Where the docs list two overloads that accept the same call, the compiler needs some way to prefer
  one, and the pages do not print it. 10 shim overloads are `@_disfavoredOverload`: 7 chosen by a rule (same labels and
  parameter types, ignoring defaults/optionality/return type, introduced in an older OS than a sibling: `Shape.fill`,
  `InsettableShape.strokeBorder` x2, `View.alert(error:)` x2, `Font.system`, `EnvironmentValues.subscript`) and 3 by hand
  (`Animation.interactiveSpring(response:...)`, two `Stepper` label-first initialisers); see `MANUAL_DISFAVOR` in
  `docs/gen/mk.py`. A wrong choice here can only change which of two overloads is picked, not whether a mismatch is found.
* **`@preconcurrency`.** The docs print `@MainActor` on `UIAccessibility.post(...)` and `isVoiceOverRunning` without
  `@preconcurrency`, which the Objective-C importer implies; the shim adds it (Swift 5 mode then accepts the call from
  `ARReviewController.announce`, a non-isolated class; `--strict` shows it as a warning). Same convention for UIKit/ARKit
  classes (`@MainActor @preconcurrency`). If a real SDK declaration lacks it, that call is an error in Xcode.
* **Types the docs show as `nonisolated struct`.** Swift 6.0.3 cannot parse the keyword on a type, so the shim leaves it off
  and declares `View` conformances in extensions (a conformance in the primary declaration would make the type
  `@MainActor`). Members keep `nonisolated`.
* **Re-exports.** The shims make `import SwiftUI` re-export Foundation and CoreGraphics; `UIKit` re-exports Foundation,
  QuartzCore and simd; `ARKit`, `RealityKit` and `RoomPlan` re-export Foundation and simd; `AVFoundation` and `Accessibility`
  re-export Foundation; `CoreGraphics` and `QuartzCore` re-export Foundation (on Linux `CGFloat` lives in Foundation). The docs do
  not say any of this. Files that import only SwiftUI (plus Core or Observation) rely on it: with the SwiftUI re-exports
  removed, `AR/OverlayStyle.swift` (`CGFloat`), `AR/ARReviewView.swift` (`UUID`, `URL`), `DesignSystem/Buttons.swift`,
  `Materials.swift`, `Components.swift` stop compiling. It is how SwiftUI behaves on Apple platforms as far as I know, but it is an assumption.
* **Observation.** `Observable` is visible from SwiftUI's declarations via `import Observation`; the shim does not
  re-export it, so a file using `@Observable` still needs its own `import Observation`.
* `#Preview`: the real macro is Xcode's; here `shims/_macros/PreviewsMacros.swift` is a SwiftSyntax plugin that expands
  `#Preview { ... }` to a `@MainActor` global holding `SwiftUI.Preview(body: { ... })` with a `ViewBuilder` body.
* `ContentUnavailableView.search`: Apple nests `SearchUnavailableContent` in the generic view; that makes the constrained
  extension circular (the compiler crashes), so it is a top-level `_SearchUnavailableContent` aliased under the documented name.
* `UIColor(Color)`, `EnvironmentValues.dismiss`/`DismissAction`, `AccessibilityTraits: SetAlgebra`, `UIKeyboardType`, `GestureMask`
  were added when the app needed them (declarations from the pages; the `SetAlgebra` requirements are `shim:` witnesses).

## Where the harness differs from Xcode

* **Compiler**: Swift 6.0.3 here; Xcode 27 ships a newer one. Diagnostics, type-checker time limits ("unable to type-check in
  reasonable time" appeared only while overloads were still ambiguous), `@isolated(any)` inference and macro handling can differ.
* **Objective-C interop** is switched on for the shims and the app (`-enable-objc-interop`,
  `-disable-objc-attr-requires-foundation-module`, `-import-module ObjectiveC`) because the app uses `@objc`, `#selector` and
  optional protocol requirements. `shims/ObjectiveC` provides `NSObjectProtocol` and `Selector`. ObjectiveC does not
  re-export Foundation (it does not on Apple platforms either), so a file that forgets `import Foundation` fails.
* **Foundation** is swift-corelibs-foundation, not Apple's. An API that exists there but not in Apple's Foundation would pass here.
  `Darwin` is an empty module re-exporting Glibc so `#if canImport(Darwin)` is true (it makes `ScanRecoveryStore`'s
  `isExcludedFromBackup` branch compile); C functions therefore come from Glibc.
* **Device vs simulator**: `targetEnvironment(simulator)` branches are compiled on a rewritten copy (see the table).
* **Pointers**: see "Harness artifact".

## What this does NOT prove

* That Apple's real signatures equal the shims beyond what the documentation pages show. The pages are lossy (builders,
  hidden constraints, `@preconcurrency`, `@_inheritActorContext`, availability of individual overloads, overload ranking),
  and the 18 + 6 + 10 + 553 items above are exactly where this is known.
* Anything about runtime: layout, gestures, ARKit/RoomPlan callbacks and threading, memory, VoiceOver output, whether an
  `#available` fallback *works* (the audit only checks that a guard exists), a missing environment object reached through a
  path the textual audit does not see (UIKit hosting, a `private func` that builds a view, a dynamic `AnyView`).
* APIs outside the shimmed Apple modules: Foundation (real corelibs), the standard library and Observation are the Linux ones,
  so their availability (iOS 17.0) and Apple-only differences are not checked.
* Swift 6 language mode: the app is Swift 5; `--strict` output is informational.
* The macro `#Preview` as Xcode expands it, SwiftData/AppIntents/other macros (none are used), `@Observable`'s real expansion
  (the toolchain's Observation macro is used).
* The Xcode project: `ios/project.yml`, XcodeGen output, Info.plist keys, entitlements, privacy manifest, signing, asset
  catalogs, the way Xcode links `NexaFixCore`, build settings other than the language version and concurrency level.
* Type-checker speed of big view bodies on Xcode's compiler.
* That the environment, collision and availability audits are complete: they are textual or documentation-derived. The
  availability audit covers only symbols the shims tag from documentation pages.

## Extending it

A new SwiftUI/UIKit/... call in the app that the shim lacks shows up as "no member" / "cannot find". Add the declaration with
`docs/docs.py scaffold <Module/Parent> <name>` (prints tagged lines for every cached overload; `docs.py show` / `find` to look
at pages), paste it into the right `shims/` file, then run `docs/verify_shims.py sync && docs/verify_shims.py verify` and
`run.sh`. The generated files can also be regenerated: `NEXAFIX_DOCS_CACHE=<dir> python3 docs/gen/<module>.py` (the docs cache
is filled by `docs.py crawl` / `docs.py refs`, about 9,000 pages; `docs/gen/autoprune.py` drops what does not compile;
`docs/gen/unprune.py` re-admits declarations once the missing type exists). Regenerating overwrites hand edits of generated
files, so edit `docs/gen/*.py` instead. After changing shims run `verify_shims.py sync` so `declarations.json` matches.

## Files

```
run.sh                       the harness            triage.py / known-harness-artifacts.tsv   error classification, pinned artifact
prove_bites.sh               the fault-injection proof      shims/MODULES                              module build order
shims/<Module>/*.swift       the shims              shims/_macros/PreviewsMacros.swift        #Preview stand-in (SwiftSyntax)
docs/docs.py                 fetch/search Apple's documentation JSON
docs/verify_shims.py         tag parser + fidelity verifier (sync / verify / report / avail)
docs/declarations.json       declarations of every tagged page (generated by `sync`)
docs/framework_names.py      module-level type names of Apple frameworks, name-collision lint   docs/framework-types.json (data)
docs/gen/                    generators, mk.py helpers, prune.txt (the 553 dropped declarations with reasons)
audit/check_environment.py   @Environment(X.self) injection audit
audit/check_availability.py  uses of APIs newer than iOS 17.0 and their #available guards (via swiftc -dump-ast)
```
