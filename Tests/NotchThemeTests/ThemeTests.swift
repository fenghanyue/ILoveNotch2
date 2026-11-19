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
    @Test(arguments: iconSets, FeatureID.allCases)
    func everyTabLooksTheSameSizeAndSitsCentered(set: String, feature: FeatureID) throws {
        let image = try #require(ThemeIcon.image(.feature(feature), in: set))
        let ink = try #require(Self.ink(of: image, size: ThemeIcon.size))
        // At 16 pt Tabler's squares and pages draw about 12 across, its circles 13.5, which look alike.
        // Its triangle play button (11 × 12) looks smaller, and the stopwatch's crown lifts it half a
        // point.
        let size = (ink.width * ink.height).squareRoot()
        #expect((11.75...13.75).contains(size), "\(set)/\(feature.rawValue) looks \(size) pt")
        #expect(abs(ink.drop) <= 0.3, "\(set)/\(feature.rawValue) sits \(ink.drop) pt off center")
    }

    /// An image's ink drawn at 4×, in points: its size, and how far below the image's center it sits.
    private static func ink(of image: NSImage, size: CGFloat) -> (width: Double, height: Double, drop: Double)? {
        let side = Int(size * 4)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
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
