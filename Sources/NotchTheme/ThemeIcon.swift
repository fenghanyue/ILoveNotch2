// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import SwiftUI

/// What an icon stands for. Every icon set in Icons/ has one SVG per role, named by it, so a new
/// feature adds one file to each set.
public enum IconRole: Hashable, Sendable {
    case feature(FeatureID)
    /// All Apps, and lit while the drawer is open.
    case apps, appsOn
    /// Pin, and lit while pinned.
    case pin, pinOn
    case settings
    /// Edit and Done in the app drawer.
    case edit, done
    /// An icon inside a tab, by the role `ThemeSymbol.roles` gives its SF Symbol.
    case symbol(String)

    public var name: String {
        switch self {
        case .feature(let feature): feature.rawValue
        case .symbol(let role): role
        case .apps: "apps"
        case .appsOn: "apps-on"
        case .pin: "pin"
        case .pinOn: "pin-on"
        case .settings: "settings"
        case .edit: "edit"
        case .done: "done"
        }
    }

    public static var all: [IconRole] {
        FeatureID.allCases.map(IconRole.feature) + [.apps, .appsOn, .pin, .pinOn, .settings, .edit, .done]
    }
}

/// An icon from the theme's set, tinted like text. Sets draw every icon on one grid with one
/// stroke, so side by side in the tab row they look one size. The files sit unchanged in
/// Icons/<set>; set.json says where each came from. A symbol set's set.json names SF Symbols
/// instead, which the system draws.
public struct ThemeIcon: View {
    let role: IconRole
    var size: CGFloat
    @Environment(\.theme) private var theme

    /// Every icon in the header, tabs and buttons alike, one size as in a macOS 26 toolbar: a
    /// 24-unit grid at 16 pt draws Tabler's 2-unit stroke about as heavy as SF Symbols' medium.
    public static let size: CGFloat = 16

    public init(_ role: IconRole, size: CGFloat = ThemeIcon.size) {
        self.role = role
        self.size = size
    }

    public init(_ feature: FeatureID, size: CGFloat = ThemeIcon.size) {
        self.init(.feature(feature), size: size)
    }

