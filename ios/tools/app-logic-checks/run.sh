#!/bin/bash
# Builds NexaFixCore and runs the plain-Swift app-logic checks against it. Needs only a Swift toolchain
# (Linux or macOS); no Xcode project, simulator or Apple framework beyond Foundation.
#
#   ios/tools/app-logic-checks/run.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
ios="$(cd "$here/../.." && pwd)"
app="$ios/NexaFixScan/App"
work="${TMPDIR:-/tmp}/nexafix-app-logic-checks"
mkdir -p "$work"

( cd "$ios/NexaFixCore" && swift build --build-path "$work/core" >/dev/null )
bin="$(cd "$ios/NexaFixCore" && swift build --build-path "$work/core" --show-bin-path)"

swiftc -swift-version 5 -O \
    -I "$bin/Modules" \
    "$bin"/NexaFixCore.build/*.o \
    "$app/MeasurementFormatting.swift" "$app/AppSettings.swift" "$app/UserFacingError.swift" \
    "$here/main.swift" \
    -o "$work/app-logic-checks"

"$work/app-logic-checks"
