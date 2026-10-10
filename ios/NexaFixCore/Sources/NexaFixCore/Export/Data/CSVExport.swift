import Foundation

// Spreadsheet export: one CSV per table (rooms, walls, openings, objects), written for Excel and
// for scripts.
//
//  - RFC 4180: fields containing a comma, a double quote, CR or LF are quoted and inner quotes are
//    doubled; lines end with CRLF ("\r\n"), including the last one.
//  - UTF-8 with a leading byte order mark (U+FEFF). Excel for Windows opens a BOM-less CSV in the
//    legacy ANSI code page and mangles Arabic, accents and the degree sign; the BOM is how it
//    recognises UTF-8. Other readers (Python `utf-8-sig`, Numbers, Google Sheets) skip it.
//  - Numbers are plain ASCII: "." decimal point, no thousands separators, fixed decimals per
//    unit, built with the C formatter and never a locale-aware one.
//  - Column names carry the unit (`length_mm`, `floor_area_m2`). Every measured dimension is three
//    columns in a row: the value to use (`length_mm`), what LiDAR read (`length_scanned_mm`) and
//    whether a person checked it on site (`length_verified`, yes / no) plus who (`length_source`).
//  - Figures derived from several walls (perimeters, a rectangle's length and width, the effective
//    floor area) follow the same pattern: the value, the LiDAR-only figure and a `_verified` flag
//    that is `yes` only when every wall behind the figure was checked. A blend of verified and
//    scanned walls is `no`: it is neither measurement. Floor area and volume of an irregular room
//    come from scanned corner coordinates and are never `yes`.
//  - Text that a spreadsheet would run as a formula (starts with = + - @, tab or CR) gets a leading
//    apostrophe, the standard defence against CSV injection. Numbers are never touched.
//  - Row order is the model order: floors, rooms, walls in loop order, openings by wall then
//    position. The same property always gives byte-identical files.

public enum CSVExport {

    /// Leading byte order mark so Excel opens the file as UTF-8.
    public static let byteOrderMark = "\u{FEFF}"
    /// RFC 4180 line ending.
    public static let lineEnding = "\r\n"

    public static let roomsFileName = "rooms.csv"
    public static let wallsFileName = "walls.csv"
    public static let openingsFileName = "openings.csv"
    public static let objectsFileName = "objects.csv"
    /// Only produced when at least one room has a custom measurement.
    public static let customMeasurementsFileName = "custom_measurements.csv"

    /// The CSV files for a property: `rooms.csv`, `walls.csv`, `openings.csv`, `objects.csv`
    /// (always, even when empty, so scripts can rely on them) and `custom_measurements.csv`
    /// when the property has any. `content` starts with the byte order mark; write it as UTF-8.
    public static func files(for property: Property, units: DisplayUnits) -> [(name: String, content: String)] {
        let q = Quantities(units: units)
        var files: [(name: String, content: String)] = [
            (roomsFileName, rooms(property, q)),
            (wallsFileName, walls(property, q)),
            (openingsFileName, openings(property, q)),
            (objectsFileName, objects(property, q)),
        ]
        let hasCustoms = property.allRooms.contains { !$0.customMeasurements.isEmpty }
        if hasCustoms { files.append((customMeasurementsFileName, customMeasurements(property, q))) }
        return files
    }

    // MARK: RFC 4180

    /// One field, quoted when it has to be. Does not guard against formulas: pass free text through
    /// `safeText(_:)` first (the table builders do).
    public static func field(_ value: String) -> String {
        let needsQuotes = value.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Free text made safe to open in a spreadsheet: a leading apostrophe when it starts with
    /// `=`, `+`, `-`, `@`, tab or CR, which Excel and Sheets would otherwise run as a formula.
    /// Quoting is done separately, by `field(_:)` / `row(_:)`.
    public static func safeText(_ value: String) -> String {
        if let first = value.unicodeScalars.first,
           first == "=" || first == "+" || first == "-" || first == "@" || first == "\t" || first == "\r" {
            return "'" + value
        }
        return value
    }

    /// A header or data row: every field quoted as needed, joined by commas, ending with CRLF.
    public static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + lineEnding
    }

    // MARK: Units

    /// Converts and formats quantities for the chosen display units.
    struct Quantities {
        let units: DisplayUnits

        /// `mm`, `cm`, `m`, `in` or `ft` (feet-and-inches is exported as decimal feet).
        var l: String { units.length.symbol }
        /// `m2` or `sqft`.
        var a: String { units.area == .squareMetres ? "m2" : "sqft" }
        /// `m3` or `ft3`.
        var v: String { units.area == .squareMetres ? "m3" : "ft3" }

