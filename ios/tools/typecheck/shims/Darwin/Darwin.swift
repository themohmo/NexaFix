// SHIM of Darwin.
//
// Only so that `#if canImport(Darwin)` is true here as it is on iOS, which makes the app's Darwin-only branch
// (ScanRecoveryStore: exclude the folder from backup) get type-checked instead of skipped. The C library of this Linux
// toolchain (Glibc) stands in for it; the module declares nothing of its own, so there is nothing to verify against the docs.
@_exported import Glibc
