#!/usr/bin/env bash
# Proves that the check bites: injects nine faults (five cross-file ones, then four mistakes against Apple's APIs), one at a time, into a COPY of ios/NexaFixScan, shows that run.sh fails
# on each, and shows that the real sources were not touched (sha256 of every file before and after).
#
#   ios/tools/typecheck/prove_bites.sh
#
# The faults (each is a mistake a cross-file edit really produces):
#   1 wrong argument label      RootView calls RoomView(propertyId:roomID:)   -> RoomView takes propertyID:
#   2 removed member            AppModel.retryUnsavedSaves() deleted           -> RootView/PropertyView still call it
#   3 duplicate type name       a second `enum Spacing` in another file        -> Theme.swift already declares Spacing
#   4 missing import            `import UIKit` removed from Theme.swift        -> UIColor/UITraitCollection unknown there
#   5 optional misuse           presentedError?.title -> presentedError.title  -> presentedError is AppError?
#   6-9 (beyond the five)       a wrong ForEach, ARSession.run, RoomCaptureSession.run and AVCaptureDevice.requestAccess call,
#                               which only fail if the shims carry the documented signatures
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS="$(cd "$HERE/../.." && pwd)"
APP="$IOS/NexaFixScan"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nexafix-bites.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

tree_hash() { ( cd "$APP" && find . -name '*.swift' | sort | xargs sha256sum | sha256sum | cut -c1-16 ); }
BEFORE="$(tree_hash)"
echo "real sources: $(find "$APP" -name '*.swift' | wc -l | tr -d ' ') files, tree hash $BEFORE"

# Build Core and the shim modules once (not part of the loop); then each run reuses them.
"$HERE/run.sh" --quick >/dev/null 2>&1 || true
export SKIP_CORE=1 SKIP_SHIMS=1

run_on() {  # $1 = copy dir; prints run.sh's error lines, returns its status
  APP_DIR="$1" "$HERE/run.sh" --quick 2>&1 | grep -E '^\s+(\S+\.swift|macro expansion)[^ ]*: error:|-> [0-9]+ errors|RESULT' | head -${SHOW:-8}
  return "${PIPESTATUS[0]}"
}

mutate() {  # $1 = copy dir, $2 = python snippet working on the dict `files` {relative path: text}
  python3 - "$1" "$2" <<'PY'
import os, sys, re
root, code = sys.argv[1], sys.argv[2]
def edit(rel, old, new):
    p = os.path.join(root, rel); s = open(p).read()
    assert s.count(old) == 1, f'{rel}: expected exactly one occurrence of {old!r}, found {s.count(old)}'
    open(p, 'w').write(s.replace(old, new))
def delete_func(rel, header):
    p = os.path.join(root, rel); s = open(p).read()
    i = s.index(header); j = s.index('{', i); d = 0
    for k in range(j, len(s)):
        d += (s[k] == '{') - (s[k] == '}')
        if d == 0: break
    open(p, 'w').write(s[:i] + s[k + 1:])
exec(code)
PY
}

fresh_copy() { rm -rf "$WORK/app"; cp -r "$APP" "$WORK/app"; }

ok=0; fail=0
echo; echo "== baseline: an untouched copy must pass"
fresh_copy
if run_on "$WORK/app"; then echo "   baseline passes"; else echo "   BASELINE FAILS: the experiment is invalid"; exit 3; fi

fault() {  # $1 = number, $2 = title, $3 = python mutation
  echo; echo "== fault $1: $2"
  fresh_copy
  if ! mutate "$WORK/app" "$3"; then echo "   mutation could not be applied (the sources changed?)"; fail=$((fail+1)); return; fi
  if run_on "$WORK/app"; then echo "   NOT CAUGHT"; fail=$((fail+1)); else echo "   caught"; ok=$((ok+1)); fi
}

fault 1 "wrong argument label across files (RootView -> RoomView)" \
  "edit('Screens/RootView.swift', 'RoomView(propertyID: propertyID, roomID: roomID)', 'RoomView(propertyId: propertyID, roomID: roomID)')"
fault 2 "removed member (AppModel.retryUnsavedSaves)" \
  "delete_func('App/AppModel.swift', 'func retryUnsavedSaves()')"
fault 3 "duplicate type name (second enum Spacing)" \
  "edit('Screens/AboutView.swift', 'import SwiftUI', 'import SwiftUI\n\nenum Spacing { static let extra: CGFloat = 1 }')"
fault 4 "missing import (UIKit removed from Theme.swift)" \
  "edit('DesignSystem/Theme.swift', 'import UIKit\n', '')"
fault 5 "optional misuse (AppModel.presentedError is optional)" \
  "edit('Screens/RootView.swift', '.alert(model.presentedError?.title ?? \"\", isPresented', '.alert(model.presentedError.title, isPresented')"

echo; echo "-- beyond the five: the shims themselves must bite on mistakes against Apple's APIs --"

fault 6 "SwiftUI: ForEach over elements that are not Identifiable, id: removed (RoomNameSheet)" \
  "edit('Capture/RoomNameSheet.swift', 'ForEach(flow.suggestedKinds, id: \\\\.self) { option in', 'ForEach(flow.suggestedKinds) { option in')"
fault 7 "ARKit: ARSession.run(_:options:) with a wrong label (ScanSessionController)" \
  "edit('Capture/ScanSessionController.swift', 'arSession.run(Self.worldTrackingConfiguration(), options: options)', 'arSession.run(Self.worldTrackingConfiguration(), option: options)')"
fault 8 "RoomPlan: RoomCaptureSession.run(configuration:) with a wrong label (ScanSessionController)" \
  "edit('Capture/ScanSessionController.swift', 'view.captureSession.run(configuration: configuration)', 'view.captureSession.run(config: configuration)')"
fault 9 "AVFoundation: AVCaptureDevice.requestAccess(for:) with a wrong label (DeviceCapability)" \
  "edit('Capture/DeviceCapability.swift', 'AVCaptureDevice.requestAccess(for: .video)', 'AVCaptureDevice.requestAccess(forMediaType: .video)')"

echo; echo "== real sources untouched?"
AFTER="$(tree_hash)"
[ "$BEFORE" = "$AFTER" ] && echo "   tree hash unchanged ($AFTER)" || { echo "   TREE HASH CHANGED: $BEFORE -> $AFTER"; exit 4; }
echo; echo "faults caught: $ok of 9 ($fail not caught); faults 1-5 are the required set, 6-9 test the shims"
[ "$ok" = 9 ]
