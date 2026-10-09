import Foundation

/// One dimension of a room that can be checked on site with a laser measure.
///
/// A target names a `Measured` value inside a `Room` (see `Room.measured(_:)` and
/// `Room.setVerification(_:for:)`). The UUID is the id of the wall, opening or custom
/// measurement, so a target stays valid when the room is edited or re-ordered.
public enum MeasureTarget: Hashable, Codable, Sendable {
    /// Clear length of a wall (its `Wall.length`).
    case wallLength(UUID)
    /// Floor-to-ceiling height of one wall (its `Wall.height`).
    case wallHeight(UUID)
    case openingWidth(UUID)
    case openingHeight(UUID)
    /// Height of the bottom edge of an opening above the floor.
    case openingSill(UUID)
    /// The room's `ceilingHeight`.
    case ceilingHeight
    /// A `CustomMeasurement` taken in the AR view or 3D viewer.
    case customLength(UUID)

    /// The id of the wall, opening or custom measurement this target points at; nil for the ceiling.
    public var entityID: UUID? {
        switch self {
        case .wallLength(let id), .wallHeight(let id), .openingWidth(let id),
             .openingHeight(let id), .openingSill(let id), .customLength(let id):
            return id
        case .ceilingHeight:
            return nil
        }
    }

    /// Only a sill height can legitimately be zero (a door on the floor).
    var allowsZeroValue: Bool {
        if case .openingSill = self { return true }
        return false
    }
}
