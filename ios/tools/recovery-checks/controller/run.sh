#!/bin/bash
# Builds the scan screen's controller (ScanSessionController, with ScanRecoveryStore, ScanResult, DeviceCapability
# and CapturedRoomMapper) against stub ARKit/RoomPlan/UIKit/AVFoundation/simd modules and runs the checks in
# main.swift. The app's files are copied into a staging folder and compiled as they are, except for two changes the
# Linux stubs need (below), which are checked to have taken effect. Needs only a Swift toolchain.
#
#   ios/tools/recovery-checks/controller/run.sh
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
need_swift

here="$checks_dir/controller"
stage="$work/controller"
rm -rf "$stage/app" "$stage/stubs" "$stage/Package.swift"
mkdir -p "$stage/app"

cp "$here/Package.swift" "$stage/Package.swift"
cp -R "$here/stubs" "$stage/stubs"

# NexaFixCore's sources become a target of the staging package (a package cannot point at a folder outside itself).
stamp="$(core_stamp)"
if [ ! -f "$stage/core.stamp" ] || [ "$(cat "$stage/core.stamp")" != "$stamp" ]; then
    rm -rf "$stage/core"
    cp -R "$ios/NexaFixCore/Sources/NexaFixCore" "$stage/core"
    echo "$stamp" > "$stage/core.stamp"
fi

for f in ScanResult DeviceCapability CapturedRoomMapper ScanSessionController ScanRecoveryStore; do
    cp "$app/Capture/$f.swift" "$stage/app/$f.swift"
done
cp "$here/HapticsStub.swift" "$stage/app/HapticsStub.swift"
cp "$here/main.swift" "$stage/app/main.swift"

# 1. On Apple platforms ARSessionDelegate's methods are @objc optional and the bridge forwards with `previous?.session?(...)`;
#    the stub protocol has default implementations instead, so the extra `?` is dropped in the staged copy.
# 2. The test reads ForegroundClock, which the app keeps private.
controller="$stage/app/ScanSessionController.swift"
sed -i.bak -E '/previous\?\./ s/\?\(/(/g' "$controller"
sed -i.bak 's/^private final class ForegroundClock/final class ForegroundClock/' "$controller"
rm -f "$controller.bak"
if grep -Eq 'previous\?\.[A-Za-z]+\?\(' "$controller" || ! grep -q '^final class ForegroundClock' "$controller"; then
    echo "recovery-checks: the staging edits of ScanSessionController.swift did not apply; update controller/run.sh" >&2
    exit 1
fi

log="$work/controller-build.log"
if ! ( cd "$stage" && swift build --build-path "$work/controller-build" >"$log" 2>&1 ); then
    tail -n 60 "$log"
    echo "recovery-checks: building the controller checks failed (full log: $log)" >&2
    exit 1
fi
bin="$(cd "$stage" && swift build --build-path "$work/controller-build" --show-bin-path)"
"$bin/ScanApp"