        func length(_ metres: Double) -> String {
            switch units.length {
            case .millimetres: return DataNumber.fixed(metres * 1000, decimals: 1)
            case .centimetres: return DataNumber.fixed(metres * 100, decimals: 2)
            case .metres: return DataNumber.fixed(metres, decimals: 4)
            case .inches: return DataNumber.fixed(metres / UnitFormatter.metresPerInch, decimals: 3)
            case .feetAndInches: return DataNumber.fixed(metres / UnitFormatter.metresPerFoot, decimals: 4)
            }
        }

        func optionalLength(_ metres: Double?) -> String { metres.map(length) ?? "" }

        func area(_ squareMetres: Double) -> String {
            switch units.area {
            case .squareMetres: return DataNumber.fixed(squareMetres, decimals: 3)
            case .squareFeet: return DataNumber.fixed(squareMetres / UnitFormatter.squareMetresPerSquareFoot, decimals: 2)
            }
        }

        func volume(_ cubicMetres: Double) -> String {
            switch units.area {
            case .squareMetres: return DataNumber.fixed(cubicMetres, decimals: 3)
            case .squareFeet:
                let f = UnitFormatter.metresPerFoot
                return DataNumber.fixed(cubicMetres / (f * f * f), decimals: 2)
            }
        }

        /// Column names for a measured dimension: value, scanned, verified, source.
        func measuredHeaders(_ name: String) -> [String] {
            ["\(name)_\(l)", "\(name)_scanned_\(l)", "\(name)_verified", "\(name)_source"]
        }

        /// Cells for a measured dimension, in the order of `measuredHeaders`.
        func measuredCells(_ m: Measured) -> [String] {
            [length(m.value), length(m.scanned), m.isVerified ? "yes" : "no",
             m.verification?.source.rawValue ?? ""]
        }
    }

    // MARK: Tables
    //
    // Rows are built with explicit `[String]` arrays and `append` / `+=` of one array at a time.
    // Long `+` chains of mixed array literals make the Swift type checker take tens of seconds.

    /// `yes` / `no` for a flag; empty when the figure does not exist (a room that is not a rectangle).
    private static func yesNo(_ flag: Bool?) -> String {
        guard let flag else { return "" }
        return flag ? "yes" : "no"
    }

    private static func rooms(_ property: Property, _ q: Quantities) -> String {
        var header: [String] = ["floor", "level", "room_id", "room", "kind", "scanned_at"]
        header += ["floor_area_\(q.a)", "effective_floor_area_\(q.a)", "effective_floor_area_scanned_\(q.a)", "effective_floor_area_verified"]
        header += ["perimeter_\(q.l)", "perimeter_scanned_\(q.l)", "perimeter_verified"]
        header += ["wall_perimeter_\(q.l)", "wall_perimeter_scanned_\(q.l)", "wall_perimeter_verified"]
        header += q.measuredHeaders("ceiling_height")
        header += ["is_rectangular"]
        header += ["length_\(q.l)", "length_scanned_\(q.l)", "length_verified"]
        header += ["width_\(q.l)", "width_scanned_\(q.l)", "width_verified"]
        header += ["volume_\(q.v)"]
        header += ["gross_wall_area_\(q.a)", "opening_area_\(q.a)", "net_wall_area_\(q.a)"]
        header += ["verified_count", "measurement_count", "joinery_verified_count", "joinery_measurement_count"]
        header += ["walls", "openings", "objects", "notes"]

        var out: String = byteOrderMark + row(header)
        for floor in property.floors {
            for room in floor.rooms {
                let m = room.metrics
                let d = DataDerived(room: room, metrics: m)
                let c = DataMeasureList.counts(for: room)
                var cells: [String] = [safeText(floor.name), String(floor.level), room.id.uuidString, safeText(room.name)]
                cells += [room.kind.rawValue, DataDates.iso8601Millis(room.scannedAt)]
                cells.append(q.area(m.floorArea))
                cells += [q.area(m.effectiveFloorArea), q.area(d.effectiveAreaScanned), yesNo(d.effectiveAreaVerified)]
                cells += [q.length(m.perimeter), q.length(d.perimeterScanned), yesNo(d.perimeterVerified)]
                cells += [q.length(m.wallPerimeter), q.length(d.wallPerimeterScanned), yesNo(d.wallPerimeterVerified)]
                cells += q.measuredCells(room.ceilingHeight)
                cells.append(m.isRectangular ? "yes" : "no")
                cells += [m.isRectangular ? q.optionalLength(m.length) : "", q.optionalLength(d.lengthScanned), yesNo(d.lengthVerified)]
                cells += [m.isRectangular ? q.optionalLength(m.width) : "", q.optionalLength(d.widthScanned), yesNo(d.widthVerified)]
                cells += [q.volume(m.volume), q.area(m.grossWallArea), q.area(m.openingArea), q.area(m.netWallArea)]
                cells += [String(c.verified), String(c.total), String(c.joineryVerified), String(c.joineryTotal)]
                cells += [String(room.walls.count), String(room.openings.count), String(room.objects.count)]
                cells.append(safeText(room.notes))
                out += row(cells)
            }
        }
        return out
    }

