import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

// What AR is doing, and whether it is honest to draw the overlay yet.
//
// Room coordinates come from the scan session. They only line up with the real room after ARKit
// RELOCALISES against the world map saved with the scan. Until then, numbers drawn over the camera
// would sit in the wrong place, so the overlay stays hidden. Everything that decides this is plain Swift
// on Foundation (the first half of this file), so it is type-checked and exercised on Linux. The delegate
// in `ARReviewController` only copies ARKit's values into a `TrackingSnapshot`; the pill at the bottom of
// the file is the only SwiftUI.

// MARK: - Snapshot

/// ARKit's tracking facts for one moment, as plain values.
struct TrackingSnapshot: Equatable, Sendable {
    /// `ARCamera.TrackingState` flattened: not available, limited for one of four reasons, or normal.
    enum Tracking: Equatable, Sendable {
        case notAvailable, initializing, relocalizing, excessiveMotion, insufficientFeatures, normal
    }

    /// `ARFrame.WorldMappingStatus`.
    enum Mapping: Equatable, Sendable {
        case notAvailable, limited, extending, mapped
    }

    /// Whether the session was started from a saved world map.
    enum WorldMap: Equatable, Sendable {
        /// The room was saved without a map.
        case none
        /// There was a map file but it could not be read.
        case unreadable
        /// The session started from this room's map.
        case loaded
    }

    var tracking: Tracking
    var mapping: Mapping
    var worldMap: WorldMap
    /// The system interrupted the session (another app took the camera).
    var isInterrupted: Bool
    /// A monotonic clock in seconds (`ARFrame.timestamp`).
    var time: Double

    init(tracking: Tracking, mapping: Mapping = .notAvailable, worldMap: WorldMap = .loaded,
         isInterrupted: Bool = false, time: Double = 0) {
        self.tracking = tracking
        self.mapping = mapping
        self.worldMap = worldMap
        self.isInterrupted = isInterrupted
        self.time = time
    }

    /// Everything except the clock, so unchanged frames can be skipped.
    func sameState(as other: TrackingSnapshot) -> Bool {
        tracking == other.tracking && mapping == other.mapping && worldMap == other.worldMap
            && isInterrupted == other.isInterrupted
    }
}

// MARK: - Phase

/// Where we are in lining the saved room up with the real one.
enum RelocalisationPhase: Equatable, Sendable {
    /// Waiting for ARKit to relocalise against the saved map.
    case searching
    /// Relocalised: the scan's coordinates match the real room.
    case aligned
    /// The overlay cannot be drawn honestly right now.
    case failed(Failure)

    enum Failure: Equatable, Sendable {
        /// The room has no saved AR map, so the overlay can never line up.
        case noWorldMap
        /// The map file exists but could not be read.
        case mapUnreadable
        /// ARKit did not relocalise in time.
        case timedOut
    }
}

/// Feeds snapshots in, keeps the phase. Pure: it never looks at a clock of its own.
///
/// The rule from ARKit's documentation (`ARWorldTrackingConfiguration.initialWorldMap`): a session started
/// from a saved map begins in `limited(relocalizing)`, and the tracking state becomes `normal` once "the
/// current world coordinate system and anchors match those from the recorded world map". So `normal` after
/// we saw `relocalizing` is the one signal that the frames of reference agree. Nothing else counts: the
/// world-mapping status describes how well the current session has mapped its own surroundings, not
/// whether it matched the saved map. If `normal` ever arrives without `relocalizing`, the search runs out
/// of time and says so honestly rather than drawing numbers that might be in the wrong place.
///
/// Time spent with no frames at all (another app had the camera) is not time spent searching: the search
/// clock restarts on the first fresh frame after such a gap.
///
/// "Keep trying" restarts the AR session, so the caller simply starts again with a new tracker: nothing
/// seen in the old session counts for the new one.
struct RelocalisationTracker: Equatable, Sendable {
    /// How long to search before saying so, seconds.
    static let defaultTimeout = 25.0
    /// Snapshots further apart than this mean ARKit delivered no frames in between, seconds.
    static let maxFrameGap = 2.0

