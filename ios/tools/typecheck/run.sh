#!/usr/bin/env bash
# Typechecks EVERY file under ios/NexaFixScan together, against the real NexaFixCore and the Apple-API shims
# in ./shims. No Xcode needed: runs on Linux with the open-source Swift toolchain (Swift 6.0 or newer) and python3.
# See README.md for what this proves and, just as important, what it does not.
#
#   ios/tools/typecheck/run.sh                 three passes + audits (about 2 minutes once Core is built)
#                                                device Debug (-D DEBUG), device Release, Simulator branches (Debug)
#                                                then the shim verifier and the static audits
#   ios/tools/typecheck/run.sh --strict        also report -strict-concurrency=complete (information only)
#   ios/tools/typecheck/run.sh --quick         device Debug pass only (the fault-injection loop uses this)
#   ios/tools/typecheck/run.sh --no-audit      passes only
#   APP_DIR=/some/copy ios/tools/typecheck/run.sh --quick     check another copy of the app sources
#   SWIFT_BIN=/path/to/toolchain/usr/bin ios/tools/typecheck/run.sh
#   TYPECHECK_OUT=/some/dir ...                build products (default ios/tools/typecheck/.build)
#   SKIP_CORE=1 SKIP_SHIMS=1                   reuse the Core build / shim modules in $TYPECHECK_OUT
#   ONLY_SHIMS=1 [MODULE_ORDER="A B"]          build just the shim modules (fast loop while writing shims)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS="$(cd "$HERE/../.." && pwd)"
APP="${APP_DIR:-$IOS/NexaFixScan}"
APP="$(cd "$APP" && pwd)"
CORE_SRC="$IOS/NexaFixCore"
OUT="${TYPECHECK_OUT:-$HERE/.build}"
SHIMS="$HERE/shims"
MODS="$OUT/modules"
STRICT=0; QUICK=0; RELEASE=1; AUDIT=1
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    --quick) QUICK=1; RELEASE=0; AUDIT=0 ;;
    --no-audit) AUDIT=0 ;;
    --debug-only) RELEASE=0 ;;
    -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
[ -n "${SWIFT_BIN:-}" ] && export PATH="$SWIFT_BIN:$PATH"
command -v swiftc >/dev/null || { echo "swiftc not found: put a Swift toolchain on PATH or set SWIFT_BIN" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 2; }
echo "swiftc: $(swiftc --version 2>&1 | head -1)"

mkdir -p "$OUT" "$MODS"

# 1. The real Core, built from a snapshot of the working tree (no .build directory copied in).
if [ -z "${SKIP_CORE:-}" ]; then
  rm -rf "$OUT/core"; mkdir -p "$OUT/core/ios"
  cp -r "$CORE_SRC" "$OUT/core/ios/"; rm -rf "$OUT/core/ios/NexaFixCore/.build"
  echo "== building NexaFixCore"
  ( cd "$OUT/core/ios/NexaFixCore" && swift build --build-path "$OUT/core/build" 2>&1 | tail -2 ) || exit 1
fi
CORE_MODS="$OUT/core/build/debug/Modules"
[ -d "$CORE_MODS" ] || { echo "Core modules missing at $CORE_MODS" >&2; exit 1; }

# 2. The macro plugin that expands #Preview (SwiftSyntax from the toolchain).
PLUGIN="$OUT/PreviewsMacros"
HOSTLIB="$(dirname "$(command -v swiftc)")/../lib/swift/host"
if [ ! -x "$PLUGIN" ] || [ "$SHIMS/_macros/PreviewsMacros.swift" -nt "$PLUGIN" ]; then
  echo "== building #Preview macro plugin"
  swiftc -parse-as-library -o "$PLUGIN" "$SHIMS/_macros/PreviewsMacros.swift" -I "$HOSTLIB" -L "$HOSTLIB" \
    -lSwiftCompilerPluginMessageHandling -lSwiftSyntax -lSwiftSyntaxMacros -lSwiftDiagnostics -lSwiftParser \
    -lSwiftOperators -lSwiftParserDiagnostics -lSwiftSyntaxBuilder -lSwiftBasicFormat -lSwiftSyntaxMacroExpansion \
    -Xlinker -rpath -Xlinker "$HOSTLIB" 2>&1 | head -20
  [ -x "$PLUGIN" ] || { echo "macro plugin did not build" >&2; exit 1; }
fi

# Objective-C interop is switched on for the shims and the app: the Linux toolchain has none, but the app uses
# @objc / #selector / NSObject subclasses / optional protocol requirements exactly as it would on iOS.
# -import-module ObjectiveC reproduces "Foundation re-exports ObjectiveC" (needed for #selector).
OBJC_FLAGS=(-Xfrontend -enable-objc-interop -Xfrontend -disable-objc-attr-requires-foundation-module -Xfrontend -import-module -Xfrontend ObjectiveC)

