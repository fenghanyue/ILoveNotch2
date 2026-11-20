// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchFeatures

/// Home's tiles: how they pack into pages, where that puts them, and that the choice is kept.
@MainActor
struct HomeTilesTests {
    private func slot(_ page: Int, _ column: Int, _ row: Int) -> TileSlot {
        TileSlot(page: page, column: column, row: row)
    }

    @Test func theFirstSixPackIntoTheBentoHomeAlwaysHad() {
        #expect(
            HomeTile.pack(HomeTile.defaults.map(\.size)) == [
                slot(0, 0, 0),  // music, 2×2
                slot(0, 2, 0),  // event, 2×1
                slot(0, 2, 1),  // tasks, 1×2
                slot(0, 3, 1),  // usage
                slot(0, 0, 2),  // script, 2×1
                slot(0, 3, 2),  // timer
            ])
    }

    @Test func moreThanAPageTurnsToTheNext() {
        let tiles = HomeTile.defaults + [.notes, .clipboard, .shortcuts, .network]
        #expect(
            HomeTile.pack(tiles.map(\.size)).suffix(4) == [
                slot(1, 0, 0), slot(1, 2, 0), slot(1, 0, 1), slot(1, 2, 1),
            ])
    }

    @Test func aSmallTileFillsAGapABigOneLeft() {
        let sizes = [HomeTile.music, .tasks, .event, .usage, .network].map(\.size)
        // The event doesn't fit beside the tasks, so it goes under the song; the small ones fill in.
        #expect(
            HomeTile.pack(sizes) == [slot(0, 0, 0), slot(0, 2, 0), slot(0, 0, 2), slot(0, 3, 0), slot(0, 3, 1)])
        // A full page sends even a small tile on.
        #expect(HomeTile.pack(Array(repeating: TileSize(columns: 1, rows: 1), count: 13)).last == slot(1, 0, 0))
    }

    @Test func aShortNotchPagesTwoByTwo() {
        let cells = HomeTile.pack(Array(repeating: TileSize(columns: 1, rows: 1), count: 5), columns: 2, rows: 2)
        #expect(cells == [slot(0, 0, 0), slot(0, 1, 0), slot(0, 0, 1), slot(0, 1, 1), slot(1, 0, 0)])
    }

    /// The frames the hand-placed bento gave the six cards at the notch's usual size: the right pair
    /// 240 pt, the rows a third of the height less the gaps.
    @Test func theFirstSixLandWhereTheyAlwaysDid() {
        let (tiles, pages) = HomeView.layout(HomeTile.defaults, in: CGSize(width: 428, height: 200))
        let row = (200 - 16) / 3.0
        let frames = Dictionary(uniqueKeysWithValues: tiles.map { ($0.tile, $0.frame) })
        func at(_ tile: HomeTile, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Bool {
            guard let frame = frames[tile] else { return false }
            return [frame.minX - x, frame.minY - y, frame.width - width, frame.height - height].allSatisfy {
                abs($0) < 0.001
            }
        }
        #expect(pages == 1)
        #expect(at(.music, 0, 0, 180, 2 * row + 8))
        #expect(at(.event, 188, 0, 240, row))
        #expect(at(.tasks, 188, row + 8, 116, 2 * row + 8))
        #expect(at(.usage, 312, row + 8, 116, row))
        #expect(at(.script, 0, 2 * row + 16, 180, row))
        #expect(at(.timer, 312, 2 * row + 16, 116, row))
    }

    @Test func theChoiceAndOrderAreKept() throws {
        let defaults = try #require(UserDefaults(suiteName: "HomeTiles.\(UUID().uuidString)"))
        let home = HomeFeature(defaults: defaults)
        #expect(home.tiles == HomeTile.defaults, "nothing changes for someone who never edits")
        home.add(.network)
        home.add(.network)
        home.remove(.usage)
        home.move(.network, to: .music)
        #expect(home.tiles == [.network, .music, .event, .tasks, .script, .timer])
        home.move(.music, to: .timer)
        #expect(home.tiles == [.network, .event, .tasks, .script, .timer, .music])
        #expect(HomeFeature(defaults: defaults).tiles == home.tiles)

        defaults.set(["notes", "someday", "notes", "music"], forKey: HomeFeature.tilesKey)
        #expect(HomeFeature(defaults: defaults).tiles == [.notes, .music], "unknown and repeated names skipped")
    }

    @Test func leavingHomeEndsEditing() {
        let home = HomeFeature(defaults: UserDefaults(suiteName: "HomeTiles.\(UUID().uuidString)")!)
        home.phase = .foreground
        home.editing = .adding
        home.phase = .background
        #expect(home.editing == nil)
    }
}
