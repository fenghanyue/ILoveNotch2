// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    /// What a phone is offering to send, set around the shelf by Quick Share: the tray shows it as a
    /// wide tile at the head of its grid.
    @Entry public var shelfIncoming: AnyView? = nil
}

/// The shelf tab, a tray. Empty, the whole tab is one drop zone. With files, a grid of their Quick
/// Look thumbnails: a click picks one, ⌘-click adds to the pick, a double click previews it, and any
/// tile drags back out. Space previews the pick, ⌘C copies it, ⌫ takes it off the shelf. The bar
/// under the grid AirDrops, sends, copies, or clears the pick, or every file when nothing is picked.
struct ShelfView: View {
    let shelf: ShelfFeature

    @Environment(\.shelfIncoming) private var incoming
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    /// A row of tiles, and in the smallest notch, where tiles drop their kind and size.
    static let row: CGFloat = 100
    static let compactRow: CGFloat = 58
    private static let spacing: CGFloat = 8
    /// Room for the offer's code and both its buttons side by side, in the widest theme face.
    private static let offerWidth: CGFloat = 220
    /// Around the grid, so a picked tile's ring and glow aren't cut off.
    private static let inset: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            if shelf.items.isEmpty, incoming == nil {
                DropZone(shelf: shelf)
            } else {
                tray(width: proxy.size.width, compact: proxy.size.height < 150)
            }
        }
    }

    private func tray(width: CGFloat, compact: Bool) -> some View {
        let column: CGFloat = compact ? 72 : 92
        let row = compact ? Self.compactRow : Self.row
        // The smallest notch gives the offer a whole row.
        let span = compact ? Int.max : offerSpan(width - Self.inset * 2, column)
        return VStack(spacing: compact ? 6 : 8) {
            ScrollView(.vertical) {
                BentoLayout(spacing: Self.spacing, minimumColumn: column) {
                    if let incoming {
                        incoming
                            .frame(height: row)
                            .layoutValue(key: BentoSpan.self, value: span)
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                    ForEach(shelf.items.reversed()) { item in
                        ShelfTile(shelf: shelf, item: item, compact: compact)
                            .frame(height: row)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                    }
                    DropTile(shelf: shelf, compact: compact).frame(height: row)
                }
                .padding(Self.inset)
                // A click between the tiles drops the pick.
                .background { Color.clear.contentShape(Rectangle()).onTapGesture { shelf.selection = [] } }
            }
            .scrollIndicators(.never)
            // In the smallest notch a row just fits, so only the inset fades.
            .fadingEdges(.vertical, length: compact ? Self.inset : Self.inset * 2)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: shelf.items.map(\.id))
            ActionBar(shelf: shelf)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        // A pick takes the keyboard, for Space, ⌘C, and ⌫, as a text field in the notch does.
        .takesKeyboard(!shelf.selection.isEmpty)
        .onChange(of: shelf.selection.isEmpty) { _, none in if !none { focused = true } }
        .onKeyPress(.space) {
            guard !shelf.selection.isEmpty else { return .ignored }
            shelf.quickLook(shelf.selected)
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard !shelf.selection.isEmpty else { return .ignored }
            shelf.remove(shelf.selected)
            return .handled
        }
        .onCopyCommand(perform: copyCommand)
        .onPasteCommand(of: [.fileURL]) { _ in shelf.paste() }
    }

    /// ⌘C while files are picked: their file URLs, which Finder pastes as the files.
    private var copyCommand: (() -> [NSItemProvider])? {
        guard !shelf.selection.isEmpty else { return nil }
        return { shelf.selected.compactMap(shelf.url(for:)).map { NSItemProvider(object: $0 as NSURL) } }
    }

    /// The columns the offer spans to be `offerWidth` wide, in `BentoLayout`'s columns across `width`.
    private func offerSpan(_ width: CGFloat, _ column: CGFloat) -> Int {
        let columns = max(1, Int((width + Self.spacing) / (column + Self.spacing)))
        let each = (width - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return Int(((Self.offerWidth + Self.spacing) / (each + Self.spacing)).rounded(.up))
    }
}

/// A file in the tray: its thumbnail, its name, and its kind and size, or Missing over hatching
/// when the file is gone. A picked tile shows in the theme's selection style: ringed and ticked,
/// underlined, or filled with the accent.
private struct ShelfTile: View {
    let shelf: ShelfFeature
    let item: ShelfItem
    let compact: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        let url = shelf.url(for: item)
        let selected = shelf.selection.contains(item.id)
        let style = theme.controls?.selection ?? .pill
        let onAccent = selected && theme.selectsOnAccent
        let name: ThemeStyle = onAccent ? .themeOnAccent : selected && style == .underline ? .themeAccent : .themeInk
        let values = url.flatMap { try? $0.resourceValues(forKeys: Self.keys) }
        VStack(alignment: .leading, spacing: 1) {
            thumbnail(url, values)
                .overlay(alignment: .topTrailing) {
                    if selected, style == .pill || style == .dot { tick }
                }
                .padding(.bottom, 3)
            // One line, middle-truncated, so the extension stays readable.
            Text(item.name)
                .themeFont(.display, size: 12, weight: .semibold)
                .foregroundStyle(name)
                .lineLimit(1)
                .truncationMode(.middle)
            if !compact {
                Text(url.map { Self.kindAndSize($0, values) } ?? "Missing")
                    .themeFont(.body, size: 10)
                    .foregroundStyle(
                        url == nil
                            ? AnyShapeStyle(Color.orange)  // a warning
                            : AnyShapeStyle(onAccent ? ThemeStyle.themeOnAccent.opacity(0.8) : .themeSecondary)
                    )
                    .lineLimit(1)
            }
        }
        .padding(compact ? 4 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if selected { mark(style) }
        }
        .contentShape(Rectangle())
        .onDrag { url.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
        .gesture(TapGesture(count: 2).onEnded { shelf.quickLook([item]) })
        .simultaneousGesture(TapGesture().onEnded(pick))
        .contextMenu {
            Button("Quick Look") { shelf.quickLook([item]) }.disabled(url == nil)
            Button("Show in Finder") { shelf.reveal(item) }.disabled(url == nil)
            Button("Copy") { shelf.copy([item]) }.disabled(url == nil)
            Button("AirDrop") { shelf.airDrop([item]) }.disabled(url == nil)
            if let send = shelf.sendToAndroid {
                Button("Quick Share\u{2026}") { url.map { send([$0]) } }.disabled(url == nil)
            }
            Divider()
            Button("Remove from Shelf") { shelf.remove([item]) }
        }
        .help(item.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(url == nil ? "\(item.name), missing" : item.name)
        .accessibilityValue(url.map { Self.kindAndSize($0, values) } ?? "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { shelf.select(item, adding: true) }
        .accessibilityAction(named: "Quick Look") { shelf.quickLook([item]) }
        .accessibilityAction(named: "Remove from Shelf") { shelf.remove([item]) }
    }

    private static let keys: Set<URLResourceKey> = [
        .fileSizeKey, .isDirectoryKey, .contentModificationDateKey, .contentTypeKey,
    ]

    /// A click picks just this file; ⌘-click adds it to the pick, or takes it out.
    private func pick() {
        shelf.select(item, adding: NSEvent.modifierFlags.contains(.command))
    }

    /// The thumbnail in the theme's frame: rounded, or printed with an edge and an offset backing on a
    /// light sheet, or in the Terminal theme's phosphor with scan lines. A missing file is hatched.
    private func thumbnail(_ url: URL?, _ values: URLResourceValues?) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius.map { $0 / 4 } ?? 10, style: .continuous)
        let outlined = theme.controls?.style == .outline
        let hard = theme.controls?.shadow == .hard
        return ZStack {
            if let url {
                // Keyed by the file's last change too, so an edited file gets a new thumbnail.
                let key = "\(url.path)|\(values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)"
                let picture = values?.contentType.map { $0.conforms(to: .image) || $0.conforms(to: .movie) } ?? false
                if theme.skin(.musicPlayer) == "terminal" {
                    Thumbnail(url: url, key: key, fills: picture)
                        .saturation(0)
                        .colorMultiply(theme.color(.accent))
                        .overlay {
                            Stripes(slanted: false, spacing: 3, width: 1).fill(theme.surface.color.color.opacity(0.5))
                        }
                } else {
                    Thumbnail(url: url, key: key, fills: picture)
                }
            } else {
                Stripes(slanted: true, spacing: 7, width: 3).fill(Color.orange.opacity(0.2))  // a warning
                ThemeSymbol("questionmark").themeFont(.body, size: 18, weight: .semibold).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 32 : 54)
        // Behind an icon, a page, or an image with clear parts; on the sheet's color, over the backing.
        .background(.themeInk.opacity(0.06))
        .background(theme.surface.color.color)
        .clipShape(shape)
        .overlay {
            if url == nil {
                shape.strokeBorder(Color.orange.opacity(0.6), lineWidth: 1.5)
            } else if outlined {
                shape.strokeBorder(
                    theme.controls?.lineColor?.color ?? theme.color(.ink).opacity(0.4),
                    lineWidth: theme.controls?.line ?? 1)
            }
        }
        .background {
            // A print's offset backing, as the player's cover has: a shape, so it's never on the wrong side.
            if outlined, hard || theme.appearance == .light {
                shape.fill(theme.color(.ink).opacity(hard ? 1 : 0.1)).offset(x: 3, y: 3)
            }
        }
    }

    /// Ticked, on a ringed tile.
    private var tick: some View {
        ThemeSymbol("checkmark")
            .themeFont(.body, size: 8, weight: .bold)
            .foregroundStyle(.themeOnAccent)
            .frame(width: 16, height: 16)
            .background(.themeAccent, in: Circle())
            .padding(4)
            .accessibilityHidden(true)
    }

    /// Behind a picked tile, in the theme's selection style.
    @ViewBuilder private func mark(_ style: Theme.Controls.Selection) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius ?? 14, style: .continuous)
        switch style {
        case .accent, .block:
            shape.fill(.themeAccent)
        case .underline:
            Rectangle().fill(.themeAccent).frame(height: 2).frame(maxHeight: .infinity, alignment: .bottom)
        case .pill, .dot:
            shape.fill(.themeAccent.opacity(0.14))
                .overlay { shape.strokeBorder(.themeAccent.opacity(0.8), lineWidth: 1.5) }
                .shadow(color: theme.color(.accent).opacity(0.3), radius: 10)
        }
    }

    /// "PNG · 2.4 MB": the extension, or Folder, and a file's size.
    static func kindAndSize(_ url: URL, _ values: URLResourceValues?) -> String {
        let kind =
            url.pathExtension.isEmpty
            ? (values?.isDirectory == true ? "Folder" : "File") : url.pathExtension.uppercased()
        guard let size = values?.fileSize else { return kind }
        return "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
    }
}

