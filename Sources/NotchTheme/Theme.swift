// SPDX-License-Identifier: MIT
import SwiftUI

/// A look for the notch: colors, fonts, icons, and shapes, decoded from a JSON file in Themes/
/// (docs/themes.md has the format). Views inside the notch read it from the environment
/// (`\.theme`), or through the `.themeInk`-style shape styles and `.themeFont`, so none of them
/// hard-codes a color or a font.
public struct Theme: Decodable, Identifiable, Sendable {
    /// The newest format this app reads. A file with a newer `schema` is skipped, and unknown keys
    /// are ignored, so themes written for later versions fail safe.
    public static let newestSchema = 1

    public let schema: Int
    /// Matches the file name, and is what Preferences stores: "black" and "glass" from before
    /// themes were files still name their themes.
    public let id: String
    public let name: String
    private let order: Int?
    public let appearance: Appearance
    public let surface: Surface
    public let colors: Colors
    public let fonts: Fonts
    public let icons: Icons
    public let radii: Radii
    public let seekBar: SeekBar
    public let waveform: Waveform
    public let skins: Skins?

    /// Where the picker puts it: by `order`, then by name.
    public var sortKey: (Int, String) { (order ?? 1000, name) }

    public enum Appearance: String, Decodable, Sendable {
        case dark, light

        public var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    }

    /// The open notch's backing. Closed, the notch is always black, to hide in the camera housing.
    public struct Surface: Decodable, Sendable {
        public let kind: Kind
        /// The fill, and what glass falls back to before macOS 26 and with Reduce Transparency.
        public let color: ThemeColor

        public enum Kind: String, Decodable, Sendable {
            case solid, glass
        }
    }

    public struct Colors: Decodable, Sendable {
        public let ink: ThemeColor
        public let secondary: ThemeColor
        public let tertiary: ThemeColor
        /// Platters, tracks, and chips.
        public let fill: ThemeColor
        public let accent: ThemeColor
        /// Text and icons on an accent fill.
        public let onAccent: ThemeColor
        /// The prompter's current word and search matches; the accent when a theme has none.
        public let highlight: ThemeColor?
    }

    public struct Fonts: Decodable, Sendable {
        public let display: Face
        public let body: Face
        public let mono: Face

        public enum Role: Sendable {
            /// Titles, track names, big numbers.
            case display
            case body
            /// Times, keys, code.
            case mono
        }

        public subscript(role: Role) -> Face {
            switch role {
            case .display: display
            case .body: body
            case .mono: mono
            }
        }
    }

    /// One font role: the system font, or a family bundled in Fonts/.
    public struct Face: Decodable, Sendable {
        /// "system", or a registered family name.
        public let family: String
        /// The system font's design; ignored for a bundled family.
        public let design: Design?
        /// Overrides the weight a view asks for, for faces drawn at one weight.
        public let weight: Weight?
        /// Multiplies the size a view asks for, for faces that draw small or large.
        public let scale: Double?

        public var isSystem: Bool { family == "system" }

        public enum Design: String, Decodable, Sendable {
            case `default`, rounded, serif, monospaced

            var font: Font.Design {
                switch self {
                case .default: .default
                case .rounded: .rounded
                case .serif: .serif
                case .monospaced: .monospaced
                }
            }
        }

        public enum Weight: String, Decodable, Sendable {
            case ultralight, thin, light, regular, medium, semibold, bold, heavy, black

            var font: Font.Weight {
                switch self {
                case .ultralight: .ultraLight
                case .thin: .thin
                case .light: .light
                case .regular: .regular
                case .medium: .medium
                case .semibold: .semibold
                case .bold: .bold
                case .heavy: .heavy
                case .black: .black
                }
            }
        }
    }

    public struct Icons: Decodable, Sendable {
        /// A folder in Icons/.
        public let set: String
        /// Line sets only: replaces the files' stroke width.
        public let stroke: Double?
        /// Line sets only: round or square ends and joins.
        public let cap: Cap?

        public enum Cap: String, Decodable, Sendable {
            case round, square
        }
    }

    /// The open notch's corners.
    public struct Radii: Decodable, Sendable {
        public let notchTop: Double
        public let notchBottom: Double
    }

    /// The wavy seek bar's line. Every theme keeps the wave.
    public struct SeekBar: Decodable, Sendable {
        public let line: Double
        public let cap: Icons.Cap
        public let rest: Rest
        public let head: Head
        public let fill: Fill

        public enum Rest: String, Decodable, Sendable {
            case solid
        }

        public enum Head: String, Decodable, Sendable {
            case bar
        }
    }

    public struct Waveform: Decodable, Sendable {
        public let bar: Double
        public let gap: Double
        public let shape: Shape
        public let fill: Fill

        public enum Shape: String, Decodable, Sendable {
            case round
        }
    }

