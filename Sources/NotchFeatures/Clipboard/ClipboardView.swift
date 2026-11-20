// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI

/// The clipboard tab: search, then click a card (or press Return for the first match) to put it
/// back on the clipboard. What you copied runs across the tab as cards of one size, each filled by
/// what it holds and colored if you gave it a color. Favorites come first and stay. Select mode ticks
/// cards to delete together, and Clear deletes all but favorites.
struct ClipboardView: View {
    let clipboard: ClipboardFeature
    @Environment(\.theme) private var theme
    @State private var query = ""
    @FocusState private var searching: Bool
    /// Clicking a row ticks it instead of copying it.
    @State private var selecting = false
    @State private var selected: Set<ClipItem.ID> = []
    /// Clear asks once more, until the pointer leaves it.
    @State private var confirmingClear = false

    var body: some View {
        if !clipboard.isRecording {
            FeatureUnavailableView(
                symbol: "doc.on.clipboard", title: "Keep what you copy",
                message: "Text, links, images, and files you copy, kept on this Mac to find and copy again. "
                    + "Passwords and anything marked private are skipped.",
                action: (label: "Turn On", perform: clipboard.startRecording))
        } else if clipboard.access == .asks || clipboard.access == .denied {
            FeatureUnavailableView(
                symbol: "lock", title: "Let ILoveNotch read what you copy",
                message: "In System Settings › Privacy & Security › Paste from Other Apps, set ILoveNotch to "
                    + "Always Allow. Until then macOS would ask each time.",
                action: (
                    label: "Open Privacy Settings",
                    perform: { NSWorkspace.shared.open(.privacySettings("Privacy_Pasteboard")) }
                )
            )
            .onAppear(perform: clipboard.refreshAccess)
        } else {
            history
                .onAppear {
                    clipboard.refreshAccess()
                    takeSearch()
                }
                .onChange(of: clipboard.wantsSearch) { takeSearch() }
        }
    }

