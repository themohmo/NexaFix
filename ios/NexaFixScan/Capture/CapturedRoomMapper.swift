#if canImport(RoomPlan)
import Foundation
import RoomPlan
import simd
import NexaFixCore

/// Copies a RoomPlan `CapturedRoom` into the platform-neutral `RawCapture` that Core's room builder reads.
/// A field-by-field copy: no geometry is decided here, so everything that matters is tested in Core.
///
/// Surface frame convention. `RawCapture.swift` says a surface's local X runs along its width, local Y is
/// up and local Z is the normal, with the origin at the centre and `dimensions` = (width, height, ~0).
/// Apple's documentation for `CapturedRoom.Surface.transform` and `.dimensions` does NOT state this
/// ("a matrix that defines the surface's position and orientation in the scene", "a bounding box that
/// contains the surface"), so it is not contradicted but also not confirmed by the docs. The one hint in
/// the docs agrees with it: `Surface.Curve.center` is documented as "xz center coordinates", which means a
/// curved wall bends in the local XZ plane, so Y is the vertical axis and Z the normal. Confirm on a device
/// by scanning one wall and checking that `dimensions.x` is its length.
enum CapturedRoomMapper {

    // MARK: Whole room

    /// - Parameters:
    ///   - room: The processed room from RoomPlan's `RoomBuilder.capturedRoom(from:)`.
    ///   - story: Overrides RoomPlan's own `story` (which is 0 unless RoomPlan was told otherwise) with the
    ///     floor the person said they are scanning.
    static func rawCapture(from room: CapturedRoom, story: Int? = nil) -> RawCapture {
        let level = story ?? room.story
        return RawCapture(
            id: room.identifier,
            story: level,
            walls: room.walls.map { surface($0, kind: .wall, story: level) },
            doors: room.doors.map { surface($0, kind: .door, story: level) },
            windows: room.windows.map { surface($0, kind: .window, story: level) },
            openings: room.openings.map { surface($0, kind: .opening, story: level) },
            floors: room.floors.map { surface($0, kind: .floor, story: level) },
            objects: room.objects.map { object($0, story: level) })
    }

    // MARK: Parts

    /// A surface's own `category` decides its kind. `listKind` (the list it came from: `walls`, `doors`, ...)
    /// is only the fallback for a category this code does not know. In RoomPlan's output they agree.
    static func surface(_ s: CapturedRoom.Surface, kind listKind: RawSurfaceKind, story: Int) -> RawSurface {
        let corners = s.polygonCorners
        return RawSurface(
            id: s.identifier,
            kind: Self.kind(of: s.category) ?? listKind,
            transform: matrix(s.transform),
            dimensions: point(s.dimensions),
            // `polygonCorners` is iOS 17+ and not optional; an empty array means RoomPlan gave none.
            polygonCorners: corners.isEmpty ? nil : corners.map(point),
            isCurved: s.curve != nil,
            parentID: s.parentIdentifier,
            story: story,
            confidence: confidence(s.confidence))
    }

    static func object(_ o: CapturedRoom.Object, story: Int) -> RawObject {
        RawObject(
            id: o.identifier,
            category: categoryName(o.category),
            transform: matrix(o.transform),
            dimensions: point(o.dimensions),
            story: story,
            confidence: confidence(o.confidence))
    }

    // MARK: Values

    /// Column-major, columns in order, translation in the last column: the layout `Matrix4` documents.
    static func matrix(_ m: simd_float4x4) -> Matrix4 {
        let c = m.columns
        return Matrix4(columnMajor: [
            Double(c.0.x), Double(c.0.y), Double(c.0.z), Double(c.0.w),
            Double(c.1.x), Double(c.1.y), Double(c.1.z), Double(c.1.w),
            Double(c.2.x), Double(c.2.y), Double(c.2.z), Double(c.2.w),
            Double(c.3.x), Double(c.3.y), Double(c.3.z), Double(c.3.w),
        ])
    }

    static func point(_ v: simd_float3) -> Point3 {
        Point3(Double(v.x), Double(v.y), Double(v.z))
    }

    static func confidence(_ c: CapturedRoom.Confidence) -> RawConfidence {
        switch c {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        @unknown default: return .medium
        }
    }

    /// Kind of a surface from its category. `door(isOpen:)` carries whether the door was open when
    /// scanned; `RawSurface` has no field for that, so it is dropped.
    static func kind(of category: CapturedRoom.Surface.Category) -> RawSurfaceKind? {
        switch category {
        case .wall: return .wall
        case .door: return .door
        case .window: return .window
        case .opening: return .opening
        case .floor: return .floor
        @unknown default: return nil
        }
    }

    /// Apple's case names, exactly: they are what `ObjectKind(rawValue:)` in Core matches on.
    static func categoryName(_ c: CapturedRoom.Object.Category) -> String {
        switch c {
        case .storage: return "storage"
        case .refrigerator: return "refrigerator"
        case .stove: return "stove"
        case .bed: return "bed"
        case .sink: return "sink"
        case .washerDryer: return "washerDryer"
        case .toilet: return "toilet"
        case .bathtub: return "bathtub"
        case .oven: return "oven"
        case .dishwasher: return "dishwasher"
        case .table: return "table"
        case .sofa: return "sofa"
        case .chair: return "chair"
        case .fireplace: return "fireplace"
        case .television: return "television"
        case .stairs: return "stairs"
        @unknown default: return "other"
        }
    }
}
#endif
