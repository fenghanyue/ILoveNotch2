// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI

/// The notes tab: the list on the left (each note's color, title, when it was edited, and first
/// line; pinned notes on top) and the open note filling the right as a page (`NotePage`). Hovering
/// a note shows its pin and delete buttons; the selection slides between notes. ↑↓ move through the
/// list, ⏎ opens the note on the page, and Escape there goes back to the list; ⌘N starts a note,
/// ⌘F unfolds search from its icon, and ⌘L turns the caret's line into a checkbox. Clicking into a
/// field or the page gives the notch keyboard focus; Escape from the list or clicking elsewhere
/// hands it back.
struct NotesView: View {
    @Bindable var notes: NotesFeature
    @Namespace private var selectionSpace
    @Namespace private var searchSpace
    @FocusState private var editorFocused: Bool
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    /// Search was opened from its icon; it also stays open while it has text.
    @State private var searching = false
    @State private var searchHovering = false
    /// The page asked for the keyboard (a click, ⏎, or ⌘N), until the editor lets it go.
    @State private var editing = false
    /// Where the caret goes once the editor has the keyboard: the end of this line, or of the note
    /// past the last line.
    @State private var caretLine: Int?
    @State private var panel = WindowLink()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    var body: some View {
        if notes.notes.isEmpty {
            FeatureUnavailableView(
                symbol: "note.text",
                title: "No notes yet",
                message: notes.usesCustomFolder
                    ? "Jot something down. Notes are saved as Markdown in \(notes.directory.lastPathComponent)."
                    : "Jot something down. Notes stay on this Mac as plain text.",
                action: (label: "New Note", perform: newNote))
        } else {
            HStack(spacing: 10) {
                list.frame(width: 142)
                if let note = notes.selected {
                    NotePage(notes: notes, note: note, editorFocused: $editorFocused, edit: edit)
                }
            }
            .takesKeyboard(editing)
            .background { shortcuts }
            .background { EscapeCatcher(link: panel, onEscape: backToList) }
            .onAppear(perform: takeFocusIfWanted)
            .onChange(of: notes.wantsEditorFocus) { _, _ in takeFocusIfWanted() }
            .onChange(of: editorFocused) { _, focused in
                editing = focused
                guard focused, let line = caretLine else { return }
                caretLine = nil
                Task { @MainActor in placeCaret(atEndOf: line) }
            }
        }
    }

