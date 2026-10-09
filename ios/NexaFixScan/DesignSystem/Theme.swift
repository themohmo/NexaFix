import SwiftUI
import UIKit
import NexaFixCore

// MARK: - Colour tokens

/// The NexaFix colour tokens from DESIGN.md as dynamic (light and dark) colours.
/// This is the only file in the app that contains hex values.
///
/// With Increased Contrast switched on, the tokens that carry text or fine lines are mixed toward `ink`
/// so they stay readable: `muted` goes from about 4.5:1 to about 8:1 against `background`.
enum Palette {
    /// Screen background.
    static let background = token(light: 0xFBF8F3, dark: 0x141311)
    /// Cards and grouped rows.
    static let surface = token(light: 0xFFFFFF, dark: 0x1E1C19)
    /// Primary text and numbers.
    static let ink = token(light: 0x1F1D1A, dark: 0xF4EFE8)
    /// Secondary text and units.
    static let muted = token(light: 0x7A7268, dark: 0xA39A8E, contrastMix: 0.5)
    /// Hairlines.
    static let line = token(light: 0xDDD3C4, dark: 0x3A3631, contrastMix: 0.45)
    /// Primary buttons, selection, plan highlight. The one thing to do next.
    static let accent = token(light: 0x9C7B52, dark: 0xB8956A, contrastMix: 0.25)
    /// Text and glyphs on an `accent` fill: white in light mode, the dark background in dark mode.
    static let accentContrast = token(light: 0xFFFFFF, dark: 0x141311)
    /// Laser-verified values.
    static let verified = token(light: 0x2F7A4B, dark: 0x5BB77E, contrastMix: 0.3)
    /// Scanned-only joinery dimensions; out of square by less than 3 degrees.
    static let caution = token(light: 0xB26A00, dark: 0xE0A04B, contrastMix: 0.3)
    /// Out of square by 3 degrees or more; failures.
    static let critical = token(light: 0xB3261E, dark: 0xF0776E, contrastMix: 0.25)

    private static let inkLight: UInt32 = 0x1F1D1A
    private static let inkDark: UInt32 = 0xF4EFE8

    private static func token(light: UInt32, dark: UInt32, contrastMix: CGFloat = 0) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            var rgb = RGB(hex: isDark ? dark : light)
            if contrastMix > 0, traits.accessibilityContrast == .high {
                rgb = rgb.mixed(with: RGB(hex: isDark ? Palette.inkDark : Palette.inkLight), amount: contrastMix)
            }
            return rgb.uiColor
        })
    }
}

/// An sRGB colour as plain numbers so the mixing is easy to read.
private struct RGB {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    init(hex: UInt32) {
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func mixed(with other: RGB, amount: CGFloat) -> RGB {
        let t = min(max(amount, 0), 1)
        return RGB(red: red + (other.red - red) * t,
                   green: green + (other.green - green) * t,
                   blue: blue + (other.blue - blue) * t)
    }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
}

// MARK: - Spacing, radii, strokes

/// The 4-point spacing scale. Layout uses these and nothing else.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

/// The corner-radius scale. Always drawn with `.continuous` corners; pills and buttons are capsules.
enum Radius {
    /// Chips and fields.
    static let chip: CGFloat = 10
    /// Rows and small cards.
    static let row: CGFloat = 16
    /// Large cards and sheets.
    static let card: CGFloat = 24
}

/// Line widths. `width` is the hairline used for card borders and dividers.
enum Hairline {
    static let width: CGFloat = 0.5
    /// Used instead of `width` when Increased Contrast is on.
    static let emphasized: CGFloat = 1

    /// `width`, or `emphasized` when Increased Contrast is on. Read the contrast with
    /// `@Environment(\.colorSchemeContrast)`.
    static func adaptive(_ contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? emphasized : width
    }
}

// MARK: - Provenance and overlay state

extension OverlayState {
    /// The colour for an overlay state. `scanned` is ink; the AR canvas draws scanned labels
    /// white-on-glass itself and uses this only where a plain colour is needed.
    var color: Color {
        switch self {
        case .scanned: return Palette.ink
        case .verified: return Palette.verified
        case .caution: return Palette.caution
        case .critical: return Palette.critical
        case .neutral: return Palette.muted
        }
    }
}

extension Measured {
    /// `verified` when a person checked the value, `caution` while it is LiDAR only.
    var provenanceColor: Color { isVerified ? Palette.verified : Palette.caution }

    /// "Verified (Laser)", "Verified (Tape)", "Verified (Drawing)" or "Scanned".
    var provenanceLabel: String { ProvenanceDescription.label(for: self) }
}