/// A file's Quick Look thumbnail: a picture or movie `fills` its frame, a page sits whole in it. Its
/// icon shows until the thumbnail comes, and for kinds without one.
private struct Thumbnail: View {
    let url: URL
    /// Names the file as it is now; a new key makes a new thumbnail.
    let key: String
    let fills: Bool

    @State private var loaded: NSImage?
    @Environment(\.displayScale) private var scale

    // ponytail: thumbnails live until memory pressure evicts them (NSCache), so reopening the notch
    // never flashes icons; the shelf holds at most 100 files.
    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image = loaded ?? Self.cache.object(forKey: key as NSString) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: fills ? .fill : .fit)
                    .padding(fills ? 0 : 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: key) {
            guard Self.cache.object(forKey: key as NSString) == nil else { return }
            // Square, so each file keeps its own shape: a photo comes back wide, a page tall.
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 160, height: 160), scale: scale, representationTypes: .thumbnail)
            guard let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            else { return }
            Self.cache.setObject(thumbnail.nsImage, forKey: key as NSString)
            loaded = thumbnail.nsImage
        }
    }
}

/// The grid's last tile: drop more files on the notch, or click to paste ones copied in Finder.
private struct DropTile: View {
    let shelf: ShelfFeature
    let compact: Bool

    var body: some View {
        Button(action: shelf.pasteOrBeep) {
            VStack(spacing: 4) {
                ThemeSymbol("plus").themeFont(.body, size: 16, weight: .medium)
                Text("Drop to add").themeFont(.body, size: 11, weight: .semibold)
                if !compact { Text("or click to paste").themeFont(.body, size: 10) }
            }
            .foregroundStyle(.themeSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { DashedWell() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to paste files you copied in Finder")
        .accessibilityLabel("Paste files")
    }
}

/// The empty shelf: the whole tab is one place to drop files, or click to paste them.
private struct DropZone: View {
    let shelf: ShelfFeature

    var body: some View {
        // The smallest notch drops the symbol and says less, so nothing clips.
        ViewThatFits(in: .vertical) {
            content(full: true)
            content(full: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { DashedWell() }
        .contentShape(Rectangle())
        .onTapGesture(perform: shelf.pasteOrBeep)
        .help("Click to paste files you copied in Finder")
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Paste Files", shelf.pasteOrBeep)
    }

    private func content(full: Bool) -> some View {
        let hint = "Keep them handy, then drag them back out, or click to paste ones you copied."
        return VStack(spacing: 6) {
            if full {
                ThemeSymbol("tray.and.arrow.down").themeFont(.body, size: 22, weight: .semibold)
                    .foregroundStyle(.themeSecondary)
            }
            Text("Drop files here").themeFont(.display, size: 15, weight: .semibold)
            Text(full ? hint : "or click to paste")
                .themeFont(.body, size: 11)
                .foregroundStyle(.themeSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let control = shelf.androidControl { ReceiveChip(control: control).padding(.top, 2) }
        }
        .padding(12)
    }
}

/// Where files can land: a dashed outline in the theme's corners.
private struct DashedWell: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius ?? 14, style: .continuous)
        let outlined = theme.controls?.style == .outline
        let dashes = StrokeStyle(lineWidth: outlined ? 1 : 1.5, dash: [5, 4])
        shape.fill(.themeInk.opacity(outlined ? 0 : 0.04))
            .overlay { shape.strokeBorder(.themeInk.opacity(outlined ? 0.5 : 0.3), style: dashes) }
    }
}

/// Under the grid: how many files there are or are picked, receiving from Android, then AirDrop, Quick
/// Share, Copy, and Clear for the pick, or for every file. A narrower notch drops the count, then the
/// words on all but AirDrop.
private struct ActionBar: View {
    let shelf: ShelfFeature

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(count: true, words: true)
            bar(count: false, words: true)
            bar(count: true, words: false)
            bar(count: false, words: false)
        }
        .themeFont(.body, size: 11, weight: .semibold)
        .buttonStyle(.plain)
        .lineLimit(1)
        .frame(height: 28)
    }

    private func bar(count: Bool, words: Bool) -> some View {
        let targets = shelf.targets
        let urls = targets.compactMap(shelf.url(for:))
        let picked = shelf.selection.count
        let what = picked == 0 ? "every file" : picked == 1 ? "the selected file" : "the selected files"
        let total = shelf.items.count
        return HStack(spacing: 6) {
            if count, total > 0 {
                Text(picked == 0 ? (total == 1 ? "1 item" : "\(total) items") : "\(picked) of \(total) selected")
                    .themeFont(.body, size: 11, weight: .medium)
                    .foregroundStyle(.themeSecondary)
            }
            if let control = shelf.androidControl { ReceiveChip(control: control) }
            Spacer(minLength: 0)
            if total > 0 {
                BarButton("AirDrop", symbol: "airdrop", style: .prominent, help: "AirDrop \(what)") {
                    shelf.airDrop(targets)
                }
                .disabled(urls.isEmpty)
                if let send = shelf.sendToAndroid {
                    BarButton(
                        "Quick Share", symbol: "smartphone", words: words,
                        help: "Send \(what) to an Android phone with Quick Share"
                    ) { send(urls) }
                    .disabled(urls.isEmpty)
                }
                BarButton("Copy", symbol: "doc.on.clipboard", words: words, help: "Copy \(what), to paste in Finder") {
                    shelf.copy(targets)
                }
                .disabled(urls.isEmpty)
                BarButton(
                    "Clear", symbol: words ? nil : "xmark", words: words, style: .secondary,
                    help: picked == 0 ? "Take every file off the shelf" : "Take \(what) off the shelf"
                ) { shelf.remove(targets) }
            }
        }
    }
}

/// A chip in the bar: its icon and words, or only its icon. A prominent one is filled with the accent.
private struct BarButton: View {
    enum Style {
        case prominent, primary, secondary
    }