    /// Puts the cursor in the editor after the quick note shortcut, once the editor is on screen.
    private func takeFocusIfWanted() {
        guard notes.wantsEditorFocus else { return }
        Task { @MainActor in
            editorFocused = true
            notes.editorTookFocus()
        }
    }

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82) }
    private var slide: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    // MARK: Keyboard

    /// Opens the page's editor with the caret at the end of `line`, or of the note.
    private func edit(_ line: Int?) {
        caretLine = line ?? .max
        editing = true
        Task { @MainActor in editorFocused = true }
    }

    private func newNote() {
        withAnimation(spring) { _ = notes.add() }
        edit(nil)
    }

    /// Escape in the editor: back to the list, keeping the keyboard.
    private func backToList() -> Bool {
        guard editorFocused else { return false }
        editorFocused = false
        listFocused = true
        return true
    }

    private func step(_ by: Int) -> KeyPress.Result {
        let ids = notes.visibleNotes.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let next = notes.selection.flatMap { ids.firstIndex(of: $0) }.map { min(max($0 + by, 0), ids.count - 1) } ?? 0
        withAnimation(slide) { notes.selection = ids[next] }
        return .handled
    }

    private func select(_ id: Note.ID) {
        withAnimation(slide) { notes.selection = id }
        listFocused = true
    }

    /// ⌘L: the lines the caret or selection is on become checklist items, or plain text again,
    /// through the editor so Undo takes it back.
    private func toggleChecklist() {
        guard editorFocused, let view = noteTextView else { return }
        let string = view.string as NSString
        var start = 0
        var end = 0
        var contentsEnd = 0
        string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: view.selectedRange())
        let range = NSRange(location: start, length: contentsEnd - start)
        let lines = Note.lines(of: string.substring(with: range)).map { MarkdownLine.togglingChecklist(String($0)) }
        view.insertText(lines.joined(separator: "\n"), replacementRange: range)
    }

    private func placeCaret(atEndOf line: Int) {
        guard let view = noteTextView else { return }
        let string = view.string
        let lines = Note.lines(of: string)
        let end = lines.indices.contains(line) ? lines[line].endIndex : string.endIndex
        let caret = NSRange(location: end.utf16Offset(in: string), length: 0)
        view.setSelectedRange(caret)
        view.scrollRangeToVisible(caret)
    }

    /// The text view behind the page's editor, while it has the keyboard.
    private var noteTextView: NSTextView? {
        guard let view = panel.window?.firstResponder as? NSTextView, !view.isFieldEditor else { return nil }
        return view
    }

    /// ⌘N, ⌘F, and ⌘L, wherever the keyboard is in the tab.
    private var shortcuts: some View {
        ZStack {
            Button("New Note", action: newNote).keyboardShortcut("n", modifiers: .command)
            Button("Search Notes") {
                if searching { searchFocused = true } else { openSearch() }
            }
            .keyboardShortcut("f", modifiers: .command)
            Button("Checkbox", action: toggleChecklist).keyboardShortcut("l", modifiers: .command)
        }
        .buttonStyle(.plain)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(notes.visibleNotes) { note in
                            NoteRow(
                                notes: notes, note: note, isSelected: notes.selection == note.id,
                                selectionSpace: selectionSpace, select: { select(note.id) }
                            )
                            .id(note.id)
                        }
                        if notes.visibleNotes.isEmpty {
                            Text("No matches").themeFont(.body, .caption).foregroundStyle(.themeInk.opacity(0.5))
                                .padding(6)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .fadingEdges()
                .onChange(of: notes.selection) { _, id in
                    if let id { withAnimation(slide) { proxy.scrollTo(id) } }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(.upArrow) { step(-1) }
            .onKeyPress(.downArrow) { step(1) }
            .onKeyPress(.return) {
                guard notes.selected != nil else { return .ignored }
                caretLine = .max
                editorFocused = true
                return .handled
            }
        }
    }

    /// Where the notes are kept, then search, sort, and new note as three icons of one size. Search
    /// opens out of its icon into a field across the header, and folds back when closed or left
    /// empty.
    private var header: some View {
        let open = searching || !notes.search.isEmpty
        return HStack(spacing: 4) {
            if open {
                HStack(spacing: 4) {
                    searchGlass
                    TextField("Search", text: $notes.search, prompt: theme.prompt("Search", .caption))
                        .textFieldStyle(.plain)
                        .themeFont(.body, .caption)
                        .focused($searchFocused)
                        .takesKeyboard(searching)
                    Button(action: closeSearch) {
                        ThemeSymbol("xmark.circle.fill").themeFont(.body, size: 10).opacity(0.5)
                    }
                    .buttonStyle(.plain)
                    .help("Close search")
                    .accessibilityLabel("Close Search")
                }
                .padding(.leading, 6)
                .padding(.trailing, 5)
                .frame(height: HeaderIcon.side)
                .background { searchField }
                .transition(.opacity)
            } else {
                folder
                Spacer(minLength: 0)
                Button(action: openSearch) {
                    searchGlass
                        .frame(width: HeaderIcon.side, height: HeaderIcon.side)
                        .background { searchField }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { searchHovering = inside } }
                .help("Search notes (⌘F)")
                .accessibilityLabel("Search")
                Menu {
                    Picker("Sort By", selection: $notes.sort) {
                        ForEach(NoteSort.allCases) { sort in Text(sort.name).tag(sort) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HeaderIcon(symbol: "arrow.up.arrow.down")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort notes")
                .accessibilityLabel("Sort")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                Button(action: newNote) {
                    HeaderIcon(symbol: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("New note (⌘N)")
                .accessibilityLabel("New Note")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .frame(height: HeaderIcon.side)
        .onChange(of: searchFocused) { _, focused in
            // Clicking away from an empty search folds it back into its icon.
            if !focused, notes.search.isEmpty { withAnimation(spring) { searching = false } }
        }
    }

    /// Where the notes are kept: iCloud Drive, a folder the user chose, or this Mac. Just its icon
    /// when the name doesn't fit.
    private var folder: some View {
        let path = notes.directory.path
        let inCloud = path.contains("/Mobile Documents/")
        let chosen = notes.usesCustomFolder ? FileManager.default.displayName(atPath: path) : "This Mac"
        let name = inCloud ? "iCloud Drive" : chosen
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ThemeSymbol(inCloud ? "icloud" : "folder.fill")
                Text(name).lineLimit(1)
            }
            ThemeSymbol(inCloud ? "icloud" : "folder.fill")
        }
        .themeFont(.body, size: 10)
        .foregroundStyle(.themeInk.opacity(0.6))
        .layoutPriority(1)  // ahead of the spacer, which only takes what's left
        .help("Notes are saved as Markdown files in \(name)")
    }

    /// The icon and the field's backdrop are shared, so the icon's circle stretches into the field.
    private var searchGlass: some View {
        ThemeSymbol("magnifyingglass")
            .themeFont(.body, size: HeaderIcon.symbolSize, weight: .semibold)
            .foregroundStyle(.themeInk.opacity(0.8))
            .matchedGeometryEffect(id: "glass", in: searchSpace)
    }

    private var searchField: some View {
        Color.clear
            .themePlatter(searchHovering && !searching ? 0.18 : 0.1, in: Capsule())
            .matchedGeometryEffect(id: "field", in: searchSpace)
    }

    private func openSearch() {
        searchHovering = false
        withAnimation(spring) { searching = true }
        Task { @MainActor in searchFocused = true }
    }

    private func closeSearch() {
        withAnimation(spring) {
            notes.search = ""
            searching = false
        }
        searchFocused = false
    }
}

extension NoteColor {
    /// The note's own color, the same in every theme.
    var swatch: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

/// One note in the list: its color, title, and pin, then when it was edited and its first line. The
/// selection shows in the theme's style, sliding between rows: behind the row, or under the title
/// for a line or a dot. Hovering shows a lighter highlight, a preview tooltip, and pin and delete
/// buttons.
private struct NoteRow: View {
    let notes: NotesFeature
    let note: Note
    let isSelected: Bool
    let selectionSpace: Namespace.ID
    let select: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let underTitle = theme.controls?.selection == .underline || theme.controls?.selection == .dot
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                NoteDot(color: note.color, size: 7)
                Text(note.title)
                    .themeFont(.display, size: 12, weight: .semibold)
                    .lineLimit(1)
                    .background {
                        if isSelected, underTitle { mark(Capsule()) }
                    }
                Spacer(minLength: 0)
                accessory
            }
            Text(note.excerpt.isEmpty ? Self.when(note.modified) : "\(Self.when(note.modified)) · \(note.excerpt)")
                .themeFont(.body, size: 10)
                .opacity(0.65)
                .lineLimit(1)
                .padding(.leading, 13)
        }
        .themeSelectionInk(isSelected && !underTitle, unlit: 1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            if isSelected, !underTitle {
                mark(shape)
            } else if hovering, !isSelected {
                Color.clear.themePlatter(0.07, in: shape)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovering = inside }
        }
        .help(tooltip)
        .onDrag {
            notes.fileURL(for: note.id).flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
        }
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin to Top") { notes.togglePin(note.id) }
            Picker("Color", selection: Binding(get: { note.color }, set: { notes.setColor(note.id, $0) })) {
                Text("None").tag(NoteColor?.none)
                ForEach(NoteColor.allCases) { color in Text(color.name).tag(NoteColor?.some(color)) }
            }
            .pickerStyle(.menu)
            if note.hasOpenChecklist {
                Button("Send Unticked Items to Tasks") { _ = notes.sendToTasks(note.id) }
            }
            Button("Show in Finder") {
                if let url = notes.fileURL(for: note.id) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
            Button("Move to Trash", role: .destructive) { notes.delete(note.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: note.isPinned ? "Unpin" : "Pin") { notes.togglePin(note.id) }
        .accessibilityAction(named: "Move to Trash") { notes.delete(note.id) }
    }

    /// The selection, which slides from row to row.
    private func mark(_ shape: some Shape) -> some View {
        SelectionMark(in: shape, strength: 0.12).matchedGeometryEffect(id: "selection", in: selectionSpace)
    }

    /// Pin and delete under the pointer, else a pin on a pinned note.
    @ViewBuilder private var accessory: some View {
        if hovering {
            HStack(spacing: 5) {
                Button {
                    notes.togglePin(note.id)
                } label: {
                    ThemeSymbol(note.isPinned ? "pin.slash" : "pin")
                }
                .accessibilityLabel(note.isPinned ? "Unpin" : "Pin")
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { notes.delete(note.id) }
                } label: {
                    ThemeSymbol("trash")
                }
                .accessibilityLabel("Move to Trash")
            }
            .buttonStyle(.plain)
            .themeFont(.body, size: 9, weight: .semibold)
            .foregroundStyle(.themeInk.opacity(0.7))
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else if note.isPinned {
            ThemeSymbol("pin.fill").themeFont(.body, size: 8).opacity(0.6)
        }
    }

    /// "now", a time today, a weekday this week, or a date.
    static func when(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        if abs(now.timeIntervalSince(date)) < 60 { return "now" }
        if days == 0 { return date.formatted(date: .omitted, time: .shortened) }
        if (1..<7).contains(days) { return date.formatted(.dateTime.weekday(.abbreviated)) }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var tooltip: String {
        let edited = "Edited " + note.modified.formatted(date: .abbreviated, time: .shortened)
        return note.preview.isEmpty ? "\(note.title)\n\(edited)" : "\(note.title)\n\(note.preview)\n\(edited)"
    }
}

/// An icon in the list's header, on a circle that brightens under the pointer.
private struct HeaderIcon: View {
    static let side: CGFloat = 22
    static let symbolSize: CGFloat = 10.5

    let symbol: String
    @State private var hovering = false

    var body: some View {
        ThemeSymbol(symbol)
            .themeFont(.body, size: Self.symbolSize, weight: .semibold)
            .foregroundStyle(.themeInk.opacity(hovering ? 1 : 0.8))
            .frame(width: Self.side, height: Self.side)
            .themePlatter(hovering ? 0.18 : 0.1, in: Circle())
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// The window the notes are drawn in, for the text view behind the page's TextEditor.
@MainActor private final class WindowLink {
    weak var window: NSWindow?
}

/// Escape while the page's editor has the keyboard goes back to the list rather than closing the
/// notch: a local monitor sees keys addressed to this app before the notch's panel turns Escape
/// into closing. It's installed only while the notes are on screen, and leaves an input method's
/// composition, and every other key, alone. It also keeps `link` pointing at its window.
private struct EscapeCatcher: NSViewRepresentable {
    let link: WindowLink
    /// Returns whether it took the Escape.
    let onEscape: () -> Bool

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.link = link
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onEscape = onEscape }

    final class CatcherView: NSView {
        var onEscape: (() -> Bool)?
        var link: WindowLink?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            link?.window = window
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let taken = MainActor.assumeIsolated { self?.take(event) ?? false }
                return taken ? nil : event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func take(_ event: NSEvent) -> Bool {
            guard event.keyCode == 53, event.window === window, let editor = window?.firstResponder as? NSTextView,
                !editor.isFieldEditor, !editor.hasMarkedText()
            else { return false }
            return onEscape?() ?? false
        }
    }
}