    private var history: some View {
        let found = clipboard.search(query)
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ThemeSymbol("magnifyingglass").themeFont(.body, .caption).opacity(0.6)
                TextField(
                    "Search what you copied", text: $query, prompt: theme.prompt("Search what you copied")
                )
                .textFieldStyle(.plain)
                .themeFont(.body, .body)
                .focused($searching)
                .onSubmit { if let first = found.first { clipboard.pick(first) } }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .themePlatter(0.1, in: RoundedRectangle(cornerRadius: 8))
            if found.isEmpty {
                FeatureUnavailableView(
                    symbol: "doc.on.clipboard", title: clipboard.items.isEmpty ? "Nothing copied yet" : "No matches",
                    message: clipboard.items.isEmpty ? "Copy something and it shows up here." : "Try other words.")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(found) { card($0) }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.never)
                .fadingEdges(.horizontal, length: 12)
            }
            if !clipboard.items.isEmpty { footer(found) }
        }
    }

    /// How many are ticked or kept, and at the bottom right, Select and Clear, or while selecting,
    /// Select All, Delete, and Done.
    private func footer(_ found: [ClipItem]) -> some View {
        let keptByClear = clipboard.items.count { !$0.favorite }
        let allTicked = !found.isEmpty && found.allSatisfy { selected.contains($0.id) }
        return HStack(spacing: 8) {
            Group {
                if selecting {
                    Text("\(selected.count) selected")
                } else {
                    Text("^[\(clipboard.items.count) item](inflect: true)")
                }
            }
            .themeFont(.body, .caption2)
            .monospacedDigit()
            .foregroundStyle(.themeInk.opacity(0.5))
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if selecting {
                    footerButton(allTicked ? "Select None" : "Select All") {
                        selected = allTicked ? [] : Set(found.map(\.id))
                    }
                    footerButton("Delete", tint: .red) {
                        clipboard.remove(selected)
                        selected = []
                        if clipboard.items.isEmpty { selecting = false }
                    }
                    .disabled(selected.isEmpty)
                    .opacity(selected.isEmpty ? 0.4 : 1)
                    .help("Delete the selected items, favorites too")
                    footerButton("Done") {
                        selecting = false
                        selected = []
                    }
                } else {
                    footerButton("Select") {
                        confirmingClear = false
                        selecting = true
                    }
                    .help("Select items to delete")
                    footerButton(
                        confirmingClear ? "Clear ^[\(keptByClear) item](inflect: true)?" : "Clear",
                        tint: confirmingClear ? .red : nil
                    ) {
                        if confirmingClear {
                            clipboard.clear()
                            confirmingClear = false
                        } else {
                            confirmingClear = true
                        }
                    }
                    .disabled(keptByClear == 0)
                    .opacity(keptByClear == 0 ? 0.4 : 1)
                    .onHover { if !$0 { confirmingClear = false } }
                    .help(keptByClear == 0 ? "Only favorites are left" : "Delete everything but favorites")
                }
            }
            .background(GlassPlatter(shape: Capsule()))
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)  // clear of the resize grip in the notch's corner
    }

    /// `tint` is the theme's ink unless given, like Clear's red while it asks to confirm.
    private func footerButton(_ title: LocalizedStringKey, tint: Color? = nil, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Text(title)
                .themeFont(.body, .caption, weight: .semibold)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? theme.color(.ink))
    }

    /// The search field takes the keyboard when the tab opened from its shortcut.
    private func takeSearch() {
        guard clipboard.wantsSearch else { return }
        clipboard.wantsSearch = false
        searching = true
    }

    static let cardWidth: CGFloat = 150

    /// One thing copied as a card: its kind and favorite star at the top, then what it holds filling
    /// the card (an image at the card's width with the text that fits under it, text wrapping to the
    /// card's foot), and where it came from. Cards are all one size; a color given to a card fills it.
    private func card(_ item: ClipItem) -> some View {
        let ticked = selected.contains(item.id)
        let shape = RoundedRectangle(
            cornerRadius: theme.controls?.radius.map { CGFloat($0) } ?? 12, style: .continuous)
        let tint = item.color.flatMap(ClipColor.init(rawValue:))?.color(dark: theme.appearance == .dark)
        return Button {
            if !selecting {
                clipboard.pick(item)
            } else if ticked {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                cardHeader(item, ticked: ticked)
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                Text(detail(item))
                    .themeFont(.body, .caption2)
                    .foregroundStyle(.themeInk.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(9)
            .frame(width: Self.cardWidth)
            .frame(maxHeight: .infinity)
            .background {
                if let tint { shape.fill(tint) }
            }
            .themePlatter(tint == nil ? (ticked ? 0.16 : 0.08) : 0, in: shape)
            .overlay {
                if ticked { shape.strokeBorder(theme.color(.accent), lineWidth: 2) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(selecting ? (ticked ? "Deselect" : "Select") : "Copy again")
        .contextMenu {
            Button("Copy") { clipboard.pick(item) }
            Button(item.favorite ? "Remove from Favorites" : "Add to Favorites") { clipboard.toggleFavorite(item) }
            Picker(
                "Color",
                selection: Binding(get: { item.color }, set: { clipboard.setColor($0, for: item) })
            ) {
                Text("Default").tag(Int?.none)
                ForEach(ClipColor.allCases, id: \.self) { color in
                    Label {
                        Text(color.name)
                    } icon: {
                        Image(nsImage: color.swatch(dark: theme.appearance == .dark))
                    }
                    .tag(Int?.some(color.rawValue))
                }
            }
            Divider()
            Button("Delete") { delete(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(ticked ? .isSelected : [])
        .accessibilityAction(named: "Delete") { delete(item) }
    }

    /// The card's kind and age, and its star, or while selecting, its tick.
    private func cardHeader(_ item: ClipItem, ticked: Bool) -> some View {
        HStack(spacing: 5) {
            ThemeSymbol(symbol(item)).themeFont(.body, size: 11).opacity(0.7)
            Text(kind(item)).themeFont(.body, size: 11, weight: .semibold)
            Spacer(minLength: 0)
            if selecting {
                ThemeSymbol(ticked ? "checkmark.circle.fill" : "circle")
                    .themeFont(.body, size: 13)
                    .foregroundStyle(ticked ? theme.color(.accent) : theme.color(.ink).opacity(0.4))
            } else {
                Button {
                    clipboard.toggleFavorite(item)
                } label: {
                    ThemeSymbol(item.favorite ? "star.fill" : "star")
                        .themeFont(.body, .caption)
                        .foregroundStyle(item.favorite ? .yellow : theme.color(.ink).opacity(0.4))  // a gold star
                }
                .buttonStyle(.plain)
                .help(item.favorite ? "Remove from favorites" : "Keep as a favorite")
                .accessibilityLabel(item.favorite ? "Favorite" : "Not a favorite")
            }
        }
    }

    private func delete(_ item: ClipItem) {
        clipboard.remove(item)
        selected.remove(item.id)
    }

    /// What a card holds, filling it: an image at the card's width, its whole height if it's tall; a
    /// color's swatch; a link's site over its address; files' icon and names; text wrapping down.
    @ViewBuilder private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            if let image = clipboard.thumbnail(for: item, size: Int(Self.cardWidth * 2)) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                ThemeSymbol("photo").themeFont(.body, size: 22).opacity(0.5)
            }
        case .files:
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.paths.first ?? "/")).resizable()
                    .frame(width: 34, height: 34)
                Text(item.paths.map { URL(filePath: $0).lastPathComponent }.joined(separator: "\n"))
                    .themeFont(.body, .callout)
            }
        case .link:
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(string: item.text)?.host() ?? item.text)
                    .themeFont(.body, .callout, weight: .semibold)
                    .lineLimit(2)
                Text(item.text)
                    .themeFont(.body, .caption2)
                    .foregroundStyle(.themeInk.opacity(0.6))
            }
        case .text:
            if let swatch = Self.hexColor(item.text) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(swatch).frame(height: 44)
                    Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                        .themeFont(.mono, .callout)
                }
            } else {
                Text(item.text).themeFont(.body, .callout)
            }
        }
    }

    /// A copied color such as "#FF8A4C", to show as its swatch.
    static func hexColor(_ text: String) -> Color? {
        let hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.wholeMatch(of: /#?[0-9A-Fa-f]{6}/) != nil, let value = Int(hex.trimmingPrefix("#"), radix: 16)
        else { return nil }
        return Color(
            red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    private func kind(_ item: ClipItem) -> String {
        switch item.kind {
        case .image: "Image"
        case .files: item.paths.count == 1 ? "File" : "\(item.paths.count) Files"
        case .link: "Link"
        case .text: Self.hexColor(item.text) == nil ? "Text" : "Color"
        }
    }

    private func symbol(_ item: ClipItem) -> String {
        switch item.kind {
        case .image: "photo"
        case .files: "folder.fill"
        case .link: "link"
        case .text: "text.alignleft"
        }
    }

    private func detail(_ item: ClipItem) -> String {
        let when = item.copied.formatted(.relative(presentation: .named))
        return [item.source, when].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The colors a clipboard card can take, like sticky notes: a soft tint on a light sheet, a deep
/// tone on a dark one, so the theme's ink reads on both.
enum ClipColor: Int, CaseIterable {
    case coral, peach, sand, mint, sage, fog, storm, dusk, blossom, clay

    var name: String { "\(self)".capitalized }

    func color(dark: Bool) -> Color {
        let hex = dark ? Self.deep[rawValue] : Self.soft[rawValue]
        return Color(
            red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// A dot of the color for the card's menu, drawn as it is rather than as a template.
    func swatch(dark: Bool) -> NSImage {
        let color = NSColor(color(dark: dark))
        return NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }

    private static let soft = [
        0xF8B4AC, 0xF5AB82, 0xF9F0B0, 0xDCF2CE, 0xB8DCD2, 0xD6E5EE, 0xB2CDDE, 0xD6C3DE, 0xF3DFDA, 0xE7E0D2,
    ]
    private static let deep = [
        0x7A2433, 0x6E3321, 0x7A5314, 0x2D5242, 0x175F5A, 0x2B5E73, 0x2E4559, 0x4B3561, 0x6B3C51, 0x4E473E,
    ]
}
