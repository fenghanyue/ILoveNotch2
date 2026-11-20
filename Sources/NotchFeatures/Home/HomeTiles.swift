// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import Observation

/// The Home tab. It does no work of its own: while it's open, the tabs it glances at run in full
/// (`FeatureID.onHome`, and the tiles `HomeView` adds). It keeps which tiles are on Home, in order,
/// and whether they're being edited.
@MainActor
@Observable
public final class HomeFeature: NotchFeature {
    /// Edit mode: arranging the tiles, or picking one to add.
    public enum Editing: Sendable {
        case arranging, adding
    }

    public let id = FeatureID.home
    /// Leaving Home ends editing.
    public var phase: FeaturePhase = .stopped {
        didSet { if phase != .foreground { editing = nil } }
    }
    /// The tiles on Home, in order, kept between launches. A tile whose tab is off keeps its place and
    /// comes back there when the tab does.
    public private(set) var tiles: [HomeTile] {
        didSet { defaults.set(tiles.map(\.rawValue), forKey: Self.tilesKey) }
    }
    /// Edit mode; nil outside it.
    public var editing: Editing?
    /// The page Home shows; nil for the first.
    var page: Int?

    static let tilesKey = "home.tiles"
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A name this version doesn't know (from a newer one) is skipped, and a tile is on Home once.
        var seen = Set<HomeTile>()
        tiles =
            defaults.stringArray(forKey: Self.tilesKey)?.compactMap(HomeTile.init(rawValue:))
            .filter { seen.insert($0).inserted } ?? HomeTile.defaults
    }

    /// Adds a tile after the others.
    public func add(_ tile: HomeTile) {
        guard !tiles.contains(tile) else { return }
        tiles.append(tile)
    }

    public func remove(_ tile: HomeTile) {
        tiles.removeAll { $0 == tile }
    }

    /// Puts `tile` in `target`'s place; the tiles from there to where it was move over by one.
    public func move(_ tile: HomeTile, to target: HomeTile) {
        guard tile != target, let from = tiles.firstIndex(of: tile), let to = tiles.firstIndex(of: target) else {
            return
        }
        tiles.remove(at: from)
        tiles.insert(tile, at: to)
    }
}

/// A card on Home: what it shows, and the room it takes on a page of four columns and three rows.
public enum HomeTile: String, CaseIterable, Sendable {
    case music, event, tasks, usage, timer, script, notes, clipboard, shortcuts, network

    /// Home as it always was: the six cards, in the order that packs into its bento.
    public static let defaults: [HomeTile] = [.music, .event, .tasks, .usage, .script, .timer]

    /// The tab it glances at, which a click opens.
    public var feature: FeatureID {
        switch self {
        case .music: .media
        case .event: .calendar
        case .tasks: .tasks
        case .usage: .usage
        case .timer: .timer
        case .script: .prompter
        case .notes: .notes
        case .clipboard: .clipboard
        case .shortcuts: .shortcuts
        case .network: .network
        }
    }

    /// The song big, the tasks tall, the event, the script and the short lists wide.
    var size: TileSize {
        switch self {
        case .music: TileSize(columns: 2, rows: 2)
        case .tasks: TileSize(columns: 1, rows: 2)
        case .event, .script, .notes, .clipboard, .shortcuts: TileSize(columns: 2, rows: 1)
        case .usage, .timer, .network: TileSize(columns: 1, rows: 1)
        }
    }

    /// Its name in the Add Tile picker.
    var title: String {
        switch self {
        case .music: "Now Playing"
        case .event: "Next Event"
        case .tasks: "Tasks"
        case .usage: "AI Usage"
        case .timer: "Timer"
        case .script: "Script"
        case .notes: "Latest Note"
        case .clipboard: "Recent Copies"
        case .shortcuts: "Shortcuts"
        case .network: "Network"
        }
    }

    /// Fills each page in turn, a row at a time from the top left: every tile goes in the first place
    /// it fits, on the first page with room, so a small one fills a gap a bigger one left. A tile
    /// larger than the page is cut to it.
    static func pack(_ sizes: [TileSize], columns: Int = 4, rows: Int = 3) -> [TileSlot] {
        var taken: [[Bool]] = []  // each page's cells, row by row
        return sizes.map { size in
            let width = min(max(size.columns, 1), columns)
            let height = min(max(size.rows, 1), rows)
            var page = 0
            while true {
                if page == taken.count { taken.append(Array(repeating: false, count: columns * rows)) }
                for row in 0...(rows - height) {
                    for column in 0...(columns - width) {
                        let cells = (row..<row + height).flatMap { line in
                            (column..<column + width).map { line * columns + $0 }
                        }
                        guard cells.allSatisfy({ !taken[page][$0] }) else { continue }
                        for cell in cells { taken[page][cell] = true }
                        return TileSlot(page: page, column: column, row: row)
                    }
                }
                page += 1  // a new page always has room
            }
        }
    }
}

/// How many columns and rows a tile spans.
struct TileSize: Hashable, Sendable {
    var columns: Int
    var rows: Int

    /// "Wide", as the Add Tile picker says it.
    var name: String {
        switch (columns, rows) {
        case (1, 1): "Small"
        case (1, _): "Tall"
        case (_, 1): "Wide"
        default: "Large"
        }
    }
}

/// Where a tile lands: its page, and the column and row of its top left cell there.
struct TileSlot: Hashable, Sendable {
    var page: Int
    var column: Int
    var row: Int
}