    let title: String
    let symbol: String?
    let words: Bool
    let style: Style
    let help: String
    let action: () -> Void

    @Environment(\.theme) private var theme

    init(
        _ title: String, symbol: String?, words: Bool = true, style: Style = .primary, help: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.words = words || symbol == nil
        self.style = style
        self.help = help
        self.action = action
    }

    var body: some View {
        let shape =
            theme.controls?.radius.map { AnyShape(RoundedRectangle(cornerRadius: $0, style: .continuous)) }
            ?? AnyShape(Capsule())
        let ink: ThemeStyle =
            switch style {
            case .prominent: .themeOnAccent
            case .primary: .themeInk
            case .secondary: .themeSecondary
            }
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { ThemeSymbol(symbol) }
                if words { Text(title) }
            }
            .padding(.horizontal, words ? 11 : 8)
            .frame(height: 26)
            .foregroundStyle(ink)
            .background {
                if style == .prominent { shape.fill(.themeAccent) }
            }
            .themePlatter(style == .prominent ? 0 : 0.1, in: Capsule())
            .contentShape(shape)
        }
        .help(help)
        .accessibilityLabel(title)
    }
}

/// Receiving from Android, Quick Share's control, as a chip.
private struct ReceiveChip: View {
    let control: AnyView

    var body: some View {
        control
            .themeFont(.body, size: 11, weight: .semibold)
            .foregroundStyle(.themeSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .themePlatter(0.1, in: Capsule())
    }
}

/// Even stripes across a rect: slanted for a missing file's hatching, or level for scan lines.
private struct Stripes: Shape {
    var slanted: Bool
    var spacing: CGFloat
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            if slanted {
                for x in stride(from: rect.minX - rect.height, to: rect.maxX, by: spacing) {
                    path.addLines([
                        CGPoint(x: x, y: rect.maxY), CGPoint(x: x + width, y: rect.maxY),
                        CGPoint(x: x + width + rect.height, y: rect.minY), CGPoint(x: x + rect.height, y: rect.minY),
                    ])
                    path.closeSubpath()
                }
            } else {
                for y in stride(from: rect.minY, to: rect.maxY, by: spacing) {
                    path.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: width))
                }
            }
        }
    }
}

extension ShelfFeature {
    /// Pastes files from the clipboard, or beeps, as macOS does when there's nothing to paste.
    fileprivate func pasteOrBeep() {
        if !paste() { NSSound.beep() }
    }
}
