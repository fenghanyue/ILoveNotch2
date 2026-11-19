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
/// stroke, so side by side in the tab row they look one size, where SF Symbols' shapes vary with
/// the glyph. The files sit unchanged in Icons/<set>; set.json says where each came from.
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
            if let image = Self.image(role, in: theme.icons.set) {
                Image(nsImage: image).renderingMode(.template).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)  // the button around it says what it does
    }

    /// Each icon loads once per set; macOS draws SVG natively, sharp at any size.
    @MainActor private static var images: [String: NSImage] = [:]

    @MainActor static func image(_ role: IconRole, in set: String) -> NSImage? {
        let key = "\(set)/\(role.name)"
        if let cached = images[key] { return cached }
        guard
            let url = Bundle.themeResources.url(
                forResource: role.name, withExtension: "svg", subdirectory: "Icons/\(set)"),
            let image = NSImage(contentsOf: url)
        else {
            Log.surface.error("No \(role.name, privacy: .public) icon in \(set, privacy: .public)")
            return nil
        }
        image.isTemplate = true
        images[key] = image
        return image
    }
}
