// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import Testing

@testable import NotchTheme

private let themeFiles: [URL] = {
    let directory = Bundle.themeResources.url(forResource: "Themes", withExtension: nil)
    let files = directory.flatMap {
        try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
    }
    return (files ?? []).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
}()

/// Every icon set a bundled theme uses.
private let iconSets = Set(Themes.all.map(\.icons.set)).sorted()

/// Every bundled theme decodes with every token valid, and names only fonts, icons, and skins the
/// app ships. The picker leaves out a theme that fails here, so a new file in Themes/ that passes
/// is a new choice in Settings.
@MainActor
struct ThemeTests {
    @Test func blackAndGlassShip() {
        let ids = Themes.all.map(\.id)
        #expect(ids.prefix(2) == ["black", "glass"], "Black first, the default")
        #expect(ids.count == themeFiles.count, "every file in Themes/ is in the picker")
    }

    @Test(arguments: themeFiles)
    func everyBundledThemeIsValid(file: URL) throws {
        // A missing or invalid token throws here, and the error names its key.
        let theme = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: file))
        #expect(theme.id == file.deletingPathExtension().lastPathComponent)
        #expect(theme.schema <= Theme.newestSchema)
        Themes.registerFonts()
        for face in [theme.fonts.display, theme.fonts.body, theme.fonts.mono] where !face.isSystem {
            #expect(
                NSFontManager.shared.availableMembers(ofFontFamily: face.family) != nil,
                "\(theme.id): no font family \(face.family) in Fonts/")
        }
        for role in IconRole.all {
            #expect(
                ThemeIcon.image(role, in: theme.icons.set) != nil,
                "\(theme.id): no \(role.name).svg in Icons/\(theme.icons.set)")
        }
        let named: [(SkinSlot, String?)] = [
            (.musicPlayer, theme.skins?.musicPlayer), (.tabRow, theme.skins?.tabRow),
            (.closedNotch, theme.skins?.closedNotch),
        ]
        for case (let slot, let name?) in named {
            #expect(slot.shipped.contains(name), "\(theme.id): no \(name) skin for \(slot)")
        }
    }

    @Test func storedNamesFromBeforeThemesWereFilesStillWork() {
        #expect(Themes.theme("black").id == "black")
        #expect(Themes.theme("glass").id == "glass")
        #expect(Themes.theme("chrome-from-the-future").id == "black", "an unknown theme falls back to Black")
    }

    /// Paper is light, so the closed notch and the header on its band take its cream; Black, already
    /// light on black, draws as it is. Only an accent Paper offers takes the accent's place.
    @Test func aLightThemeDrawsOnBlackInItsClosedInkAndKeepsToItsAccents() {
        let paper = Themes.theme("paper")
        #expect(paper.appearance == .light)
        #expect(paper.onBlack.appearance == .dark)
        #expect(paper.onBlack.colors.ink.text == "#F6F1E7")
        #expect(Themes.black.onBlack.colors.ink.text == "#FFFFFF")
        #expect(paper.withAccent("#D2462F").colors.accent.text == "#D2462F")
        #expect(paper.withAccent("#123456").colors.accent.text == "#2C4A9A", "not one of Paper's")
        #expect(Themes.black.withAccent("#D2462F").colors.accent.text == "system", "Black offers none")
    }

    /// A theme's stroke and caps reach every path, since some sets repeat them per path, and the
    /// rewritten file still draws.
    @Test func aLineSetsStrokeAndCapsAreRewrittenOnEveryPath() {
        let svg = #"<svg stroke-width="2" stroke-linecap="round"><p stroke-width="1.5" stroke-linejoin="round"/>"#
        let square = #"<svg stroke-width="2.5" stroke-linecap="square"><p stroke-width="2.5" stroke-linejoin="miter"/>"#
        #expect(ThemeIcon.restroke(svg, width: 2.5, cap: .square) == square)
        #expect(ThemeIcon.restroke(svg, width: nil, cap: .round) == svg)
        #expect(ThemeIcon.image(.feature(.media), in: "tabler", stroke: 2.5, cap: .square) != nil)
    }

    @Test func colorsAreHexOrTheSystemAccent() {
        #expect(ThemeColor.parse("#1F1D1A") != nil)
        #expect(ThemeColor.parse("#FFFFFF80") != nil)
        #expect(ThemeColor.parse("system") != nil)
        for bad in ["#FFF", "1F1D1A", "#1F1D1G", "#+FFFFF", "#FFFFFF8", "white"] {
            #expect(ThemeColor.parse(bad) == nil, "\(bad)")
        }
    }
}

/// A set's icons look one size side by side in the tab row. Measured from the ink each draws at the
/// row's size, since every file's frame is the same square whatever the glyph.
@MainActor
struct IconTests {
    /// Each tab's icon within a point and a half of the set's typical size, and centered to half a
    /// point. At 16 pt Tabler's squares and pages draw about 12 across and its circles 13.5, which
    /// look alike; sets drawn on a tighter or looser grid sit at their own size. Iconoir draws every
    /// calendar and clipboard half a point low.
    @Test(arguments: iconSets)
    func everyTabLooksTheSameSizeAndSitsCentered(set: String) throws {
        var sizes: [FeatureID: (size: Double, drop: Double)] = [:]
        for feature in FeatureID.allCases {
            let image = try #require(ThemeIcon.image(.feature(feature), in: set))
            let natural = ThemeIcon.symbol(.feature(feature), in: set) != nil
            let ink = try #require(Self.ink(of: image, size: ThemeIcon.size, natural: natural))
            sizes[feature] = ((ink.width * ink.height).squareRoot(), ink.drop)
        }
        let median = sizes.values.map(\.size).sorted()[sizes.count / 2]
        for (feature, ink) in sizes {
            #expect(abs(ink.size - median) <= 1.5, "\(set)/\(feature.rawValue) looks \(ink.size) pt, the set \(median)")
            #expect(abs(ink.drop) <= 0.5, "\(set)/\(feature.rawValue) sits \(ink.drop) pt off center")
        }
    }

    /// An image's ink drawn at 4×, in points: its size, and how far below the image's center it sits.
    /// An SVG fills the icon's square, as the view resizes it; a symbol (`natural`) keeps its own
    /// size, centered, as the system draws it.
    private static func ink(of image: NSImage, size: CGFloat, natural: Bool = false)
        -> (width: Double, height: Double, drop: Double)?
    {
        let side = Int(size * 4)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let drawn =
            natural
            ? CGSize(width: image.size.width * 4, height: image.size.height * 4) : CGSize(width: side, height: side)
        image.draw(
            in: NSRect(
                x: (CGFloat(side) - drawn.width) / 2, y: (CGFloat(side) - drawn.height) / 2, width: drawn.width,
                height: drawn.height))
        NSGraphicsContext.current = previous
        var (minX, maxX, minY, maxY) = (side, 0, side, 0)
        for y in 0..<side {
            for x in 0..<side where pixels[(y * side + x) * 4 + 3] > 20 {
                (minX, maxX, minY, maxY) = (min(minX, x), max(maxX, x), min(minY, y), max(maxY, y))
            }
        }
        guard minX <= maxX else { return nil }
        // Rows run top to bottom in memory, so a center past the middle row sits lower.
        return (
            Double(maxX - minX + 1) / 4, Double(maxY - minY + 1) / 4, (Double(minY + maxY) / 2 - Double(side) / 2) / 4
        )
    }
}
