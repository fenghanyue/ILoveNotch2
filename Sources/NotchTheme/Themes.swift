// SPDX-License-Identifier: MIT
import CoreText
import Foundation
import NotchCore
import SwiftUI

/// The bundled themes. Adding a theme is adding a JSON file to Themes/.
public enum Themes {
    /// Every valid bundled theme, in picker order. A file that doesn't decode, has a newer schema,
    /// or whose id isn't its file name is left out and logged; the bundled-themes test fails on it.
    public static let all: [Theme] = load(Bundle.themeResources.url(forResource: "Themes", withExtension: nil))

    /// The default, and what an unknown stored id falls back to.
    // ponytail: black.json always ships (ThemeTests), so there's no compiled copy to drift from it.
    public static let black = all.first { $0.id == "black" } ?? all[0]

    /// The theme Preferences stores by id, or Black when it's gone or unknown.
    public static func theme(_ id: String) -> Theme {
        all.first { $0.id == id } ?? black
    }

    static func load(_ directory: URL?) -> [Theme] {
        let files =
            directory.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
            ?? []
        let themes = files.filter { $0.pathExtension == "json" }.compactMap { file -> Theme? in
            do {
                let theme = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: file))
                guard theme.schema <= Theme.newestSchema else { return nil }
                guard theme.id == file.deletingPathExtension().lastPathComponent else {
                    Log.surface.error(
                        "Theme \(file.lastPathComponent, privacy: .public) has id \(theme.id, privacy: .public)")
                    return nil
                }
                return theme
            } catch {
                Log.surface.error("Theme \(file.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                return nil
            }
        }
        return themes.sorted { $0.sortKey < $1.sortKey }
    }

    /// Makes every font in Fonts/ available to this process. Call once at launch, before the
    /// notch draws.
    public static func registerFonts() {
        guard let fonts = Bundle.themeResources.url(forResource: "Fonts", withExtension: nil),
            let files = FileManager.default.enumerator(at: fonts, includingPropertiesForKeys: nil)
        else { return }
        for case let file as URL in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) {
                let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
                Log.surface.error("Font \(file.lastPathComponent, privacy: .public): \(reason, privacy: .public)")
            }
        }
    }
}

extension EnvironmentValues {
    /// The notch's theme, set once at its root.
    @Entry public var theme: Theme = Themes.black
}

/// The theme's colors by role, for code that needs a `Color` (a tint, gradient stops); views that
/// take a style use `.themeInk` and its siblings instead.
public enum ThemeToken: Sendable {
    /// Primary text and icons: white in Black.
    case ink
    case secondary, tertiary
    /// Platters, tracks, and chips.
    case fill
    case accent
    /// Text and icons on an accent fill.
    case onAccent
    /// The prompter's current word and search matches.
    case highlight
}

extension Theme {
    public func color(_ token: ThemeToken) -> Color {
        switch token {
        case .ink: colors.ink.color
        case .secondary: colors.secondary.color
        case .tertiary: colors.tertiary.color
        case .fill: colors.fill.color
        case .accent: colors.accent.color
        case .onAccent: colors.onAccent.color
        case .highlight: (colors.highlight ?? colors.accent).color
        }
    }
}

/// A theme color as a shape style, resolved from the environment where it's drawn, so a view can
/// write `.foregroundStyle(.themeInk.opacity(0.55))` without reading the theme itself.
public struct ThemeStyle: ShapeStyle {
    let token: ThemeToken

    public func resolve(in environment: EnvironmentValues) -> Color {
        environment.theme.color(token)
    }
}

extension ShapeStyle where Self == ThemeStyle {
    public static var themeInk: ThemeStyle { ThemeStyle(token: .ink) }
    public static var themeSecondary: ThemeStyle { ThemeStyle(token: .secondary) }
    public static var themeTertiary: ThemeStyle { ThemeStyle(token: .tertiary) }
    public static var themeFill: ThemeStyle { ThemeStyle(token: .fill) }
    public static var themeAccent: ThemeStyle { ThemeStyle(token: .accent) }
    public static var themeOnAccent: ThemeStyle { ThemeStyle(token: .onAccent) }
    public static var themeHighlight: ThemeStyle { ThemeStyle(token: .highlight) }
}

extension View {
    /// The theme's font for `role`, at the size and weight this view asks for.
    public func themeFont(
        _ role: Theme.Fonts.Role, size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil
    ) -> some View {
        modifier(ThemeFont { $0.font(role, size: size, weight: weight, design: design) })
    }

    /// The theme's font for `role` in a text style, such as `.caption`.
    public func themeFont(_ role: Theme.Fonts.Role, _ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(
            ThemeFont { theme in
                let font = theme.font(role, style)
                return weight.map { font.weight($0) } ?? font
            })
    }
}

private struct ThemeFont: ViewModifier {
    let font: (Theme) -> Font
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.font(font(theme))
    }
}

extension Bundle {
    /// NotchTheme's resources (themes, fonts, icons). The app's Resources come first: in a packaged
    /// app, SwiftPM's `Bundle.module` can fail to find its bundle and stop the app, as NotchUsage's
    /// `openUsageResources` explains.
    static let themeResources: Bundle = {
        let name = "OpenNotchKit_NotchTheme.bundle"
        for case let base? in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let bundle = Bundle(url: base.appending(path: name)) { return bundle }
        }
        return .module
    }()
}
