// Checks for the AR screen's decision logic that needs no Apple framework: RelocalisationTracker (has the saved
// room lined up with the real one?), ARStatusSummary (what the pill and the tape card say) and ARCameraRay
// (the maths around ARKit's projection). Run with ./run.sh; it works on Linux and macOS and prints
// "checks: N, failures: M".
import Foundation
import NexaFixCore

var failures = 0
var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() { failures += 1; print("FAIL line \(line): \(message)") }
}

func snap(_ tracking: TrackingSnapshot.Tracking, _ time: Double, map: TrackingSnapshot.WorldMap = .loaded,
          mapping: TrackingSnapshot.Mapping = .notAvailable, interrupted: Bool = false) -> TrackingSnapshot {
    TrackingSnapshot(tracking: tracking, mapping: mapping, worldMap: map, isInterrupted: interrupted, time: time)
}

/// Snapshots as ARKit delivers them: a steady stream, never more than half a second apart. Ingests one at
/// `from`, then every half second, and a last one exactly at `to`. Returns the phase after the last one.
@discardableResult
func feed(_ r: inout RelocalisationTracker, _ tracking: TrackingSnapshot.Tracking, from: Double, to: Double,
          mapping: TrackingSnapshot.Mapping = .notAvailable, interrupted: Bool = false) -> RelocalisationPhase {
    var t = from
    while t < to {
        r.ingest(snap(tracking, t, mapping: mapping, interrupted: interrupted))
        t += 0.5
    }
    return r.ingest(snap(tracking, to, mapping: mapping, interrupted: interrupted))
}

func summary(_ tracker: RelocalisationTracker, _ s: TrackingSnapshot) -> ARStatusSummary {
    ARStatusSummary.make(phase: tracker.phase, snapshot: s)
}

// ---------- 1. The normal path: relocalising, then normal, is aligned ----------
do {
    var r = RelocalisationTracker()
    check(r.ingest(snap(.initializing, 0)) == .searching, "starts searching")
    check(r.ingest(snap(.relocalizing, 1)) == .searching, "relocalising keeps searching")
    check(r.ingest(snap(.normal, 4)) == .aligned, "normal after relocalising is aligned")
    let s = summary(r, snap(.normal, 4))
    check(s.overlayAllowed, "overlay allowed when aligned and normal")
    check(s.phase == .aligned, "the summary carries the phase")
    // A brief dip keeps the alignment but hides the overlay.
    r.ingest(snap(.excessiveMotion, 5))
    check(r.phase == .aligned, "a dip keeps the alignment")
    check(!summary(r, snap(.excessiveMotion, 5)).overlayAllowed, "overlay hidden during a dip")
    check(summary(r, snap(.excessiveMotion, 5)).title == "Slow down", "slow-down title")
    r.ingest(snap(.normal, 6))
    check(r.phase == .aligned, "back to normal is still aligned")
    // Losing the frame means searching again.
    r.ingest(snap(.relocalizing, 7))
    check(r.phase == .searching, "relocalising after alignment is searching again")
    r.ingest(snap(.normal, 9))
    check(r.phase == .aligned, "aligned again")
}

// ---------- 2. Normal without ever relocalising is NOT aligned, whatever the mapping status says ----------
do {
    var r = RelocalisationTracker()
    for (i, mapping) in [TrackingSnapshot.Mapping.notAvailable, .limited, .extending, .mapped].enumerated() {
        r.ingest(snap(.normal, Double(i), mapping: mapping))
        check(r.phase == .searching, "normal with mapping \(mapping) but no relocalising is not trusted")
        check(!summary(r, snap(.normal, Double(i), mapping: mapping)).overlayAllowed, "no overlay for \(mapping)")
    }
    // It runs out of time honestly instead of drawing numbers that might be in the wrong place.
    check(feed(&r, .normal, from: 4, to: 24.9, mapping: .mapped) == .searching, "still searching just before 25 s")
    check(r.ingest(snap(.normal, 25, mapping: .mapped)) == .failed(.timedOut), "times out into the honest card")
    // Relocalising after all, then normal, still earns the overlay.
    check(r.ingest(snap(.relocalizing, 25.5)) == .failed(.timedOut), "still failed on the relocalising frame")
    check(r.ingest(snap(.normal, 26)) == .aligned, "a late relocalisation recovers")
}

