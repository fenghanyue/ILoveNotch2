// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchTheme
import SwiftUI

/// Tiles, each sized by what it holds: the song big, with its cover and controls; the next event
/// wide, with Join; the tasks tall, ticked off in place; the AI plans' ring and the timer small; the
/// script along the bottom, with Start; and, once added, the latest note, the last copies, the favorite
/// shortcuts, and the network's speed. They pack in order into pages of four columns and three rows
/// (`HomeTile.pack`), and more than a page turns sideways, with dots under it; a short notch lines
/// them up two to a row instead (three when wide), two rows a page. A click on a tile opens its tab,
/// and its buttons act in place. A tab that's off drops its tile, and the ones after it move up.
///
/// Edit mode, from the pencil that shows while the pointer is over Home or from any tile's menu, rocks
/// the tiles: one dragged onto another takes its place, the minus takes a tile off Home, and Add
/// brings back one that isn't on it. Done, or leaving Home, ends it.
public struct HomeView: View {
    let home: HomeFeature
    let media: MediaFeature
    let calendar: CalendarFeature
    let tasks: TasksFeature
    let timer: TimerFeature
    let prompter: PrompterFeature
    let notes: NotesFeature
    let clipboard: ClipboardFeature
    let shortcuts: ShortcutsFeature
    let network: NetworkFeature
    /// The AI plans' card, from the GitHub build's AI Usage; nil leaves it out.
    let usage: AnyView?
    /// The tabs that are on.
    let tabs: Set<FeatureID>
    let open: (FeatureID) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The cards rise into place once the tab is open.
    @State private var appeared = false
    /// The pointer is over Home, which shows the pencil.
    @State private var hovering = false
    /// The tile on the move in edit mode.
    @State private var drag: TileDrag?

    public init(
        home: HomeFeature, media: MediaFeature, calendar: CalendarFeature, tasks: TasksFeature,
        timer: TimerFeature, prompter: PrompterFeature, notes: NotesFeature, clipboard: ClipboardFeature,
        shortcuts: ShortcutsFeature, network: NetworkFeature, usage: AnyView?, tabs: Set<FeatureID>,
        open: @escaping (FeatureID) -> Void
    ) {
        self.home = home
        self.media = media
        self.calendar = calendar
        self.tasks = tasks
        self.timer = timer
        self.prompter = prompter
        self.notes = notes
        self.clipboard = clipboard
        self.shortcuts = shortcuts
        self.network = network
        self.usage = usage
        self.tabs = tabs
        self.open = open
    }

    private static let gap: CGFloat = 8
    /// Shorter than this, the cards line up in rows.
    private static let bentoHeight: CGFloat = 150
    /// Where a drag in edit mode is measured, to find the tile under the pointer.
    private static let pageSpace = "HomePage"
    /// Between pages, out of sight past the margin around the one in view.
    private static let pageGap: CGFloat = 24

    public var body: some View {
        let shown = self.shown
        GeometryReader { proxy in
            ZStack {
                if shown.isEmpty {
                    empty
                } else {
                    pager(shown, in: proxy.size)
                }
                if home.editing == .adding {
                    picker(in: proxy.size).transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Edit, or Add and Done while editing, on Home's top right corner, half over the gap above it.
        .overlay(alignment: .topTrailing) { corner.offset(x: 4, y: -7) }
        .onHover { hovering = $0 }
        .onAppear { appeared = true }
        .animation(motion, value: home.editing)
    }

    /// The tiles whose tab is on, in Home's order.
    private var shown: [HomeTile] { home.tiles.filter(isShown) }

    /// Whether a tile's tab is on: for the AI plans', whether this build has them and they're on.
    private func isShown(_ tile: HomeTile) -> Bool {
        tile == .usage ? usage != nil : tabs.contains(tile.feature)
    }

    /// Tiles that could go on Home: not on it yet, with their tab on.
    private var addable: [HomeTile] {
        HomeTile.allCases.filter { !home.tiles.contains($0) && isShown($0) }
    }

    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78) }

    // MARK: Layout

    /// A shown tile and where it goes: its page, and its frame there.
    struct Placed: Identifiable {
        let tile: HomeTile
        /// Its place among the shown tiles, the order they rise in.
        let order: Int
        let page: Int
        let frame: CGRect
        var id: HomeTile { tile }
    }

    /// Every shown tile's page and frame. Four columns and three rows, the right pair half the width,
    /// or 240 pt (58% when narrower) so its small tiles keep about 116 pt each, the left pair giving way;
    /// with the first six that's the song over the script on the left, and on the right the event, then
    /// the tasks beside the small cards. In a short notch, every tile one of two cells a row (three in a
    /// wide notch), two rows a page.
    static func layout(_ shown: [HomeTile], in size: CGSize) -> (tiles: [Placed], pages: Int) {
        let short = size.height < bentoHeight
        let columns = short ? (size.width >= 560 ? 3 : 2) : 4
        let rows = short ? 2 : 3
        let spans = shown.map { short ? TileSize(columns: 1, rows: 1) : $0.size }
        let slots = HomeTile.pack(spans, columns: columns, rows: rows)
        let widths: [CGFloat]
        if short {
            widths = Array(repeating: (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns), count: columns)
        } else {
            let right = max((size.width - gap) / 2, min(240, size.width * 0.58))
            let left = size.width - gap - right
            widths = [(left - gap) / 2, (left - gap) / 2, (right - gap) / 2, (right - gap) / 2]
        }
        let xs = edges(widths)
        let ys = edges(Array(repeating: (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows), count: rows))
        let tiles = shown.indices.map { index in
            let slot = slots[index]
            let right = slot.column + min(spans[index].columns, columns)
            let bottom = slot.row + min(spans[index].rows, rows)
            let frame = CGRect(
                x: xs[slot.column], y: ys[slot.row], width: xs[right] - gap - xs[slot.column],
                height: ys[bottom] - gap - ys[slot.row])
            return Placed(tile: shown[index], order: index, page: slot.page, frame: frame)
        }
        return (tiles, (slots.map(\.page).max() ?? 0) + 1)
    }

    /// Where each of a line of cells `sizes` long starts, with a gap between them, and where one more
    /// would.
    private static func edges(_ sizes: [CGFloat]) -> [CGFloat] {
        sizes.reduce(into: [0]) { edges, size in edges.append((edges.last ?? 0) + size + gap) }
    }

    /// The pages side by side, one in view, turned a page at a time; dots under them when there's more
    /// than one.
    private func pager(_ shown: [HomeTile], in size: CGSize) -> some View {
        let layout = Self.layout(shown, in: size)
        return ScrollViewReader { reader in
            ScrollView(.horizontal) {
                // Apart by more than the margin below, so a page's card shadows never show on the next.
                HStack(spacing: Self.pageGap) {
                    ForEach(0..<layout.pages, id: \.self) { page in
                        self.page(layout.tiles.filter { $0.page == page })
                            .frame(width: size.width, height: size.height, alignment: .topLeading)
                    }
                }
                .scrollTargetLayout()
            }
            // A page at a time, each lined up with the leading edge (`.paging` would land between them).
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Bindable(home).page)
            .scrollIndicators(.never)
            .scrollDisabled(layout.pages < 2)
            // The tiles' shadows and outlines, and the edit badges on their top edges, show past the
            // pages' edges, as they did before there were pages.
            .scrollClipDisabled()
            .clipShape(Margin())
            // In the margin the notch keeps under its tab, so the tiles keep their size.
            .overlay(alignment: .bottom) {
                if layout.pages > 1, home.editing != .adding { dots(layout.pages).offset(y: 16) }
            }
            .onChange(of: layout.pages) { _, pages in
                if let page = home.page, page >= pages { home.page = pages - 1 }
            }
            // Back on Home, the page it was on: the position follows changes, not where it starts.
            .onAppear {
                if let page = home.page { reader.scrollTo(page, anchor: .leading) }
            }
        }
    }