# 3. The shim modules, in dependency order (a module only sees the ones built before it).
[ -z "${MODULE_ORDER:-}" ] && [ -z "${SKIP_SHIMS:-}" ] && rm -f "$MODS"/*.swiftmodule "$MODS"/*.swiftdoc
MODULE_ORDER="${MODULE_ORDER:-$(cat "$SHIMS/MODULES")}"
[ -n "${SKIP_SHIMS:-}" ] && MODULE_ORDER=""    # reuse the modules built by an earlier run (fault-injection loop)
for m in $MODULE_ORDER; do
  [ "${QUIET_MODULES:-}" = 1 ] || echo "== shim module $m"
  EXTRA_OBJC=("${OBJC_FLAGS[@]}"); [ "$m" = ObjectiveC ] && EXTRA_OBJC=(-Xfrontend -enable-objc-interop -Xfrontend -disable-objc-attr-requires-foundation-module)
  swiftc -emit-module -module-name "$m" -parse-as-library -swift-version 5 -I "$MODS" "${EXTRA_OBJC[@]}" \
    -emit-module-path "$MODS/$m.swiftmodule" -load-plugin-executable "$PLUGIN#PreviewsMacros" \
    $(find "$SHIMS/$m" -name '*.swift' | sort) 2>&1 | grep -E ': error:' | head -40
  [ -f "$MODS/$m.swiftmodule" ] || { echo "shim module $m failed to build" >&2; exit 1; }
done

[ -n "${ONLY_SHIMS:-}" ] && exit 0

# 4. The app: all files in one module.
NFILES=$(find "$APP" -name '*.swift' | wc -l | tr -d ' ')
echo "app: $APP ($NFILES swift files)"

SWIFT_APP_FLAGS=(-wmo -swift-version 5 -module-name NexaFixScan -parse-as-library -I "$MODS" -I "$CORE_MODS" "${OBJC_FLAGS[@]}" -load-plugin-executable "$PLUGIN#PreviewsMacros")

# check LABEL SOURCE_ROOT [extra swiftc flags]: one pass over every file under SOURCE_ROOT
check() {
  local label="$1" root="$2"; shift 2
  local files; files=$(find "$root" -name '*.swift' | sort)
  swiftc -typecheck "${SWIFT_APP_FLAGS[@]}" "$@" $files > "$OUT/$label.log" 2>&1
  local warns; warns=$(grep -c ': warning:' "$OUT/$label.log")
  echo "== $label: $NFILES files, $warns warnings (log $OUT/$label.log)"
  python3 "$HERE/triage.py" "$OUT/$label.log" "$APP" "$root"
}

status=0
check device-debug "$APP" -strict-concurrency=minimal -D DEBUG || status=1
if [ "$RELEASE" = 1 ]; then
  check device-release "$APP" -strict-concurrency=minimal || status=1
fi
if [ "$QUICK" = 0 ]; then
  # The `#if targetEnvironment(simulator)` branches cannot be switched on here (a simulator triple is rejected on Linux),
  # so they are checked on a copy where that condition reads `os(Linux)`, which is true. Same line numbers as the original.
  SIM="$OUT/simulator-app"
  rm -rf "$SIM"; mkdir -p "$SIM"; cp -r "$APP/." "$SIM/"
  find "$SIM" -name '*.swift' -exec sed -i 's/targetEnvironment(simulator)/os(Linux)/g' {} +
  check simulator-debug "$SIM" -strict-concurrency=minimal -D DEBUG || status=1
fi
if [ "$STRICT" = 1 ]; then
  echo "== strict-concurrency=complete (information only; only the Swift 5 minimal passes above decide)"
  swiftc -typecheck "${SWIFT_APP_FLAGS[@]}" -strict-concurrency=complete -D DEBUG $(find "$APP" -name '*.swift' | sort) > "$OUT/strict-complete.log" 2>&1
  echo "   $(grep -c ': error:' "$OUT/strict-complete.log") errors, $(grep -c ': warning:' "$OUT/strict-complete.log") warnings; distinct kinds:"
  grep -E '^/.*: (warning|error):' "$OUT/strict-complete.log" | sed -E 's/^[^ ]+ (warning|error): //' | sed -E "s/'[^']*'/'_'/g" | sort | uniq -c | sort -rn | head -12 | sed 's/^/   /'
fi

# 5. Audits that the compiler cannot do for us.
if [ "$AUDIT" = 1 ]; then
  echo "== shims vs Apple documentation"
  python3 "$HERE/docs/verify_shims.py" verify | tail -3 || status=1
  echo "== name collisions (Core / app vs every module-level type of the imported Apple frameworks)"
  python3 "$HERE/docs/framework_names.py" collisions | tail -4 || status=1
  echo "== @Environment(Model.self) injection"
  python3 "$HERE/audit/check_environment.py" "$APP" || status=1
  echo "== APIs newer than the iOS 17.0 deployment target"
  python3 "$HERE/audit/check_availability.py" "$APP" "$OUT" "${SWIFT_APP_FLAGS[@]}" || status=1
fi
[ "$status" = 0 ] && echo "RESULT: OK" || echo "RESULT: FAILED"
exit $status
