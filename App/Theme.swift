import AppKit
import BrowserKit
import SwiftUI

/// Koala's design tokens. One 11-step neutral ramp is the only tonal scale; every surface,
/// hairline, and text color is a step on it. Chroma is reserved for the accent and state.
enum Theme {
    // MARK: Neutral ramp (step 0 is the lightest surface in light mode, the deepest in dark)

    private static let lightRamp: [UInt32] = [
        0xFFFFFF, 0xFAFAFA, 0xF4F4F5, 0xEBEBED, 0xDEDEE1, 0xC8C8CD,
        0xA0A0A8, 0x6C6C75, 0x4E4E56, 0x2E2E33, 0x18181B,
    ]
    private static let darkRamp: [UInt32] = [
        0x111113, 0x18181B, 0x1E1E21, 0x26262A, 0x303035, 0x3E3E44,
        0x5A5A62, 0x8A8A93, 0xA6A6AE, 0xD4D4D8, 0xF4F4F5,
    ]

    static func neutral(_ step: Int) -> NSColor {
        dynamic(light: lightRamp[step], dark: darkRamp[step], name: "neutral\(step)")
    }

    // MARK: Surfaces

    /// Ground behind the tab strip.
    static let stripGround = dynamic(light: lightRamp[3], dark: darkRamp[0], name: "stripGround")
    /// Toolbar and the selected tab, which share one surface.
    static let chromeSurface = dynamic(light: lightRamp[1], dark: darkRamp[2], name: "chromeSurface")
    /// Hover fill for tabs and toolbar buttons.
    static let hoverFill = dynamic(light: lightRamp[4], dark: darkRamp[3], name: "hoverFill")
    /// Pressed fill.
    static let pressedFill = dynamic(light: lightRamp[5], dark: darkRamp[4], name: "pressedFill")
    /// Address field well.
    static let fieldFill = dynamic(light: lightRamp[3], dark: darkRamp[1], name: "fieldFill")
    /// One-pixel separators.
    static let hairline = dynamic(light: lightRamp[4], dark: darkRamp[4], name: "hairline")

    // MARK: Text

    static let textPrimary = neutral(10)
    static let textSecondary = neutral(8)
    static let textTertiary = neutral(7)

    // MARK: Accent and state

    /// Koala teal: focus, selection, and primary actions only.
    static let accent = dynamic(light: 0x0E8F80, dark: 0x2CC3AE, name: "accent")
    static let accentText = dynamic(light: 0x0B7A6D, dark: 0x2CC3AE, name: "accentText")
    /// Text on a filled primary button, whose fill is `accentText` (deep teal light, teal dark).
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0B1F1C, name: "onAccent")
    /// Native selected segments use white labels in both appearances.
    static let controlSelectionTint = dynamic(light: 0x4E4E56, dark: 0x3E3E44, name: "controlSelectionTint")
    /// A switch's on track: ramp step 8 light, step 7 dark, so on stays above 3:1 against chrome surface.
    static let switchTint = dynamic(light: lightRamp[8], dark: darkRamp[7], name: "switchTint")
    static let pass = dynamic(light: 0x248A57, dark: 0x3DD68C, name: "pass")
    static let pending = dynamic(light: 0xB07A0A, dark: 0xF5A524, name: "pending")
    static let fail = dynamic(light: 0xD1343A, dark: 0xF2555A, name: "fail")
    static let merged = dynamic(light: 0x8E4EC6, dark: 0xB57FE8, name: "merged")

    // MARK: Type

    static let tabTitle = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let tabTitleSelected = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let field = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let fieldMono = mono(ofSize: 12)

    /// 0xProto, the monospace face. It ships Regular and Bold only: semibold and heavier set Bold.
    static func mono(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: weight.rawValue >= NSFont.Weight.semibold.rawValue ? MonoFont.bold : MonoFont.regular, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: Geometry (4pt grid)

    static let stripHeight: CGFloat = 40      // matches the native compact titlebar
    static let toolbarHeight: CGFloat = 36
    static let tabHeight: CGFloat = 28
    static let tabMaxWidth: CGFloat = 200
    static let tabMinWidth: CGFloat = 120
    static let tabSpacing: CGFloat = 4
    static let trafficLightInset: CGFloat = 80
    static let controlRadius: CGFloat = 6
    static let panelRadius: CGFloat = 10
    static let iconButtonSize: CGFloat = 28

    // MARK: Motion

    static let hoverDuration: TimeInterval = 0.08
    static let panelDuration: TimeInterval = 0.12

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Helpers

    private static func dynamic(light: UInt32, dark: UInt32, name: String) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua])
                .map { $0 == .darkAqua || $0 == .accessibilityHighContrastDarkAqua } ?? false
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension NSView {
    /// Resolves a dynamic color against this view's appearance, for use in CALayer properties.
    func resolved(_ color: NSColor) -> CGColor {
        var cg = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { cg = color.cgColor }
        return cg
    }
}

extension Font {
    /// SwiftUI's handle on `Theme.mono`.
    static func mono(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        Font(Theme.mono(ofSize: size, weight: weight))
    }
}