    private static func walls(_ property: Property, _ q: Quantities) -> String {
        var header: [String] = ["floor", "room_id", "room", "wall_id", "wall_index", "wall", "kind", "curved"]
        header += ["start_x_\(q.l)", "start_y_\(q.l)", "end_x_\(q.l)", "end_y_\(q.l)"]
        header += q.measuredHeaders("length")
        header += q.measuredHeaders("height")

        var out: String = byteOrderMark + row(header)
        for floor in property.floors {
            for room in floor.rooms {
                for (i, wall) in room.walls.enumerated() {
                    var cells: [String] = [safeText(floor.name), room.id.uuidString, safeText(room.name), wall.id.uuidString]
                    cells += [String(i), DataLabels.wall(i), wall.kind.rawValue, wall.isCurved ? "yes" : "no"]
                    cells += [q.length(wall.start.x), q.length(wall.start.y), q.length(wall.end.x), q.length(wall.end.y)]
                    cells += q.measuredCells(wall.length)
                    cells += q.measuredCells(wall.height)
                    out += row(cells)
                }
            }
        }
        return out
    }

    private static func openings(_ property: Property, _ q: Quantities) -> String {
        var header: [String] = ["floor", "room_id", "room", "opening_id", "opening", "kind", "wall_id", "wall"]
        header += ["offset_from_start_\(q.l)", "offset_from_end_\(q.l)"]
        header += q.measuredHeaders("width")
        header += q.measuredHeaders("height")
        header += q.measuredHeaders("sill_height")
        header.append("area_\(q.a)")

        var out: String = byteOrderMark + row(header)
        for floor in property.floors {
            for room in floor.rooms {
                for ref in DataOpenings.ordered(in: room) {
                    let o = ref.opening
                    let wall: Wall? = ref.wallIndex.map { room.walls[$0] }
                    let fromEnd: Double? = wall.map { $0.geometricLength - o.offsetFromWallStart - o.width.scanned }
                    let wallLabel: String = ref.wallIndex.map { DataLabels.wall($0) } ?? ""
                    var cells: [String] = [safeText(floor.name), room.id.uuidString, safeText(room.name), o.id.uuidString]
                    // A wall id that is not a wall of this room is a dangling reference: left empty, like no wall.
                    cells += [ref.label, o.kind.rawValue, wall?.id.uuidString ?? "", wallLabel]
                    cells += [q.length(o.offsetFromWallStart), q.optionalLength(fromEnd)]
                    cells += q.measuredCells(o.width)
                    cells += q.measuredCells(o.height)
                    cells += q.measuredCells(o.sillHeight)
                    cells.append(q.area(o.width.value * o.height.value))
                    out += row(cells)
                }
            }
        }
        return out
    }

    private static func objects(_ property: Property, _ q: Quantities) -> String {
        // RoomPlan estimates; the model has no way to verify them, so `verified` is always "no".
        var header: [String] = ["floor", "room_id", "room", "object_id", "kind"]
        header += ["center_x_\(q.l)", "center_y_\(q.l)", "yaw_deg"]
        header += ["width_\(q.l)", "depth_\(q.l)", "height_\(q.l)", "elevation_\(q.l)", "verified"]

        var out: String = byteOrderMark + row(header)
        for floor in property.floors {
            for room in floor.rooms {
                for obj in room.objects {
                    var cells: [String] = [safeText(floor.name), room.id.uuidString, safeText(room.name), obj.id.uuidString]
                    cells.append(obj.kind.rawValue)
                    cells += [q.length(obj.center.x), q.length(obj.center.y)]
                    cells.append(DataNumber.fixed(ScanExport.yawDegrees(obj.yaw), decimals: 3))
                    cells += [q.length(obj.width), q.length(obj.depth), q.length(obj.height), q.length(obj.elevation)]
                    cells.append("no")
                    out += row(cells)
                }
            }
        }
        return out
    }

    private static func customMeasurements(_ property: Property, _ q: Quantities) -> String {
        var header: [String] = ["floor", "room_id", "room", "measurement_id", "label"]
        header += q.measuredHeaders("length")
        header += ["created_at", "note"]

        var out: String = byteOrderMark + row(header)
        for floor in property.floors {
            for room in floor.rooms {
                for c in room.customMeasurements {
                    var cells: [String] = [safeText(floor.name), room.id.uuidString, safeText(room.name)]
                    cells += [c.id.uuidString, safeText(c.label)]
                    cells += q.measuredCells(c.length)
                    cells += [DataDates.iso8601Millis(c.createdAt), safeText(c.note ?? "")]
                    out += row(cells)
                }
            }
        }
        return out
    }
}
