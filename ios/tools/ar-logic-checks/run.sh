#!/bin/bash
# Builds NexaFixCore and runs the plain-Swift checks for the AR screen's decision logic against it: when the
# saved room has really lined up with the real one (RelocalisationTracker), what the status pill and the tape
# card say (ARStatusSummary), and the camera-ray maths (ARCameraRay). Needs only a Swift toolchain (Linux or
# macOS); no Xcode project, simulator or Apple framework beyond Foundation.
#
#   ios/tools/ar-logic-checks/run.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
ios="$(cd "$here/../.." && pwd)"
ar="$ios/NexaFixScan/AR"
work="${TMPDIR:-/tmp}/nexafix-ar-logic-checks"
mkdir -p "$work"

( cd "$ios/NexaFixCore" && swift build --build-path "$work/core" >/dev/null )
bin="$(cd "$ios/NexaFixCore" && swift build --build-path "$work/core" --show-bin-path)"

# Both app files keep their Apple-framework parts behind #if canImport, so they compile here as plain Swift.
swiftc -swift-version 5 -O \
    -I "$bin/Modules" \
    "$bin"/NexaFixCore.build/*.o \
    "$ar/ARTrackingStatus.swift" "$ar/ARProjection.swift" \
    "$here/main.swift" \
    -o "$work/ar-logic-checks"

"$work/ar-logic-checks"
