#!/bin/bash
# Shared by run.sh, controller/run.sh and mutation-check.sh. Source it; do not run it.
#
# Variables it sets:  checks_dir  ios  work  app
#   RECOVERY_CHECKS_WORK   where everything is built (default: $TMPDIR or /tmp, in nexafix-recovery-checks)
#   APP_DIR                the app sources to test (default: ios/NexaFixScan); mutation-check.sh points it at a copy

checks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ios="$(cd "$checks_dir/../.." && pwd)"
work="${RECOVERY_CHECKS_WORK:-${TMPDIR:-/tmp}/nexafix-recovery-checks}"
app="${APP_DIR:-$ios/NexaFixScan}"
mkdir -p "$work"

sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

# A fingerprint of NexaFixCore's package file and sources, so an unchanged Core is neither copied nor rebuilt.
core_stamp() {
    (
        cd "$ios/NexaFixCore"
        find Package.swift Sources -type f | LC_ALL=C sort
        find Package.swift Sources -type f -print0 | LC_ALL=C sort -z | xargs -0 cat
    ) | sha | cut -c1-64
}

# Copies NexaFixCore (package file without its test target, and Sources) to $work/core-src and builds that copy
# into $work/core, so the working tree is never written to. Sets CORE_BIN to the folder with Modules/ and the objects.
build_core() {
    local snap="$work/core-src" stamp
    stamp="$(core_stamp)"
    if [ ! -f "$snap/.stamp" ] || [ "$(cat "$snap/.stamp")" != "$stamp" ]; then
        rm -rf "$snap"
        mkdir -p "$snap"
        cp -R "$ios/NexaFixCore/Sources" "$snap/Sources"
        grep -v 'testTarget' "$ios/NexaFixCore/Package.swift" > "$snap/Package.swift"
        echo "$stamp" > "$snap/.stamp"
    fi
    local log
    if ! log="$(cd "$snap" && swift build --build-path "$work/core" 2>&1)"; then
        echo "$log" | tail -n 40
        echo "recovery-checks: building NexaFixCore failed" >&2
        return 1
    fi
    CORE_BIN="$(cd "$snap" && swift build --build-path "$work/core" --show-bin-path)"
}

# Compiles the coordinator checks against the app files in $1 (default $app); the binary goes to $work/coordinator-checks
# (or $2). The app's real files are compiled as they are. PropertyActions.swift holds the coordinator and ScanIntake.
# RECOVERY_CHECKS_OPT: optimisation flag, default -O (mutation-check.py uses -Onone).
build_coordinator() {
    local dir="${1:-$app}" out="${2:-$work/coordinator-checks}"
    swiftc -swift-version 5 "${RECOVERY_CHECKS_OPT:--O}" \
        -I "$CORE_BIN/Modules" \
        "$CORE_BIN"/NexaFixCore.build/*.o \
        "$dir/App/AppModel.swift" "$dir/App/AppSettings.swift" "$dir/App/UserFacingError.swift" \
        "$dir/App/MeasurementFormatting.swift" \
        "$dir/Screens/PropertyActions.swift" \
        "$dir/Capture/ScanResult.swift" "$dir/Capture/ScanRecoveryStore.swift" "$dir/Capture/DeviceCapability.swift" \
        "$checks_dir/coordinator/main.swift" \
        -o "$out"
}

need_swift() {
    command -v swiftc >/dev/null 2>&1 || {
        echo "recovery-checks: swiftc not found. Put a Swift 5.9+ toolchain on PATH (Linux or macOS)." >&2
        exit 2
    }
}