    public var body: some View {
        Group {
            if let symbol = Self.symbol(role, in: theme.icons.set) {
                Image(systemName: symbol)
                    .font(.system(size: size * Self.symbolScale))
                    .symbolRenderingMode(theme.icons.rendering == .hierarchical ? .hierarchical : .monochrome)
            } else if let image = Self.image(
                role, in: theme.icons.set, stroke: theme.icons.stroke, cap: theme.icons.cap)
            {
                Image(nsImage: image).renderingMode(.template).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)  // the button around it says what it does
    }

    /// A symbol's point size for the icon's frame: SF Symbols draw about as large as their font, so
    /// at 0.8 their ink matches a 24-unit set's.
    static let symbolScale: CGFloat = 0.8

    /// What a set's set.json says about drawing it.
    private struct SetInfo: Decodable {
        /// "symbols" for a set that names SF Symbols instead of shipping SVGs.
        let kind: String
        let symbols: [String: String]?
    }

    @MainActor private static var sets: [String: SetInfo?] = [:]

    @MainActor private static func info(_ set: String) -> SetInfo? {
        sets[set]
            ?? {
                let url = Bundle.themeResources.url(
                    forResource: "set", withExtension: "json", subdirectory: "Icons/\(set)")
                let info = url.flatMap { try? JSONDecoder().decode(SetInfo.self, from: Data(contentsOf: $0)) }
                sets[set] = .some(info)
                return info
            }()
    }

    /// Whether `set` names SF Symbols instead of shipping SVGs.
    @MainActor static func drawsSymbols(_ set: String) -> Bool { info(set)?.kind == "symbols" }

    /// The SF Symbol a symbol set draws for `role`, or nil for a set of SVGs.
    @MainActor static func symbol(_ role: IconRole, in set: String) -> String? {
        guard drawsSymbols(set) else { return nil }
        return info(set)?.symbols?[role.name]
    }

    /// Each icon loads once per set and line; macOS draws SVG natively, sharp at any size. A line
    /// set's `stroke` and `cap` rewrite every stroke in the file. For a symbol set, the symbol at the
    /// icon's size, which the tests measure.
    @MainActor private static var images: [String: NSImage] = [:]

    @MainActor static func image(
        _ role: IconRole, in set: String, stroke: Double? = nil, cap: Theme.Icons.Cap? = nil
    ) -> NSImage? {
        let key = "\(set)/\(role.name)/\(stroke.map { "\($0)" } ?? "")/\(cap?.rawValue ?? "")"
        if let cached = images[key] { return cached }
        if let symbol = symbol(role, in: set) {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: Self.size * Self.symbolScale, weight: .regular))
            image?.isTemplate = true
            images[key] = image
            return image
        }
        let url = Bundle.themeResources.url(
            forResource: role.name, withExtension: "svg", subdirectory: "Icons/\(set)")
        let image: NSImage?
        if stroke == nil, cap == nil {
            image = url.flatMap(NSImage.init(contentsOf:))
        } else {
            let svg = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            image = svg.flatMap { NSImage(data: Data(Self.restroke($0, width: stroke, cap: cap).utf8)) }
        }
        guard let image else {
            Log.surface.error("No \(role.name, privacy: .public) icon in \(set, privacy: .public)")
            return nil
        }
        image.isTemplate = true
        images[key] = image
        return image
    }

    /// The SVG with every stroke `width` wide, and square ends and mitered joins for `.square`.
    /// Some sets repeat the attributes on each path, so every one is replaced, not just the root's.
    static func restroke(_ svg: String, width: Double?, cap: Theme.Icons.Cap?) -> String {
        var svg = svg
        if let width { svg.replace(/stroke-width="[^"]*"/, with: "stroke-width=\"\(width)\"") }
        if cap == .square {
            svg.replace("stroke-linecap=\"round\"", with: "stroke-linecap=\"square\"")
            svg.replace("stroke-linejoin=\"round\"", with: "stroke-linejoin=\"miter\"")
        }
        return svg
    }
}

