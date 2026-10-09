import Foundation

/// An error written for the person holding the phone: what happened, and what to do about it.
///
/// Build one from any `Error` plus a short phrase for what the app was doing:
///
///     UserFacingError(error, context: "save “Marina apartment”")
///
/// gives the title "Couldn't save “Marina apartment”". `context` is a lower-case verb phrase.
/// Foundation only, so the wording rules are unit-checked on Linux.
struct UserFacingError: LocalizedError, Identifiable {
    /// How loudly the interface should treat the error.
    enum Severity: Equatable {
        /// Something did not work; nothing the person made is at risk.
        case notice
        /// Work the person has done exists only in memory. Use a blocking alert and a persistent banner.
        case dataAtRisk
    }

    let id = UUID()
    /// Short headline for an alert title, for example "Couldn't save “Marina apartment”".
    let title: String
    /// One or two plain sentences saying what happened.
    let message: String
    /// What to do next, when there is something to do.
    let recovery: String?
    let severity: Severity
    /// The underlying error in developer terms. Show it only behind a "Details" disclosure.
    let technicalDetail: String

    init(title: String, message: String, recovery: String? = nil,
         severity: Severity = .notice, technicalDetail: String = "") {
        self.title = title
        self.message = message
        self.recovery = recovery
        self.severity = severity
        self.technicalDetail = technicalDetail
    }

    init(_ error: Error, context: String, severity: Severity = .notice) {
        let reason = UserFacingError.describe(error)
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Something went wrong" : "Couldn't " + trimmed

        var message = reason.message
        var recovery = reason.recovery
        if severity == .dataAtRisk {
            message += " Your work is still open in the app, but it is not saved."
            let advice = "Don't close the app until it has saved."
            recovery = recovery.map { $0 + " " + advice } ?? "Try again. " + advice
        }

        self.init(title: title, message: message, recovery: recovery, severity: severity,
                  technicalDetail: String(describing: error))
    }

    // MARK: LocalizedError

    var errorDescription: String? { title }
    var failureReason: String? { message }
    var recoverySuggestion: String? { recovery }

    // MARK: Wording

    /// Same wording on iPhone and iPad, so it names no device.
    private static let outOfSpace: (message: String, recovery: String?) =
        ("There isn't enough free storage on this device.",
         "Free up space in Settings > General > Storage, then try again.")

    /// Plain-language reason and next step for the errors this app can realistically hit.
    static func describe(_ error: Error) -> (message: String, recovery: String?) {
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileWriteOutOfSpace:
                return outOfSpace
            case .fileWriteNoPermission, .fileWriteVolumeReadOnly:
                return ("The app isn't allowed to write to its storage.",
                        "Restart the app and try again.")
            case .fileReadNoSuchFile, .fileNoSuchFile:
                return ("A file the app needs is missing.", nil)
            case .fileReadCorruptFile, .coderReadCorrupt, .propertyListReadCorrupt:
                return ("A saved file is damaged and can't be read.", nil)
            case .fileReadNoPermission:
                return ("The app isn't allowed to read its storage.", "Restart the app and try again.")
            default:
                break
            }
        }
        if error is DecodingError {
            return ("A saved file is damaged, or was made by a newer version of the app.", nil)
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) {
            return outOfSpace
        }
        if let localized = error as? LocalizedError,
           let text = localized.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return (sentence(text), localized.recoverySuggestion)
        }
        return ("Something unexpected happened.", "Try again. If it keeps happening, restart the app.")
    }

    /// Makes sure a message ends in a full stop so concatenated sentences read properly.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last else { return text }
        return ".!?".contains(last) ? text : text + "."
    }
}