    let timeout: Double
    private(set) var phase: RelocalisationPhase = .searching
    private var searchStart: Double?
    private var sawRelocalising = false
    private var lastTime: Double?
    private var wasInterrupted = false

    init(timeout: Double = RelocalisationTracker.defaultTimeout) {
        self.timeout = timeout
    }

    /// Update with the latest snapshot and return the new phase.
    @discardableResult
    mutating func ingest(_ s: TrackingSnapshot) -> RelocalisationPhase {
        defer {
            lastTime = s.time
            wasInterrupted = s.isInterrupted
        }

        switch s.worldMap {
        case .none:
            phase = .failed(.noWorldMap)
            return phase
        case .unreadable:
            phase = .failed(.mapUnreadable)
            return phase
        case .loaded:
            break
        }

        if s.tracking == .relocalizing { sawRelocalising = true }
        let confirmed = s.tracking == .normal && !s.isInterrupted && sawRelocalising

        switch phase {
        case .aligned:
            // A short dip in quality (fast movement, a blank wall) keeps the alignment but hides the overlay
            // through `ARStatusSummary.overlayAllowed`. Losing the frame of reference means searching again.
            let lostFrame = s.isInterrupted || s.tracking == .relocalizing
                || s.tracking == .notAvailable || s.tracking == .initializing
            if lostFrame {
                phase = .searching
                searchStart = s.time
                sawRelocalising = s.tracking == .relocalizing
            }
        case .searching:
            if searchClockWasPaused(at: s) { searchStart = s.time }
            let start = searchStart ?? s.time
            searchStart = start
            if confirmed {
                phase = .aligned
                searchStart = nil
            } else if s.time - start >= timeout {
                phase = .failed(.timedOut)
            }
        case .failed(let reason):
            if confirmed {
                // ARKit relocalised after all, for example once the person walked back to the start.
                phase = .aligned
                searchStart = nil
            } else if reason != .timedOut {
                // The map is available now; start looking.
                phase = .searching
                searchStart = s.time
            }
        }
        return phase
    }

    /// True while the camera is taken, on the first frame after it comes back, and after any gap with no
    /// frames: none of that time counts towards the timeout.
    private func searchClockWasPaused(at s: TrackingSnapshot) -> Bool {
        if s.isInterrupted || wasInterrupted { return true }
        if let last = lastTime, s.time - last > RelocalisationTracker.maxFrameGap { return true }
        return false
    }
}

// MARK: - What to show

