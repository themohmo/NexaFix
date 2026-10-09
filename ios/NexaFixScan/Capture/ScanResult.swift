import Foundation
import NexaFixCore

// Plain values the scan flow takes in and hands back. Foundation and NexaFixCore only, so this file
// is type-checked on Linux with the rest of the pure code.

/// What the scan screen needs to know before it starts.
struct ScanConfiguration {
    /// Shown nowhere on the camera screen; carried so the result screen can name what was scanned.
    var propertyName: String
    /// Names of rooms the property already has. New rooms never reuse them.
    var existingRoomNames: [String]
    /// How live measurements are shown while scanning.
    var units: DisplayUnits
    /// The Settings switch. Off means no haptic feedback from the scan screen.
    var hapticsEnabled: Bool
    /// The floor being scanned: 0 = ground, 1 = first floor, -1 = basement.
    var story: Int

    init(propertyName: String,
         existingRoomNames: [String] = [],
         units: DisplayUnits = .default,
         hapticsEnabled: Bool = true,
         story: Int = 0) {
        self.propertyName = propertyName
        self.existingRoomNames = existingRoomNames
        self.units = units
        self.hapticsEnabled = hapticsEnabled
        self.story = story
    }
}

/// Everything a finished scan session produces. The caller saves it: the rooms into the property,
/// the data blobs as the floor's files.
struct ScanResult {
    /// The parametric rooms, named and typed by the person, in scan order.
    var rooms: [Room]
    /// RoomPlan's `CapturedRoom` as JSON, keyed by `Room.id`. A room that has no entry was not scanned
    /// with RoomPlan (a Simulator practice room, or the data could not be encoded).
    var capturedRoomJSON: [UUID: Data]
    /// One USDZ model of the whole floor, when the rooms could be joined and exported.
    var structureUSDZ: Data?
    /// The archived `ARWorldMap` that lets AR review line up with the scan later, when ARKit gave one.
    var worldMapData: Data?
    var story: Int
    /// Plain-language things the person should know, such as "the AR map could not be saved".
    /// Show them on the result screen; an empty list means nothing went wrong.
    var warnings: [String]

    init(rooms: [Room] = [],
         capturedRoomJSON: [UUID: Data] = [:],
         structureUSDZ: Data? = nil,
         worldMapData: Data? = nil,
         story: Int = 0,
         warnings: [String] = []) {
        self.rooms = rooms
        self.capturedRoomJSON = capturedRoomJSON
        self.structureUSDZ = structureUSDZ
        self.worldMapData = worldMapData
        self.story = story
        self.warnings = warnings
    }

    /// True when AR review can work for this scan: there is a saved world map.
    var supportsARReview: Bool { worldMapData != nil }
}
