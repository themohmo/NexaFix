import Foundation
import NexaFixCore

/// The user's preferences, stored as one JSON blob in `UserDefaults` under a versioned key.
///
/// Decoding is deliberately forgiving: a missing field, a value from a newer version of the app
/// (for example a unit this build does not know) or a value that makes no sense falls back to its
/// default instead of throwing away every other setting. Foundation and NexaFixCore only, so it is
/// unit-checked on Linux.
struct AppSettings: Codable, Equatable {
    /// How lengths and areas are shown. Storage and exports are always metric.
    var units: DisplayUnits
    /// Whether the app plays haptic feedback.
    var hapticsEnabled: Bool
    /// Drawing scale denominator for exported plans (50 means 1:50). `nil` picks a scale automatically.
    var planScale: Double?
    /// Paper size for exported plans: `"auto"`, `"a4"` or `"a3"`.
    var paper: String

    /// Paper choices the export code understands.
    static let paperChoices = ["auto", "a4", "a3"]
    static let automaticPaper = "auto"

    /// Bump the suffix when the stored shape changes in a way tolerant decoding cannot absorb.
    static let storageKey = "com.nexafix.scan.settings.v1"

    init(units: DisplayUnits = .default,
         hapticsEnabled: Bool = true,
         planScale: Double? = nil,
         paper: String = AppSettings.automaticPaper) {
        self.units = units
        self.hapticsEnabled = hapticsEnabled
        self.planScale = AppSettings.sanitisedScale(planScale)
        self.paper = AppSettings.sanitisedPaper(paper)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case units, hapticsEnabled, planScale, paper
    }

    private enum UnitKeys: String, CodingKey {
        case length, area
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        var units = DisplayUnits.default
        if let u = try? c.nestedContainer(keyedBy: UnitKeys.self, forKey: .units) {
            if let length = try? u.decode(LengthUnit.self, forKey: .length) { units.length = length }
            if let area = try? u.decode(AreaUnit.self, forKey: .area) { units.area = area }
        }

        let haptics = try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)
        let scale = try? c.decodeIfPresent(Double.self, forKey: .planScale)
        let paper = try? c.decodeIfPresent(String.self, forKey: .paper)

        self.init(units: units,
                  hapticsEnabled: haptics ?? true,
                  planScale: scale,
                  paper: paper ?? AppSettings.automaticPaper)
    }

    // MARK: Persistence

    /// Reads the saved settings, or the defaults when nothing usable is stored.
    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    /// Writes the settings. Encoding a handful of strings and numbers cannot realistically fail;
    /// if it ever does, the previous value stays in place.
    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppSettings.storageKey)
    }

    // MARK: Sanitising

    static func sanitisedPaper(_ value: String) -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return paperChoices.contains(key) ? key : automaticPaper
    }

    static func sanitisedScale(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