// ---------- 3. Timeout, and "Keep trying" as a fresh tracker ----------
do {
    var r = RelocalisationTracker()
    check(feed(&r, .relocalizing, from: 100, to: 124.9) == .searching, "still searching before 25 s")
    check(r.ingest(snap(.relocalizing, 125)) == .failed(.timedOut), "timed out at 25 s")
    let s = summary(r, snap(.relocalizing, 125))
    check(s.offersKeepTrying, "keep trying is offered after a timeout")
    check(s.message == ARStatusSummary.unalignedMessage, "unaligned message")
    check(s.title == "Not lined up", "title")
    check(!s.overlayAllowed, "no overlay when failed")
    check(s.tapeSaveNote == "Scanned. Can't be saved until the overlay lines up with the room.", "timed-out save note")
    // Keep trying restarts the AR session; the controller starts a new tracker.
    var again = RelocalisationTracker()
    check(feed(&again, .relocalizing, from: 130, to: 154.9) == .searching, "a full new window")
    check(again.ingest(snap(.relocalizing, 155)) == .failed(.timedOut), "times out again after another 25 s")
    // The time-out is not a dead end: ARKit relocalising late still lines up.
    check(feed(&r, .normal, from: 125.5, to: 130) == .aligned, "late relocalisation recovers (relocalising was seen)")
}

// ---------- 4. Rooms with no usable map can never line up, and the card says so ----------
do {
    var r = RelocalisationTracker()
    check(r.ingest(snap(.normal, 0, map: .none, mapping: .mapped)) == .failed(.noWorldMap),
          "no map never aligns, even if normal and mapped")
    let s = summary(r, snap(.normal, 0, map: .none))
    check(!s.overlayAllowed && !s.offersKeepTrying, "no map: no overlay, no keep trying")
    check(s.message == ARStatusSummary.noMapMessage, "no map message")
    check(s.message?.contains("You can still measure") == true, "no map message says measuring still works")
    check(s.tapeSaveNote.hasPrefix("Scanned."), "a tape reading is always called scanned")
    check(s.tapeSaveNote.contains("no saved AR map"), "no map: the note says why saving is off")
    check(!s.tapeSaveNote.contains("until the overlay lines up"), "no map: never promises it will line up")
    check(s.tapeSaveNote.contains("Scan the room again"), "no map: says what to do")

    var u = RelocalisationTracker()
    check(u.ingest(snap(.normal, 0, map: .unreadable)) == .failed(.mapUnreadable), "unreadable map")
    let us = summary(u, snap(.normal, 0, map: .unreadable))
    check(us.tapeSaveNote.contains("couldn't be read"), "unreadable: the note says why")
    check(!us.tapeSaveNote.contains("until the overlay lines up"), "unreadable: never promises it will line up")
    check(!us.offersKeepTrying, "unreadable: no keep trying")
}

// ---------- 5. The aligned pill does not borrow the verified look ----------
do {
    let r: RelocalisationTracker = {
        var t = RelocalisationTracker()
        t.ingest(snap(.relocalizing, 0)); t.ingest(snap(.normal, 1))
        return t
    }()
    let s = summary(r, snap(.normal, 1))
    check(s.symbol != "checkmark.circle.fill" && !s.symbol.contains("checkmark"),
          "a check mark means laser-verified; lining up must not use it")
    check(s.tone == .good, "good tone")
    check(s.tapeSaveNote == "Scanned. Check with a laser before cutting.", "aligned save note keeps the joinery warning")
    // Every state's symbol: only verified labels (not the status pill) use a check mark.
    for t in [TrackingSnapshot.Tracking.initializing, .notAvailable, .relocalizing, .excessiveMotion, .insufficientFeatures, .normal] {
        check(!summary(r, snap(t, 2)).symbol.contains("checkmark"), "no check mark in the status pill for \(t)")
    }
}

// ---------- 6. Interruptions ----------
do {
    var r = RelocalisationTracker()
    r.ingest(snap(.relocalizing, 0)); r.ingest(snap(.normal, 2))
    check(r.phase == .aligned, "aligned")
    r.ingest(snap(.normal, 3, interrupted: true))
    check(r.phase == .searching, "an interruption means searching")
    check(summary(r, snap(.normal, 3, interrupted: true)).title == "AR paused", "paused title")
    r.ingest(snap(.normal, 4))
    check(r.phase == .searching, "normal after an interruption without relocalising is not trusted")
    r.ingest(snap(.relocalizing, 5)); r.ingest(snap(.normal, 6))
    check(r.phase == .aligned, "relocalised after the interruption")
}