    private func page(_ tiles: [Placed]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(tiles) { placed in
                tile(placed, among: tiles)
                    .frame(width: placed.frame.width, height: placed.frame.height)
                    .offset(x: placed.frame.minX, y: placed.frame.minY)
                    .zIndex(drag?.tile == placed.tile ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(.named(Self.pageSpace))
    }

    /// One dot a page, the one in view lit; a click turns to it.
    private func dots(_ count: Int) -> some View {
        let current = min(home.page ?? 0, count - 1)
        return HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    withAnimation(motion) { home.page = index }
                } label: {
                    Circle()
                        .fill(.themeInk.opacity(index == current ? 0.85 : 0.25))
                        .frame(width: 5, height: 5)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(index + 1) of \(count)")
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }
    }

    /// Nothing to show: no tiles on Home, or their tabs all off.
    private var empty: some View {
        VStack(spacing: 8) {
            Text(home.tiles.isEmpty ? "Nothing on Home yet" : "Turn on a tab in Settings to see it here")
                .themeFont(.body, size: 12)
                .foregroundStyle(.themeInk.opacity(0.6))
            if home.editing == nil, !addable.isEmpty {
                Button("Add Tiles") { edit(.adding) }
                    .buttonStyle(.plain)
                    .themeFont(.body, size: 11, weight: .semibold)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .themePlatter(0.12, in: controlShape)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Tiles

    /// A card: its backing (the theme's card color, by kind, or its platter), a glow in what it shows
    /// in a dark theme, and its content. A click anywhere opens its tab. In edit mode it rocks, a click
    /// does nothing, its buttons sleep, and it drags onto another tile to take its place.
    private func tile(_ placed: Placed, among page: [Placed]) -> some View {
        let tile = placed.tile
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let title = tile.feature.title
        let editing = home.editing != nil
        // Under the picker the tiles hold still and keep their badges out of the way.
        let arranging = home.editing == .arranging
        let lifted = drag?.tile == tile
        // Erased, or ten tiles each carrying every card's type overflow the stack in a debug build.
        return AnyView(content(tile))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // A short notch's one-line cards (a 30 pt cover) fit its 47 pt tiles with 8 pt over and under.
            .padding(.horizontal, 10)
            .padding(.vertical, placed.frame.height < 50 ? 8 : 10)
            .allowsHitTesting(!editing)
            .background { glow(tile).clipShape(shape) }
            .background { backing(HomeTile.allCases.firstIndex(of: tile) ?? 0, in: shape) }
            .foregroundStyle(ink)
            .overlay {
                // The tile a dragged one would take the place of.
                if drag?.target == tile { shape.strokeBorder(theme.color(.accent), lineWidth: 2) }
            }
            .overlay(alignment: .topLeading) {
                if arranging, !lifted { removeBadge(tile).offset(x: 6, y: -7) }
            }
            .scaleEffect(lifted ? 1.04 : 1)
            .opacity(lifted ? 0.85 : 1)
            .offset(lifted ? drag?.offset ?? .zero : .zero)
            .modifier(Wiggle(active: arranging && !reduceMotion, still: drag != nil, pace: placed.order))
            .contentShape(shape)
            .onTapGesture { if !editing { activate(tile) } }
            .gesture(dragging(tile, among: page), including: editing ? .all : .subviews)
            .contextMenu { menu(tile) }
            .help(editing ? "Drag onto another tile to move it there" : "Open \(title)")
            .modifier(RunsOnHome(feature: glanced(tile), home: home))
            .accessibilityElement(children: editing ? .ignore : .contain)
            .accessibilityLabel(title)
            .accessibilityHint(editing ? "Drag onto another tile to move it there." : "")
            .accessibilityActions { actions(tile) }
            // Each rises 6 pt and fades in, 30 ms after the one before; with Reduce Motion they're
            // just there.
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 6)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.22).delay(Double(placed.order) * 0.03), value: appeared)
    }

    @ViewBuilder private func content(_ tile: HomeTile) -> some View {
        switch tile {
        case .music: music
        case .event: event
        case .tasks: taskList
        case .usage: if let usage { usageCard(usage) }
        case .timer: if timerIsIdle { timerIdle } else { timerCard }
        case .script: script
        case .notes: noteCard
        case .clipboard: clipCard
        case .shortcuts: shortcutPads
        case .network: NetworkGlance(network: network, secondary: secondary) { header(.network) }
        }
    }

    /// A click on a tile: its tab, open on the latest note for Notes.
    private func activate(_ tile: HomeTile) {
        if tile == .notes, let note = latestNote {
            notes.search = ""
            notes.selection = note.id
        }
        open(tile.feature)
    }

    /// The tab a tile glances at that runs in full only while its tile is on Home, besides
    /// `FeatureID.onHome`'s.
    private func glanced(_ tile: HomeTile) -> (any NotchFeature)? {
        switch tile {
        case .notes: notes
        case .shortcuts: shortcuts
        case .network: network
        default: nil
        }
    }

    // MARK: Editing

    private func edit(_ editing: HomeFeature.Editing?) {
        withAnimation(motion) { home.editing = editing }
    }

    private func remove(_ tile: HomeTile) {
        withAnimation(motion) { home.remove(tile) }
    }

    /// Moves a tile past the shown tile before or after it, for its menu and VoiceOver.
    private func step(_ tile: HomeTile, by offset: Int) {
        let shown = self.shown
        guard let index = shown.firstIndex(of: tile), shown.indices.contains(index + offset) else { return }
        withAnimation(motion) { home.move(tile, to: shown[index + offset]) }
    }

    /// Adds a tile, back to arranging, on the page it went to.
    private func add(_ tile: HomeTile, in size: CGSize) {
        withAnimation(motion) {
            home.add(tile)
            home.editing = .arranging
            home.page = Self.layout(shown, in: size).tiles.first { $0.tile == tile }?.page
        }
    }

    private func dragging(_ tile: HomeTile, among page: [Placed]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.pageSpace))
            .onChanged { value in
                let target = page.first { $0.tile != tile && $0.frame.contains(value.location) }?.tile
                drag = TileDrag(tile: tile, offset: value.translation, target: target)
            }
            .onEnded { _ in
                withAnimation(motion) {
                    if let target = drag?.target { home.move(tile, to: target) }
                    drag = nil
                }
            }
    }

    @ViewBuilder private func menu(_ tile: HomeTile) -> some View {
        if home.editing == nil {
            Button("Edit Home…") { edit(.arranging) }
        } else {
            let shown = self.shown
            Button("Move Earlier") { step(tile, by: -1) }.disabled(shown.first == tile)
            Button("Move Later") { step(tile, by: 1) }.disabled(shown.last == tile)
            Button("Remove from Home") { remove(tile) }
            Divider()
            Button("Done") { edit(nil) }
        }
    }

    @ViewBuilder private func actions(_ tile: HomeTile) -> some View {
        if home.editing == nil {
            Button("Open \(tile.feature.title)") { activate(tile) }
            Button("Edit Home") { edit(.arranging) }
        } else {
            Button("Move Earlier") { step(tile, by: -1) }
            Button("Move Later") { step(tile, by: 1) }
            Button("Remove from Home") { remove(tile) }
        }
    }

    /// The minus on a tile's top edge in edit mode: the sheet's color on its ink, like Done.
    private func removeBadge(_ tile: HomeTile) -> some View {
        Button {
            remove(tile)
        } label: {
            ThemeSymbol("minus")
                .themeFont(.body, size: 8, weight: .heavy)
                .foregroundStyle(theme.surface.color.color)
                .frame(width: 16, height: 16)
                .background(.themeInk, in: Circle())
                .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .help("Remove \(tile.title) from Home")
        .accessibilityLabel("Remove \(tile.title) from Home")
    }

    /// The pencil while the pointer is over Home; Add and Done in edit mode; nothing while adding,
    /// where the picker has its own close.
    @ViewBuilder private var corner: some View {
        switch home.editing {
        case nil:
            if hovering {
                cornerButton(help: "Edit Home") {
                    ThemeSymbol("pencil").frame(width: 22)
                } action: {
                    edit(.arranging)
                }
                .transition(.opacity)
            }
        case .arranging?:
            HStack(spacing: 4) {
                if !addable.isEmpty {
                    cornerButton(help: "Add a tile") {
                        HStack(spacing: 3) {
                            ThemeSymbol("plus").imageScale(.small)
                            Text("Add")
                        }
                        .padding(.horizontal, 9)
                    } action: {
                        edit(.adding)
                    }
                }
                Button {
                    edit(nil)
                } label: {
                    Text("Done")
                        .themeFont(.body, size: 11, weight: .semibold)
                        .foregroundStyle(theme.surface.color.color)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background(.themeInk, in: controlShape)
                        .contentShape(controlShape)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Done editing Home")
            }
            .fixedSize()
        case .adding?:
            EmptyView()
        }
    }

    /// A small button on the sheet's own color, so it reads over a tile's corner.
    private func cornerButton(
        help: String, @ViewBuilder label: () -> some View, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label()
                .themeFont(.body, size: 11, weight: .semibold)
                .foregroundStyle(.themeInk)
                .frame(height: 22)
                .themePlatter(0.14, in: controlShape)
                .background(theme.surface.color.color, in: controlShape)
                .contentShape(controlShape)
        }
        .buttonStyle(PressableButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    /// The tiles not on Home, over the tiles, inside the notch: a click adds one.
    private func picker(in size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let tiles = addable
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 6)]
        let grid = LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(tiles, id: \.self) { tile in
                Button {
                    add(tile, in: size)
                } label: {
                    pickerRow(tile)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Add \(tile.title) to Home")
                .accessibilityLabel("Add \(tile.title)")
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Add a Tile")
                    .themeFont(.body, size: caps ? 10 : 11, weight: .semibold)
                    .textCase(caps ? .uppercase : nil)
                    .tracking(caps ? 1 : 0)
                    .foregroundStyle(.themeInk.opacity(0.62))
                Spacer(minLength: 0)
                Button {
                    edit(.arranging)
                } label: {
                    ThemeSymbol("xmark")
                        .themeFont(.body, size: 10, weight: .semibold)
                        .frame(width: 22, height: 22)
                        .themePlatter(0.1, in: controlShape)
                        .contentShape(controlShape)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Close")
                .accessibilityLabel("Close")
            }
            if tiles.isEmpty {
                Text("Every tile is on Home. Turn on more tabs in Settings for more.")
                    .themeFont(.body, size: 12)
                    .foregroundStyle(.themeInk.opacity(0.62))
            } else {
                ViewThatFits(in: .vertical) {
                    grid
                    ScrollView { grid }.fadingEdges()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.themeInk)
        .background {
            shape.fill(theme.surface.color.color)
                .themePlatter(0.05, in: shape)
                .overlay(shape.strokeBorder(.themeInk.opacity(0.2), lineWidth: 1))
        }
    }

    /// A tile in the picker: its tab's icon, its name, and its size.
    private func pickerRow(_ tile: HomeTile) -> some View {
        let plate = RoundedRectangle(cornerRadius: square ? 0 : 7, style: .continuous)
        return HStack(spacing: 8) {
            ThemeIcon(tile.feature, size: 14)
                .frame(width: 28, height: 26)
                .themePlatter(0.12, in: plate)
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.title).themeFont(.body, size: 11, weight: .semibold)
                Text(tile.size.name).themeFont(.body, size: 9).foregroundStyle(.themeInk.opacity(0.55))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(3)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func backing(_ index: Int, in shape: RoundedRectangle) -> some View {
        if let cards = theme.cards, !cards.colors.isEmpty {
            shape.fill(cards.colors[index % cards.colors.count].color)
        } else {
            // On a light sheet a card covers its texture in the sheet's own color, like an index card
            // on the page, outlined, with a soft print shadow unless the theme draws a hard one.
            let light = theme.appearance == .light
            Color.clear
                .themePlatter(light ? 0.01 : 0.07, in: shape)
                .background {
                    if light {
                        if theme.controls?.shadow != .hard { shape.fill(ink.opacity(0.07)).offset(x: 3, y: 3) }
                        shape.fill(theme.surface.color.color)
                    }
                }
        }
    }

    /// Dark sheets light the song's card in its cover's color, the event's in its calendar's, and a
    /// running timer's in the accent.
    @ViewBuilder private func glow(_ tile: HomeTile) -> some View {
        if glows, let spot = glowSpot(tile) {
            RadialGradient(
                colors: [spot.color.opacity(0.3), .clear], center: spot.center, startRadius: 0, endRadius: 150)
        }
    }

    private func glowSpot(_ tile: HomeTile) -> (color: Color, center: UnitPoint)? {
        let color: Color? =
            switch tile {
            case .music: media.nowPlaying == nil ? nil : media.accent?.color
            case .event: nextEvent.map { $0.color?.color ?? theme.color(.accent) }
            case .timer: timerIsIdle ? nil : theme.color(.accent)
            default: nil
            }
        let center: UnitPoint = tile == .music ? .init(x: 0.16, y: 0.42) : tile == .event ? .trailing : .bottomLeading
        return color.map { ($0, center) }
    }

    // MARK: Theme

    /// What's written on a card: the ink of the theme's card colors, or its own.
    private var ink: Color { theme.cards?.ink.color ?? theme.color(.ink) }
    private var secondary: Color { ink.opacity(0.62) }
    private var radius: CGFloat { theme.controls?.radius.map { CGFloat($0) } ?? 16 }
    /// Outlined themes label their cards in small capitals.
    private var caps: Bool { theme.controls?.style == .outline }
    private var square: Bool { theme.controls?.radius == 0 }
    private var glows: Bool {
        theme.appearance == .dark && theme.cards == nil && theme.controls?.style != .outline && !reduceTransparency
    }
    /// Join's and play's colors: the ink with the sheet's color on it where the theme has no controls
    /// of its own (Black's white button), else the accent and its ink.
    private var primary: (fill: Color, ink: Color) {
        theme.controls == nil ? (ink, theme.surface.color.color) : (theme.color(.accent), theme.color(.onAccent))
    }
    private var controlShape: AnyShape {
        theme.controls?.radius.map { AnyShape(RoundedRectangle(cornerRadius: $0, style: .continuous)) }
            ?? AnyShape(Capsule())
    }
    /// The song's color: the cover's, or the theme's when its seek bar says so.
    private var musicTint: Color { theme.color(theme.seekBar.fill, artwork: media.accent?.color) }

    // MARK: Parts

    /// The card's name, a button to its tab, and what it says at a glance on the right. When both
    /// don't fit, the name stays whole and the glance goes: "Tasks ›" rather than "TAS… 3 due".
    private func header(_ feature: FeatureID, detail: String? = nil, tint: Color? = nil) -> some View {
        ViewThatFits(in: .horizontal) {
            headerRow(feature, detail: detail, tint: tint)
            headerRow(feature, detail: nil, tint: tint)
        }
    }

    private func headerRow(_ feature: FeatureID, detail: String?, tint: Color?) -> some View {
        HStack(spacing: 6) {
            Button {
                open(feature)
            } label: {
                HStack(spacing: 2) {
                    Text(feature.title)
                    ThemeSymbol("chevron.right").imageScale(.small)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .themeFont(.body, size: caps ? 10 : 11, weight: .semibold)
            .textCase(caps ? .uppercase : nil)
            .tracking(caps ? 1 : 0)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .themeFont(.body, size: 10, weight: tint == nil ? .regular : .semibold)
                    .foregroundStyle(tint ?? secondary)
            }
        }
        .foregroundStyle(secondary)
        .lineLimit(1)
    }

    /// A card with nothing to show but a line saying so.
    private func notice(_ feature: FeatureID, _ text: String) -> some View {
        let line = Text(text).themeFont(.body, size: 12).foregroundStyle(secondary).lineLimit(2)
        return ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 6) {
                header(feature)
                line
            }
            line
        }
    }

    private func bar(_ fraction: Double, tint: Color, height: CGFloat = 4) -> some View {
        let shape = RoundedRectangle(cornerRadius: square ? 0 : height / 2)
        return shape.fill(ink.opacity(0.16))
            .overlay {
                shape.fill(tint)
                    .scaleEffect(x: min(max(fraction, 0), 1), y: 1, anchor: .leading)
                    .shadow(color: glows ? tint.opacity(0.6) : .clear, radius: 4)
            }
            .frame(minWidth: 40, maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
    }

    // MARK: Music

    /// Shorter cards shrink the cover and drop the card's name; the shortest is one row.
    @ViewBuilder private var music: some View {
        if let now = media.nowPlaying {
            ViewThatFits(in: .vertical) {
                musicStack(now, cover: 72, header: true)
                musicStack(now, cover: 56, header: true)
                musicStack(now, cover: 56, header: false)
                musicStack(now, cover: 44, header: false)
                musicRow(now)
            }
        } else {
            notice(.media, "Nothing playing")
        }
    }

    private func musicStack(_ now: NowPlaying, cover size: CGFloat, header: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if header { self.header(.media, detail: playerName(now)) }
            HStack(spacing: 12) {
                cover(size)
                VStack(alignment: .leading, spacing: 3) {
                    Text(now.title).themeFont(.display, size: size >= 56 ? 19 : 15, weight: .semibold)
                    if let line = trackLine(now) {
                        Text(line).themeFont(.body, size: 12).foregroundStyle(secondary)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            musicControls(now)
        }
    }

    private func musicRow(_ now: NowPlaying) -> some View {
        HStack(spacing: 10) {
            cover(30)
            VStack(alignment: .leading, spacing: 1) {
                Text(now.title).themeFont(.display, size: 13, weight: .semibold)
                if let artist = now.artist {
                    Text(artist).themeFont(.body, size: 11).foregroundStyle(secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            playButton(now, size: 26)
                .buttonStyle(PressableButtonStyle())
                .disabled(!media.hasControls)
        }
    }

    private func trackLine(_ now: NowPlaying) -> String? {
        let line = [now.artist, now.album].compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// The app it plays in.
    private func playerName(_ now: NowPlaying) -> String? {
        guard let id = now.appBundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return nil }
        return FileManager.default.displayName(atPath: app.path).replacing(".app", with: "")
    }

    /// Outlined themes frame the cover like a print; dark ones light it in its color.
    private func cover(_ size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(radius, size * 0.2), style: .continuous)
        return ZStack {
            if let artwork = media.artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
            } else {
                shape.fill(musicTint.opacity(0.3))
                ThemeSymbol("music.note").themeFont(.body, size: size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            if caps { shape.stroke(theme.controls?.lineColor?.color ?? ink.opacity(0.4), lineWidth: 1) }
        }
        .shadow(color: glows ? musicTint.opacity(0.45) : .clear, radius: size * 0.16, y: size * 0.06)
        .accessibilityHidden(true)
    }

    /// Back, play or pause, and ahead (by 15 seconds where the player skips that way), then how far in.
    private func musicControls(_ now: NowPlaying) -> some View {
        let interval = now.skipsByInterval
        return HStack(spacing: 4) {
            Button {
                media.send(interval ? .skipBackward : .previousTrack)
            } label: {
                ThemeSymbol(interval ? "gobackward.15" : "backward.fill").frame(width: 24, height: 26)
            }
            .accessibilityLabel(interval ? "Back 15 seconds" : "Previous track")
            playButton(now, size: 30)
            Button {
                media.send(interval ? .skipForward : .nextTrack)
            } label: {
                ThemeSymbol(interval ? "goforward.15" : "forward.fill").frame(width: 24, height: 26)
            }
            .accessibilityLabel(interval ? "Forward 15 seconds" : "Next track")
            progress(now).padding(.leading, 6)
        }
        .themeFont(.body, size: 13)
        .buttonStyle(PressableButtonStyle())
        .disabled(!media.hasControls)
    }

    /// An ink disc, or the accent on themes with controls of their own; a ring on a light sheet.
    private func playButton(_ now: NowPlaying, size: CGFloat) -> some View {
        let disc = square ? AnyShape(Rectangle()) : AnyShape(Circle())
        let light = theme.appearance == .light
        return Button {
            media.send(.togglePlayPause)
        } label: {
            ThemeSymbol(now.isPlaying ? "pause.fill" : "play.fill")
                .themeFont(.body, size: size * 0.4, weight: .bold)
                .foregroundStyle(light ? ink : primary.ink)
                .frame(width: size, height: size)
                .background {
                    if light { disc.stroke(ink, lineWidth: 1.5) } else { disc.fill(primary.fill) }
                }
                .contentShape(disc)
        }
        .accessibilityLabel(now.isPlaying ? "Pause" : "Play")
    }

    /// The time in and left around a bar, or the bar alone when narrow. Once a second while playing.
    @ViewBuilder private func progress(_ now: NowPlaying) -> some View {
        if let duration = now.duration, duration > 0 {
            TimelineView(.periodic(from: .now, by: now.isPlaying ? 1 : 3600)) { context in
                let position = min(max(now.position(at: context.date) ?? 0, 0), duration)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(formatTime(position, roundingUp: false))
                        bar(position / duration, tint: musicTint)
                        Text("-" + formatTime(duration - position, roundingUp: false))
                    }
                    bar(position / duration, tint: musicTint)
                }
                .themeFont(.body, size: 10)
                .monospacedDigit()
                .foregroundStyle(secondary)
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    // MARK: Calendar

    /// The next event still to come today, whichever day the Calendar tab shows.
    private var nextEvent: DayEvent? {
        calendar.events(on: Calendar.current.startOfDay(for: .now)).first { !$0.isAllDay && $0.end > .now }
    }

    @ViewBuilder private var event: some View {
        if calendar.access != .granted {
            notice(.calendar, "Allow access in the Calendar tab")
        } else if let next = nextEvent {
            // "in 18 min" moves on once a minute.
            TimelineView(.everyMinute) { _ in
                let when = Self.when(next, now: .now)
                let tint = eventTint(next)
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        header(.calendar, detail: when, tint: tint)
                        eventRow(next, title: 16) {
                            Text(eventLine(next)).themeFont(.body, size: 11).foregroundStyle(secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        header(.calendar, detail: when, tint: tint)
                        eventRow(next, title: 15) { EmptyView() }
                    }
                    eventRow(next, title: 13) {
                        Text(when).themeFont(.body, size: 11, weight: .semibold).foregroundStyle(tint)
                    }
                }
            }
        } else {
            notice(.calendar, "Nothing else today")
        }
    }

    /// The title and a line under it beside Join, which says so where there's room.
    private func eventRow(_ event: DayEvent, title size: CGFloat, @ViewBuilder detail: () -> some View)
        -> some View
    {
        let words = VStack(alignment: .leading, spacing: 1) {
            Text(event.title).themeFont(.display, size: size, weight: .semibold)
            detail()
        }
        .lineLimit(1)
        let joins = event.meeting != nil && !event.isDeclined
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                words.frame(minWidth: 130, idealWidth: 130, maxWidth: .infinity, alignment: .leading)
                if joins { joinButton(event, labeled: true) }
            }
            HStack(spacing: 8) {
                words.frame(maxWidth: .infinity, alignment: .leading)
                if joins { joinButton(event, labeled: false) }
            }
        }
    }

    /// "in 18 min" in the calendar's color where cards glow, else in the accent, or the ink where the
    /// accent is a fill rather than a color for words (Brutal's yellow).
    private func eventTint(_ event: DayEvent) -> Color {
        if glows { return event.color?.color ?? theme.color(.accent) }
        return theme.selectsOnAccent ? ink : theme.color(.accent)
    }

    /// "11:00–11:30 · Google Meet", or where it is.
    private func eventLine(_ event: DayEvent) -> String {
        let times =
            event.start.formatted(date: .omitted, time: .shortened) + "–"
            + event.end.formatted(date: .omitted, time: .shortened)
        return [times, event.meeting?.service ?? event.place].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Now" once it's started, "in 18 min" within the hour, else when it starts.
    static func when(_ event: DayEvent, now: Date) -> String {
        guard event.start > now else { return "Now" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes < 60 ? "in \(minutes) min" : event.start.formatted(date: .omitted, time: .shortened)
    }

    private func joinButton(_ event: DayEvent, labeled: Bool) -> some View {
        Button {
            calendar.join(event)
        } label: {
            Group {
                if labeled { ThemeLabel("Join", symbol: "video.fill") } else { ThemeSymbol("video.fill") }
            }
            .themeFont(.body, size: 12, weight: .semibold)
            .foregroundStyle(primary.ink)
            .padding(.horizontal, labeled ? 12 : 9)
            .frame(height: 28)
            .background(primary.fill, in: controlShape)
            .contentShape(controlShape)
        }
        .buttonStyle(PressableButtonStyle())
        .help(event.meeting.map { "Join on \($0.service)" } ?? "Join")
        .accessibilityLabel("Join")
    }

    // MARK: Tasks

    /// As many tasks as fit, soonest due first, each ticked off in place.
    @ViewBuilder private var taskList: some View {
        if tasks.access != .granted {
            notice(.tasks, "Allow access in the Tasks tab")
        } else if tasks.tasks.isEmpty {
            notice(.tasks, "Nothing to do")
        } else {
            ViewThatFits(in: .vertical) {
                taskStack(5, header: true)
                taskStack(4, header: true)
                taskStack(3, header: true)
                taskStack(2, header: true)
                taskStack(1, header: true)
                taskStack(1, header: false)
            }
        }
    }

    private func taskStack(_ count: Int, header: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if header { self.header(.tasks, detail: dueSummary) }
            ForEach(tasks.tasks.prefix(count)) { taskRow($0) }
        }
    }

    /// "3 due" today or before, or how many are open.
    private var dueSummary: String {
        let now = Date.now
        let due = tasks.tasks.filter { $0.group(now: now) <= .today }.count
        return due > 0 ? "\(due) due" : "\(tasks.tasks.count) open"
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                    tasks.complete(task)
                }
            } label: {
                ThemeSymbol("circle").themeFont(.body, size: 13).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).themeFont(.body, size: 12, weight: .medium)
                if let due = task.due {
                    Text(DueLabel.text(for: due, hasTime: task.hasTime))
                        .themeFont(.body, size: 10)
                        .foregroundStyle(task.isOverdue() ? Color.red : secondary)  // overdue: red in every theme
                }
            }
            .lineLimit(1)
        }
    }

    // MARK: AI Usage

    private func usageCard(_ usage: AnyView) -> some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 6) {
                header(.usage)
                usage
            }
            usage
        }
        .minimumScaleFactor(0.8)
    }

    // MARK: Timer

    /// What's left of the countdown, or the stopwatch's time, changing once a second without
    /// animating, and still while paused.
    private var timerCard: some View {
        let countdown = timer.countdown
        let running = countdown?.isRunning ?? timer.stopwatch.isRunning
        return TimelineView(.periodic(from: .now, by: running ? 1 : 3600)) { context in
            let seconds = countdown?.remaining(at: context.date) ?? timer.stopwatch.elapsed(at: context.date)
            let time = formatTime(seconds, roundingUp: countdown != nil)
            let done = countdown.map { $0.total > 0 ? 1 - seconds / $0.total : 0 }
            let stack = { (size: CGFloat, label: String?) in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        header(.timer)
                        timerButton(running)
                    }
                    timerDigits(time, size: size, running: running, label: label)
                    if let done { bar(done, tint: theme.color(.accent), height: 3) }
                }
            }
            // Narrower cards drop the word after the time, then shrink it; shorter ones are one row.
            ViewThatFits {
                stack(22, countdown == nil ? "elapsed" : "left")
                stack(22, nil)
                stack(18, nil)
                HStack(spacing: 6) {
                    timerDigits(time, size: 18, running: running, label: nil)
                    Spacer(minLength: 0)
                    timerButton(running)
                }
            }
        }
    }

    private func timerDigits(_ time: String, size: CGFloat, running: Bool, label: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(time)
                .themeFont(.numbers, size: size, weight: .semibold)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .opacity(running ? 1 : 0.5)
            if let label { Text(label).themeFont(.body, size: 10).foregroundStyle(secondary) }
        }
        .lineLimit(1)
    }

    /// No countdown, and the stopwatch still.
    private var timerIsIdle: Bool { timer.countdown == nil && !timer.stopwatch.isRunning }

    /// Nothing running: a few lengths to start one with.
    private var timerIdle: some View {
        let line = Text("Start a timer").themeFont(.body, size: 12).foregroundStyle(secondary).lineLimit(1)
        let presets = ViewThatFits(in: .horizontal) {
            presetRow(3)
            presetRow(2)
            presetRow(1)
        }
        return ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 4) {
                header(.timer)
                line
                presets
            }
            VStack(alignment: .leading, spacing: 3) {
                line
                presets
            }
            presets
        }
    }

    private func presetRow(_ count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(Self.timerPresets.prefix(count), id: \.self) { seconds in
                Button {
                    timer.start(seconds)
                } label: {
                    Text(TimerView.length(seconds, short: true))
                        .themeFont(.body, size: 11, weight: .semibold)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .modifier(CardChip(strength: 0.1, shape: controlShape))
                        .contentShape(controlShape)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Start a \(TimerView.length(seconds)) timer")
                .accessibilityLabel("Start a \(TimerView.spoken(seconds)) timer")
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// The idle timer's lengths, from the Timer tab's own.
    private static let timerPresets: [TimeInterval] = [300, 900, 1500]

    private func timerButton(_ running: Bool) -> some View {
        Button {
            if timer.countdown != nil {
                running ? timer.pause() : timer.resume()
            } else {
                timer.toggleStopwatch()
            }
        } label: {
            ThemeSymbol(running ? "pause.fill" : "play.fill")
                .themeFont(.body, size: 9, weight: .bold)
                .frame(width: 22, height: 22)
                .modifier(CardChip(strength: 0.12, shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(running ? "Pause timer" : "Resume timer")
    }

    // MARK: Prompter

    /// The script's first lines, how long it takes to read, and Start, which opens the prompter on it.
    @ViewBuilder private var script: some View {
        let text = prompter.script.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            notice(.prompter, "No script yet")
        } else {
            let preview = String(text.prefix(400)).replacing(/\s+/, with: " ")
            let words = text.split(whereSeparator: \.isWhitespace).count
            let minutes = max(1, Int((Double(words) / PrompterFeature.wordsPerSecond / 60).rounded()))
            let lines = { (limit: Int) in Text(preview).themeFont(.display, size: 13).lineLimit(limit) }
            HStack(spacing: 10) {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        header(.prompter, detail: "\(minutes) min")
                        lines(8)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        header(.prompter, detail: "\(minutes) min")
                        lines(2)
                    }
                    lines(2)
                    lines(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                startButton
            }
        }
    }

    private var startButton: some View {
        Button {
            open(.prompter)
            prompter.start()
        } label: {
            HStack(spacing: 4) {
                ThemeSymbol("play.fill").imageScale(.small)
                Text(prompter.isReading ? "Resume" : "Start")
            }
            .themeFont(.body, size: 11, weight: .semibold)
            .foregroundStyle(secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .modifier(CardChip(strength: 0.1, shape: controlShape))
            .contentShape(controlShape)
        }
        .buttonStyle(PressableButtonStyle())
        .help("Read it in the prompter")
    }

    // MARK: Notes

    /// The note edited last.
    private var latestNote: Note? {
        notes.notes.filter { !$0.isEmpty }.max { $0.modified < $1.modified }
    }

    /// The latest note's title and the line after it; a click opens it in Notes.
    @ViewBuilder private var noteCard: some View {
        if let note = latestNote {
            let title = Text(note.title).themeFont(.display, size: 14, weight: .semibold)
            let excerpt = note.excerpt
            let line = Text(excerpt).themeFont(.body, size: 11).foregroundStyle(secondary)
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    header(.notes)
                    title
                    if !excerpt.isEmpty { line }
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    if !excerpt.isEmpty { line }
                }
                title
            }
            .lineLimit(1)
        } else {
            notice(.notes, "No notes yet")
        }
    }

    // MARK: Clipboard

    /// The last copies, newest first; a click puts one back on the clipboard.
    @ViewBuilder private var clipCard: some View {
        let recent = Array(clipboard.items.prefix(3))
        if recent.isEmpty {
            notice(.clipboard, clipboard.isRecording ? "Nothing copied yet" : "Turn on history in the Clipboard tab")
        } else {
            ViewThatFits(in: .vertical) {
                clipStack(recent, header: true)
                clipStack(Array(recent.prefix(2)), header: true)
                clipStack(Array(recent.prefix(2)), header: false)
                clipStack(Array(recent.prefix(1)), header: false)
            }
        }
    }

    private func clipStack(_ items: [ClipItem], header: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if header { self.header(.clipboard) }
            ForEach(items) { clipRow($0) }
        }
    }

    private func clipRow(_ item: ClipItem) -> some View {
        let line = Self.line(for: item)
        return Button {
            clipboard.pick(item)
        } label: {
            HStack(spacing: 6) {
                ThemeSymbol(Self.symbol(for: item.kind))
                    .themeFont(.body, size: 10)
                    .foregroundStyle(secondary)
                    .frame(width: 12)
                Text(line).themeFont(.body, size: 12)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy it again")
        .accessibilityLabel("Copy \(line) again")
    }

    /// A copy in one line: its first line of text, the files' names, or what the image is.
    static func line(for item: ClipItem) -> String {
        switch item.kind {
        case .files:
            return item.paths.map { URL(filePath: $0).lastPathComponent }.joined(separator: ", ")
        case .text, .link, .image:
            let first = item.text.split(whereSeparator: \.isNewline).lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return first ?? item.text
        }
    }

    private static func symbol(for kind: ClipItem.Kind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .files: "folder.fill"
        }
    }

    // MARK: Shortcuts

    /// The favorites' pads, two a row; a click runs one.
    @ViewBuilder private var shortcutPads: some View {
        let favorites = shortcuts.favorites
        if shortcuts.status == .unavailable {
            notice(.shortcuts, "Shortcuts can't run on this Mac")
        } else if favorites.isEmpty {
            notice(.shortcuts, shortcuts.status == .loading ? "Loading…" : "Pick favorites in the Shortcuts tab")
        } else {
            ViewThatFits(in: .vertical) {
                padGrid(favorites, header: true)
                padGrid(favorites, header: false)
                padGrid(Array(favorites.prefix(2)), header: true)
                padGrid(Array(favorites.prefix(2)), header: false)
            }
        }
    }

    private func padGrid(_ names: [String], header: Bool) -> some View {
        let rows = stride(from: 0, to: names.count, by: 2).map { Array(names[$0..<min($0 + 2, names.count)]) }
        return VStack(alignment: .leading, spacing: 5) {
            if header { self.header(.shortcuts) }
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { pad($0) }
                    // A pad alone keeps a pad's width.
                    if row.count == 1, names.count > 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                }
            }
        }
    }

    private func pad(_ name: String) -> some View {
        let running = shortcuts.running.contains(name)
        return Button {
            shortcuts.run(name)
        } label: {
            HStack(spacing: 4) {
                ThemeSymbol("play.fill").imageScale(.small)
                Text(name).lineLimit(1)
            }
            .themeFont(.body, size: 11, weight: .semibold)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 22)
            .modifier(CardChip(strength: 0.1, shape: controlShape))
            .contentShape(controlShape)
            .opacity(running ? 0.5 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(running)
        .help("Run \(name)")
        .accessibilityLabel(running ? "\(name), running" : "Run \(name)")
    }
}

/// The network's speed, down and up, and what moved today. A view of its own, so the reading each
/// second redraws only this tile.
private struct NetworkGlance<Header: View>: View {
    let network: NetworkFeature
    let secondary: Color
    @ViewBuilder let header: () -> Header

    var body: some View {
        let moved = network.soFar(.day).total
        // Nothing at all means the day's total isn't loaded yet: a Mac that's on moves something.
        let today = moved > 0 ? Text("\(NetworkFeature.bytes(moved)) today") : nil
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 3) {
                header()
                speeds(14)
                today?.themeFont(.body, size: 10).foregroundStyle(secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                speeds(14)
                today?.themeFont(.body, size: 10).foregroundStyle(secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                speeds(12)
                today?.themeFont(.body, size: 9).foregroundStyle(secondary)
            }
            speeds(12)
        }
        .lineLimit(1)
    }

    private func speeds(_ size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            speed(network.rate.down, down: true, size: size)
            speed(network.rate.up, down: false, size: size - 1)
        }
    }

    private func speed(_ rate: Double, down: Bool, size: CGFloat) -> some View {
        let speed = NetworkFeature.speed(rate)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            ThemeSymbol(down ? "arrow.down" : "arrow.up")
                .themeFont(.body, size: size * 0.65, weight: .bold)
                .foregroundStyle(secondary)
            Text(speed.value).themeFont(.numbers, size: size, weight: .semibold).monospacedDigit()
            Text(speed.unit).themeFont(.body, size: 9).foregroundStyle(secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(down ? "Down" : "Up") \(speed.value) \(speed.unit)")
    }
}

/// A tile on the move in edit mode.
private struct TileDrag: Equatable {
    var tile: HomeTile
    var offset: CGSize
    /// The tile under the pointer, whose place it would take.
    var target: HomeTile?
}

/// The rock of a tile waiting to be moved, each at its own pace so they don't move in step, and still
/// while one is dragged. Outside edit mode (and with Reduce Motion) it isn't there, so nothing animates.
private struct Wiggle: ViewModifier {
    let active: Bool
    let still: Bool
    let pace: Int

    func body(content: Content) -> some View {
        if active {
            let beat = 0.13 + 0.011 * Double(pace % 5)
            content.phaseAnimator([-1.0, 1.0]) { view, side in
                view.rotationEffect(.degrees(still ? 0 : side * 0.7))
            } animation: { _ in
                .easeInOut(duration: beat)
            }
        } else {
            content
        }
    }
}

/// Runs a tile's tab in full while Home is on screen, as `FeatureID.onHome` does for the first cards:
/// Notes loads, Shortcuts lists, and Network reads every second with today's total. The notch puts
/// every tab but the open one in the background whenever it changes, and this lifts the tile's tab
/// again; never from stopped (its tab is off, or the notch is away), and not once Home has left.
// ponytail: two hands on one phase. Listing these in `FeatureID.onHome` would run them whenever Home is
// open, tile or not; an activation policy in NotchCore that asks Home for its tiles is the upgrade path.
private struct RunsOnHome: ViewModifier {
    let feature: (any NotchFeature)?
    let home: HomeFeature

    func body(content: Content) -> some View {
        content.onChange(of: [home.phase, feature?.phase], initial: true) {
            guard let feature, home.phase == .foreground, feature.phase == .background else { return }
            feature.phase = .foreground
        }
    }
}

/// The pages' bounds and a little more: 8 pt each side for a light card's shadow, 10 above for the
/// edit badges.
private struct Margin: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - 8, y: rect.minY - 10, width: rect.width + 16, height: rect.height + 18))
    }
}

/// A button's backing on a card: the theme's platter, or on a theme's card colors the card's ink
/// faintly, as the theme's own ink is for its sheet.
private struct CardChip<S: Shape>: ViewModifier {
    let strength: Double
    let shape: S
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        if let cards = theme.cards {
            content.background(cards.ink.color.opacity(strength), in: shape)
        } else {
            content.themePlatter(strength, in: shape)
        }
    }
}