/// An icon inside a tab, named as the SF Symbol it stands for: the theme's own icon for it when the
/// theme draws its set everywhere (`icons.everywhere`), else the symbol. It takes its size from the
/// `.themeFont` around it and the image scale, as a symbol does, so it drops in for
/// `Image(systemName:)`.
public struct ThemeSymbol: View {
    let systemName: String
    @Environment(\.theme) private var theme
    @Environment(\.themeFontSize) private var fontSize
    @Environment(\.imageScale) private var imageScale

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        if theme.icons.everywhere == true, let role = Self.roles[systemName], !ThemeIcon.drawsSymbols(theme.icons.set),
            let image = ThemeIcon.image(
                .symbol(role), in: theme.icons.set, stroke: theme.icons.stroke, cap: theme.icons.cap)
        {
            Image(nsImage: image).renderingMode(.template).resizable()
                .frame(width: side, height: side)
                .accessibilityHidden(true)  // the control around it says what it does
        } else if theme.icons.everywhere == true, theme.icons.rendering == .hierarchical {
            Image(systemName: systemName).symbolRenderingMode(.hierarchical)
        } else {
            Image(systemName: systemName)
        }
    }

    /// A set's square for the font: a symbol draws about as large as its font, so a 24-unit set's
    /// ink matches it at 1 / 0.8 (ThemeIcon's scale, turned around), grown or shrunk by the image
    /// scale as a symbol is.
    private var side: CGFloat {
        let scale: CGFloat =
            switch imageScale {
            case .small: 0.8
            case .large: 1.3
            default: 1
            }
        return (fontSize / ThemeIcon.symbolScale * scale).rounded()
    }

    /// The role of each SF Symbol the tabs draw. A symbol not here stays a symbol in every theme:
    /// device glyphs (AirPods, a battery's level), the 15-second skips, and text sizes.
    public static let roles: [String: String] = [
        // Playing
        "play.fill": "play", "playpause": "play", "play.circle": "play", "pause.fill": "pause",
        "backward.fill": "previous", "backward.end.fill": "previous", "forward.fill": "next",
        "shuffle": "shuffle", "repeat": "repeat", "repeat.1": "repeat-one", "music.note": "music",
        "list.bullet": "list", "quote.bubble": "quote", "airplayaudio": "airplay",
        "clock.arrow.circlepath": "history", "waveform": "waveform",
        "speaker.fill": "volume", "speaker.wave.1.fill": "volume", "speaker.wave.2.fill": "volume",
        "speaker.wave.2": "volume", "speaker.wave.3.fill": "volume", "speaker.slash.fill": "volume-off",
        "mic": "mic", "mic.fill": "mic", "mic.slash.fill": "mic-off",
        // Editing and lists
        "magnifyingglass": "search", "xmark": "close", "xmark.circle.fill": "close", "plus": "plus",
        "plus.circle.fill": "plus", "minus": "minus", "trash": "trash", "pencil": "edit",
        "square.and.pencil": "edit", "checkmark": "done", "circle": "circle", "checkmark.circle": "check-circle",
        "checkmark.circle.fill": "check-circle", "star": "star", "star.fill": "star-fill", "heart.fill": "heart",
        "pin": "pin", "pin.fill": "pin-on", "pin.slash": "pin",
        // Things
        "link": "link", "text.alignleft": "text", "note.text": "text", "photo": "image", "folder.fill": "folder",
        "questionmark.folder": "folder", "doc.on.clipboard": "clipboard", "doc.on.clipboard.fill": "clipboard",
        "list.clipboard": "clipboard", "tray.full": "shelf", "calendar": "calendar",
        "calendar.badge.plus": "calendar", "checklist": "tasks", "timer": "timer", "terminal": "agents",
        "apple.terminal": "agents", "web.camera": "mirror", "square.grid.2x2": "apps",
        // Arrows
        "chevron.left": "chevron-left", "chevron.right": "chevron-right", "arrow.up": "arrow-up",
        "arrow.down": "arrow-down", "arrow.up.circle.fill": "upload", "arrow.down.circle.fill": "download",
        "arrow.down.circle": "download", "arrow.down.to.line": "download", "tray.and.arrow.down": "download",
        "tray.and.arrow.down.fill": "download", "arrow.up.arrow.down": "sort",
        "arrow.up.arrow.down.circle": "sort", "arrow.clockwise": "refresh",
        "arrow.counterclockwise.circle.fill": "refresh", "arrow.up.right": "external",
        "square.and.arrow.up": "share",
        // States
        "ellipsis.circle": "more", "slider.horizontal.3": "sliders", "exclamationmark.triangle.fill": "warning",
        "exclamationmark.circle.fill": "alert", "exclamationmark": "alert", "bell": "bell", "bell.fill": "bell",
        "video": "video", "video.fill": "video", "video.slash": "video-off", "cup.and.saucer.fill": "coffee",
        "moon.zzz.fill": "moon", "infinity": "infinity", "flip.horizontal": "flip", "hand.raised.fill": "hand",
        "gauge.with.needle": "gauge", "gauge.with.dots.needle.67percent": "gauge",
        "dot.radiowaves.left.and.right": "broadcast", "square.stack.3d.up": "layers",
        "square.2.layers.3d": "layers", "slash.circle": "ban", "lock": "lock", "key": "key", "key.fill": "key",
    ]

    /// The roles above that aren't tab or header icons already: every set of SVGs has a file for each.
    public static var setRoles: [String] {
        let existing = Set(IconRole.all.map(\.name))
        return Set(roles.values).subtracting(existing).sorted()
    }
}

/// `Label(title, systemImage:)` with the theme's icon for the symbol (`ThemeSymbol`).
public struct ThemeLabel: View {
    let title: String
    let symbol: String

    public init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            ThemeSymbol(symbol)
        }
    }
}
