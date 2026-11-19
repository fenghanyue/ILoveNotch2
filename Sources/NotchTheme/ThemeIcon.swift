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

    public var name: String {
        switch self {
        case .feature(let feature): feature.rawValue
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

    /// The SF Symbol a symbol set draws for `role`, or nil for a set of SVGs.
    @MainActor static func symbol(_ role: IconRole, in set: String) -> String? {
        let info: SetInfo? =
            sets[set]
            ?? {
                let url = Bundle.themeResources.url(
                    forResource: "set", withExtension: "json", subdirectory: "Icons/\(set)")
                let info = url.flatMap { try? JSONDecoder().decode(SetInfo.self, from: Data(contentsOf: $0)) }
                sets[set] = .some(info)
                return info
            }()
        guard info?.kind == "symbols" else { return nil }
        return info?.symbols?[role.name]
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