// ---------- 7. Time with no frames does not count towards the timeout (stale timestamps) ----------
do {
    // The review's reproduction: aligned at t=5; an interruption is reported with the STALE last frame; the
    // first fresh frame arrives 60 s later, still relocalising. That must not time out at once.
    var r = RelocalisationTracker()
    feed(&r, .relocalizing, from: 1, to: 2)
    feed(&r, .normal, from: 2.5, to: 5)
    check(r.phase == .aligned, "aligned at t=5")
    r.ingest(snap(.normal, 5, interrupted: true))     // sessionWasInterrupted: stale frame, flagged
    check(r.phase == .searching, "interrupted")
    r.ingest(snap(.normal, 5))                         // sessionInterruptionEnded: stale frame again
    check(r.phase == .searching, "still searching after the interruption ends")
    check(r.ingest(snap(.relocalizing, 70)) == .searching, "first fresh frame 65 s later does NOT time out")
    check(feed(&r, .relocalizing, from: 70.5, to: 94.9) == .searching, "the 25 s window runs from the fresh frame")
    check(r.ingest(snap(.relocalizing, 95)) == .failed(.timedOut), "and ends 25 s after it")

    // The same without an interruption flag: ARKit simply delivered nothing for a while.
    var g = RelocalisationTracker()
    feed(&g, .relocalizing, from: 0, to: 1)
    check(g.ingest(snap(.relocalizing, 100)) == .searching, "a long gap with no frames is not search time")
    check(feed(&g, .relocalizing, from: 100.5, to: 124.9) == .searching, "window measured from the first frame after the gap")
    check(g.ingest(snap(.relocalizing, 125)) == .failed(.timedOut), "times out 25 s later")

    // Frames flowing normally (about 30 per second) still time out on schedule.
    var f = RelocalisationTracker()
    var t = 0.0
    var phase = RelocalisationPhase.searching
    while t < 24.9 { phase = f.ingest(snap(.relocalizing, t)); t += 1.0 / 30 }
    check(phase == .searching, "continuous frames: not yet at 24.9 s")
    while t < 25.2 { phase = f.ingest(snap(.relocalizing, t)); t += 1.0 / 30 }
    check(phase == .failed(.timedOut), "continuous frames: timed out by 25.2 s")

    // While the camera is taken the clock does not run, however long that lasts.
    var h = RelocalisationTracker()
    feed(&h, .relocalizing, from: 0, to: 10)
    feed(&h, .normal, from: 10.5, to: 70, interrupted: true)
    check(h.phase == .searching, "60 s of interruption is not search time")
    feed(&h, .relocalizing, from: 70.5, to: 90)
    check(h.phase == .searching, "and the first frame after it starts a fresh window")
    check(feed(&h, .relocalizing, from: 90.5, to: 95.4) == .searching, "still inside the fresh window")
    check(feed(&h, .relocalizing, from: 95.5, to: 96) == .failed(.timedOut), "the fresh window is 25 s from the first frame after it")
}

// ---------- 8. Summaries ----------
do {
    for t in [TrackingSnapshot.Tracking.initializing, .notAvailable, .relocalizing, .excessiveMotion, .insufficientFeatures, .normal] {
        let s = ARStatusSummary.make(phase: .searching, snapshot: snap(t, 0))
        check(!s.overlayAllowed, "searching never allows the overlay for \(t)")
        check(!s.title.isEmpty && !s.symbol.isEmpty && !s.spoken.isEmpty, "has text for \(t)")
        check(s.phase == .searching, "phase for \(t)")
        check(s.tapeSaveNote.hasPrefix("Scanned."), "tape note for \(t)")
    }
    check(ARStatusSummary.make(phase: .searching, snapshot: snap(.relocalizing, 0)).title == "Relocalising", "relocalising title")
    check(ARStatusSummary.make(phase: .aligned, snapshot: snap(.normal, 0, interrupted: true)).overlayAllowed == false,
          "an interrupted session never draws")
}

// ---------- 9. ARCameraRay ----------
do {
    let ray = ARCameraRay(position: Point3(0, 1.5, 0), forward: Point3(0, 0, -1))
    check(ray.isInFront(Point3(0, 1.5, -2)), "in front")
    check(!ray.isInFront(Point3(0, 1.5, 2)), "behind")
    check(!ray.isInFront(Point3(0, 1.5, -0.01)), "inside the near plane")
    check(abs(ray.distance(to: Point3(3, 1.5, -4)) - 5) < 1e-12, "distance")
    check(ray.clip(Point3(0, 0, -1), Point3(1, 0, -3)) != nil, "a segment fully in front is kept")
    check(ray.clip(Point3(0, 0, 1), Point3(1, 0, 3)) == nil, "a segment fully behind is dropped")
    if let (a, b) = ray.clip(Point3(-2, 1.5, -2), Point3(-2, 1.5, 2)) {
        check(abs(a.z - (-2)) < 1e-12, "the kept end is unchanged")
        check(abs(ray.depth(of: b) - ARCameraRay.nearDistance) < 1e-9, "the cut lands on the near plane")
        check(abs(b.x - (-2)) < 1e-12, "the cut stays on the line")
    } else { check(false, "a straddling segment should clip") }
    if let (a, b) = ray.clip(Point3(-2, 1.5, 2), Point3(-2, 1.5, -2)) {
        check(abs(ray.depth(of: a) - ARCameraRay.nearDistance) < 1e-9, "reverse order: the first end is cut")
        check(b.z == -2, "reverse order: the second end is kept")
    } else { check(false, "reverse straddle should clip") }
}

print("checks: \(checks), failures: \(failures)")
exit(failures == 0 ? 0 : 1)