/// The words, symbol and permission for one moment. Derived from the phase and the snapshot only.
struct ARStatusSummary: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        /// Working on it.
        case working
        /// Lined up with the scan. Deliberately not green with a check mark: that pairing means
        /// "laser-verified" everywhere else in the app, and a line-up says nothing about any number.
        case good
        /// Needs the person to do something.
        case caution
    }

    /// Short text for the pill.
    var title: String
    /// One line of guidance under the title; nil when there is nothing to do.
    var detail: String?
    /// SF Symbol name.
    var symbol: String
    var tone: Tone
    /// True only when it is honest to draw the overlay: lined up and tracking is normal right now.
    var overlayAllowed: Bool
    /// A plain-language explanation shown in a card when the overlay cannot be drawn; nil otherwise.
    var message: String?
    /// Whether the card offers "Keep trying".
    var offersKeepTrying: Bool
    /// Where the line-up stands.
    var phase: RelocalisationPhase

    /// One sentence for VoiceOver.
    var spoken: String {
        if let message { return title + ". " + message }
        if let detail { return title + ". " + detail }
        return title
    }

    static let unalignedMessage =
        "Overlay can't line up with the room yet. Go back to where you started scanning and look at the walls you scanned."
    static let noMapMessage =
        "Overlay can't line up with the room yet. This room was saved without an AR map, so scan it again to use the overlay. You can still measure."
    static let unreadableMapMessage =
        "Overlay can't line up with the room yet. The saved AR map couldn't be read, so scan the room again to use the overlay. You can still measure."

    /// The line on the tape-measure card about what happens to the number. A tape reading is LiDAR only, so
    /// every variant starts with "Scanned". Rooms that can never line up say so, instead of promising
    /// something that cannot happen.
    var tapeSaveNote: String {
        switch phase {
        case .aligned:
            return "Scanned. Check with a laser before cutting."
        case .failed(.noWorldMap):
            return "Scanned. This room has no saved AR map, so measurements can't be saved. Scan the room again to save them."
        case .failed(.mapUnreadable):
            return "Scanned. The saved AR map couldn't be read, so measurements can't be saved. Scan the room again to save them."
        case .searching, .failed(.timedOut):
            return "Scanned. Can't be saved until the overlay lines up with the room."
        }
    }

    static func make(phase: RelocalisationPhase, snapshot s: TrackingSnapshot) -> ARStatusSummary {
        func summary(_ title: String, _ detail: String? = nil, symbol: String, tone: Tone,
                     overlayAllowed: Bool = false, message: String? = nil,
                     offersKeepTrying: Bool = false) -> ARStatusSummary {
            ARStatusSummary(title: title, detail: detail, symbol: symbol, tone: tone,
                            overlayAllowed: overlayAllowed, message: message,
                            offersKeepTrying: offersKeepTrying, phase: phase)
        }

        switch phase {
        case .failed(.timedOut):
            return summary("Not lined up", symbol: "exclamationmark.triangle.fill", tone: .caution,
                           message: unalignedMessage, offersKeepTrying: true)
        case .failed(.noWorldMap):
            return summary("No saved AR map", symbol: "exclamationmark.triangle.fill", tone: .caution,
                           message: noMapMessage)
        case .failed(.mapUnreadable):
            return summary("AR map unreadable", symbol: "exclamationmark.triangle.fill", tone: .caution,
                           message: unreadableMapMessage)
        case .searching, .aligned:
            break
        }

        if s.isInterrupted {
            return summary("AR paused", "Another app is using the camera.", symbol: "pause.circle.fill",
                           tone: .caution)
        }

        let aligned = phase == .aligned
        switch s.tracking {
        case .normal:
            if aligned {
                return summary("Lined up with your scan", symbol: "viewfinder.circle.fill", tone: .good,
                               overlayAllowed: true)
            }
            return summary("Checking the match", "Keep looking at the walls you scanned.",
                           symbol: "viewfinder", tone: .working)
        case .relocalizing:
            return summary("Relocalising", "Look at the room you scanned.", symbol: "viewfinder", tone: .working)
        case .excessiveMotion:
            return summary("Slow down", "Move your phone more slowly.", symbol: "tortoise.fill", tone: .caution)
        case .insufficientFeatures:
            return summary("Need more detail", "Point at walls, corners or furniture.",
                           symbol: "viewfinder", tone: .caution)
        case .initializing, .notAvailable:
            return summary("Starting AR", "Move your phone slowly.", symbol: "viewfinder", tone: .working)
        }
    }
}

// MARK: - Pill

#if canImport(SwiftUI)

/// The glass status pill at the top of the AR screen: a symbol, what AR is doing, and one line of guidance.
struct ARTrackingStatusPill: View {
    let summary: ARStatusSummary

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: summary.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: summary.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if let detail = summary.detail {
                    // Text over glass is ink at full strength and semibold, never a flat grey.
                    Text(verbatim: detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .glass(cornerRadius: Radius.row, prominence: .thin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.spoken)
    }

    private var tint: Color {
        switch summary.tone {
        case .working: return Palette.muted
        case .good: return Palette.ink
        case .caution: return Palette.caution
        }
    }
}

#endif
