#!/bin/bash
# Regression checks for the code that decides when a scan's safety copy may be deleted, and what the person
# is told. Needs only a Swift toolchain (Linux or macOS): no Xcode project, simulator or Apple framework.
#
#   ios/tools/recovery-checks/run.sh                 both suites (coordinator, then controller)
#   ios/tools/recovery-checks/run.sh coordinator     launch-time recovery only (fast)
#   ios/tools/recovery-checks/run.sh controller      the scan screen's controller only
#
# Exit status 0 only if every check of the chosen suites passed (1: a check failed, 3: a harness failed to compile).
# See README.md.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need_swift

suite="${1:-all}"
status=0
case "$suite" in all|coordinator|controller) ;; *) echo "usage: run.sh [all|coordinator|controller]" >&2; exit 2 ;; esac

if [ "$suite" = all ] || [ "$suite" = coordinator ]; then
    echo "== coordinator: launch-time recovery (ScanRecoveryCoordinator, ScanRecoveryStore, ScanIntake)"
    build_core
    if ! build_coordinator; then
        echo "recovery-checks: compiling the coordinator checks failed" >&2
        exit 3
    fi
    "$work/coordinator-checks" || status=1
fi

if [ "$suite" = all ] || [ "$suite" = controller ]; then
    echo "== controller: ScanSessionController and the safety copy it writes"
    "$checks_dir/controller/run.sh" || status=1
fi

if [ "$status" -ne 0 ]; then echo "recovery-checks: FAILED" >&2; else echo "recovery-checks: all checks passed"; fi
exit "$status"
