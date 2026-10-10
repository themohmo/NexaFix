#!/bin/bash
# Keeps your Apple signing choices across `xcodegen generate`.
#
# Why: the Xcode project is re-created from project.yml every time you run `xcodegen generate`, and Xcode
# stores the Team you pick in Signing & Capabilities inside that generated project, so it is lost.
# This script copies your Team (and your Bundle Identifier, if you changed it) out of the generated project
# into ios/Config/Local.xcconfig, which is git-ignored and read by ios/Config/Signing.xcconfig.
#
# Use: pick your Team in Xcode once, close Xcode (or at least save), then
#     ios/tools/remember-signing.sh          # writes ios/Config/Local.xcconfig
#     ios/tools/remember-signing.sh --force  # replaces an existing Local.xcconfig
# After that `cd ios && xcodegen generate` keeps the Team and the identifier.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
ios="$(cd "$here/.." && pwd)"
pbx="${NEXAFIX_PBXPROJ:-$ios/NexaFixScan.xcodeproj/project.pbxproj}"
out="$ios/Config/Local.xcconfig"
force=0
[ "${1:-}" = "--force" ] && force=1

if [ ! -f "$pbx" ]; then
    echo "Cannot find $pbx" >&2
    echo "Run 'cd ios && xcodegen generate', open the project, pick your Team in Signing & Capabilities, then run this again." >&2
    exit 1
fi
if [ -f "$out" ] && [ "$force" -eq 0 ]; then
    echo "$out already exists:" >&2
    sed 's/^/    /' "$out" >&2
    echo "Delete it, or run with --force to replace it." >&2
    exit 1
fi

# First value Xcode wrote for each setting in the target's build configurations. A Team ID is 10
# letters/digits; a bundle identifier is letters, digits, dots and hyphens (Xcode may or may not quote it).
team="$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM = "?([A-Z0-9]{10})"?;[[:space:]]*$/\1/p' "$pbx" | head -n 1)" || true
bundle="$(sed -nE 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = "?([A-Za-z0-9.-]+)"?;[[:space:]]*$/\1/p' "$pbx" | head -n 1)" || true

if [ -z "$team" ] && [ -z "$bundle" ]; then
    echo "Nothing to remember yet: the project has no Team and no custom Bundle Identifier." >&2
    echo "In Xcode: NexaFixScan target > Signing & Capabilities > Team, pick your Apple ID, then run this again." >&2
    exit 1
fi

{
    echo "// Written by ios/tools/remember-signing.sh. Personal and git-ignored; edit freely."
    [ -n "$team" ] && echo "DEVELOPMENT_TEAM = $team"
    [ -n "$bundle" ] && echo "PRODUCT_BUNDLE_IDENTIFIER = $bundle"
} > "$out"

echo "Wrote $out:"
sed 's/^/    /' "$out"
echo "Now 'cd ios && xcodegen generate' will keep these."