    /// What the media visuals are tinted with.
    public enum Fill: String, Decodable, Sendable {
        /// The now-playing artwork's color, or ink without one.
        case artwork
        case accent, ink
    }

    /// Views a theme swaps in for the default one in a slot. Each names a skin the app ships
    /// (`SkinSlot.shipped`); a missing or unknown one draws the default view.
    public struct Skins: Decodable, Sendable {
        public let musicPlayer: String?
        public let tabRow: String?
        public let closedNotch: String?
    }

    /// The skin a theme names for `slot`, if the app ships it.
    public func skin(_ slot: SkinSlot) -> String? {
        let name: String? =
            switch slot {
            case .musicPlayer: skins?.musicPlayer
            case .tabRow: skins?.tabRow
            case .closedNotch: skins?.closedNotch
            }
        return name.flatMap { slot.shipped.contains($0) ? $0 : nil }
    }
}

/// The places a theme can draw its own view instead of the default one.
public enum SkinSlot: CaseIterable, Sendable {
    case musicPlayer, tabRow, closedNotch

    /// The skins this app ships for the slot, by the name a theme uses. A skin's view lives with
    /// the slot's default view; its name goes here so the bundled-themes test can check it.
    public var shipped: Set<String> {
        switch self {
        case .musicPlayer, .tabRow, .closedNotch: []
        }
    }
}

/// A color written "#RRGGBB" or "#RRGGBBAA", or "system" for macOS's accent color.
public struct ThemeColor: Decodable, Sendable {
    public let color: Color

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = Self.parse(text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "\(text) isn't #RRGGBB, #RRGGBBAA, or system"))
        }
        self.color = color
    }

    static func parse(_ text: String) -> Color? {
        if text == "system" { return .accentColor }
        let digits = text.dropFirst()
        guard text.first == "#", digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
            let value = UInt32(digits, radix: 16)
        else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        func channel(_ shift: UInt32) -> Double { Double((rgba >> shift) & 0xFF) / 255 }
        return Color(.sRGB, red: channel(24), green: channel(16), blue: channel(8), opacity: channel(0))
    }
}

extension Theme {
    /// The font for `role` at the size and weight a view asks for. With the system face this is
    /// exactly `.system(size:weight:design:)`, so Black draws as it did before themes.
    public func font(
        _ role: Fonts.Role, size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil
    ) -> Font {
        let face = fonts[role]
        let weight = face.weight?.font ?? weight
        let size = size * (face.scale ?? 1)
        if face.isSystem {
            return .system(size: size, weight: weight, design: design ?? face.design?.font ?? .default)
        }
        return Font(Self.font(family: face.family, size: size, weight: weight))
    }

    /// A bundled family's face, by its CSS weight. `.custom(family).weight(_:)` misses faces in
    /// variable fonts (Nunito and Doto's Black come out ExtraBold, Space Grotesk's 600 Medium) and pins
    /// Bricolage's optical size; naming the weight axis and an automatic optical size reaches every
    /// one, and the weight trait still picks the right file of a static family such as Plex.
    static func font(family: String, size: CGFloat, weight: Font.Weight) -> CTFont {
        let css = Self.cssWeights[weight] ?? 400
        let wght = 0x7767_6874  // the 'wght' axis
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontTraitsAttribute: [kCTFontWeightTrait: Self.weightTraits[weight] ?? 0],
            kCTFontVariationAttribute: [wght: css],
            kCTFontOpticalSizeAttribute: "auto",
        ]
        return CTFontCreateWithFontDescriptor(
            CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
    }

    private static let cssWeights: [Font.Weight: Double] = [
        .ultraLight: 100, .thin: 200, .light: 300, .regular: 400, .medium: 500, .semibold: 600, .bold: 700,
        .heavy: 800, .black: 900,
    ]

    /// CoreText's weight traits for the same weights (NSFont.Weight's values).
    private static let weightTraits: [Font.Weight: CGFloat] = [
        .ultraLight: NSFont.Weight.ultraLight.rawValue, .thin: NSFont.Weight.thin.rawValue,
        .light: NSFont.Weight.light.rawValue, .regular: 0, .medium: NSFont.Weight.medium.rawValue,
        .semibold: NSFont.Weight.semibold.rawValue, .bold: NSFont.Weight.bold.rawValue,
        .heavy: NSFont.Weight.heavy.rawValue, .black: NSFont.Weight.black.rawValue,
    ]

    /// The font for `role` in a text style, such as `.caption`. With the system face this is the
    /// style itself.
    public func font(_ role: Fonts.Role, _ style: Font.TextStyle) -> Font {
        let face = fonts[role]
        if face.isSystem, face.design == nil, face.scale == nil, face.weight == nil {
            return .system(style)
        }
        let size = NSFont.preferredFont(forTextStyle: style.nsTextStyle).pointSize
        return font(role, size: size, weight: style == .headline ? .bold : .regular)
    }
}

extension Font.TextStyle {
    fileprivate var nsTextStyle: NSFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
