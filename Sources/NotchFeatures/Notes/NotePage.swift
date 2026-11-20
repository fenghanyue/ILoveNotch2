// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI

/// The open note as a page. Read, its Markdown shows as formatting: headings in the theme's display
/// face, boxes to tick, bold text, and the marks hidden, or kept dim in a monospaced theme. A click
/// puts the editor in its place, the caret at the end of the clicked line; on macOS 26 the editor
/// formats as you type too, with the marks faint on the lines being edited. Under the text: the
/// note's color, which unfolds the palette, Send to Tasks, Share, and its length. The file stays
/// plain Markdown.
struct NotePage: View {
    let notes: NotesFeature
    let note: Note
    let editorFocused: FocusState<Bool>.Binding
    /// Opens the editor with the caret at the end of a line, or of the note for nil.
    let edit: (Int?) -> Void

    @State private var showsPalette = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.theme) private var theme

    nonisolated static let bodySize: CGFloat = 12

    nonisolated static func headingSize(_ level: Int) -> CGFloat { level == 1 ? 16 : level == 2 ? 13.5 : 12.5 }

    var body: some View {
        let editing = editorFocused.wrappedValue
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                editor.opacity(editing ? 1 : 0).accessibilityHidden(!editing)
                if !editing {
                    reading.id(note.id).transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: note.id)
            .padding(.top, 8)
            .padding(.horizontal, 7)
            footer
        }
        .background { backing }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: note.color)
        .onChange(of: note.id) { showsPalette = false }
    }

    // MARK: Reading

    private var reading: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if note.isEmpty {
                    Text("Write something").themeFont(.body, size: Self.bodySize).foregroundStyle(.themeTertiary)
                } else {
                    ForEach(Array(Note.lines(of: note.text).enumerated()), id: \.offset) { index, line in
                        self.line(MarkdownLine(line), at: index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { edit(index) }
                    }
                }
            }
            .padding(.horizontal, 5)  // where the editor's text starts
            .padding(.bottom, 8)
        }
        .mask {
            // A line cut off by the footer fades out; the first line never does.
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 10)
            }
        }
        .background { Color.clear.contentShape(Rectangle()).onTapGesture { edit(nil) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note text")
        .accessibilityAction(named: "Edit") { edit(nil) }
    }

    @ViewBuilder private func line(_ line: MarkdownLine, at index: Int) -> some View {
        switch line.kind {
        case .heading(let level):
            inline(line, role: .display, size: Self.headingSize(level), weight: .semibold, prefix: theme.keepsMarks)
                .padding(.top, index == 0 ? 0 : 3)
        case .checkbox(let done):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                box(line, done: done, at: index)
                inline(line).strikethrough(done).opacity(done ? 0.55 : 1)
            }
            .padding(.leading, CGFloat(line.indent) * 6)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(theme.keepsMarks ? line.prefix.trimmingCharacters(in: .whitespaces) : "•")
                    .themeFont(.body, size: Self.bodySize)
                    .foregroundStyle(.themeTertiary)
                inline(line)
            }
            .padding(.leading, CGFloat(line.indent) * 6)
        case .text:
            inline(line)
        }
    }

    /// A line's text: bold spans in bold, and their marks (and the line's own, with `prefix`) only in a
    /// theme that keeps them.
    private func inline(
        _ line: MarkdownLine, role: Theme.Fonts.Role = .body, size: CGFloat = bodySize, weight: Font.Weight = .regular,
        prefix: Bool = false
    ) -> Text {
        let marks = theme.keepsMarks
        let parts =
            (prefix ? [.init(role: .mark, text: line.prefix)] : []) + line.parts.filter { marks || $0.role != .mark }
        var text = AttributedString()
        for part in parts {
            var piece = AttributedString(part.text)
            piece.font = theme.font(role, size: size, weight: part.role == .bold ? .bold : weight)
            if part.role == .mark { piece.foregroundColor = theme.color(.tertiary) }
            text.append(piece)
        }
        return text.characters.isEmpty ? Text(verbatim: " ").font(theme.font(role, size: size)) : Text(text)
    }

    /// A box to tick, or the item's own `- [ ]` in a theme that keeps its marks.
    private func box(_ line: MarkdownLine, done: Bool, at index: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { notes.toggleCheckbox(note.id, line: index) }
        } label: {
            if theme.keepsMarks {
                Text(line.prefix.trimmingCharacters(in: .whitespaces))
                    .themeFont(.body, size: Self.bodySize)
                    .foregroundStyle(.themeTertiary)
            } else {
                CheckBox(done: done, color: note.color)
            }
        }
        .buttonStyle(.plain)
        .help(done ? "Untick" : "Tick")
        .accessibilityLabel(line.parts.filter { $0.role != .mark }.map(\.text).joined())
        .accessibilityValue(done ? "Ticked" : "Not ticked")
    }

    // MARK: Editing

    @ViewBuilder private var editor: some View {
        Group {
            if #available(macOS 26, *) {
                MarkdownEditor(notes: notes, note: note, focus: editorFocused).id(note.id)
            } else {
                TextEditor(text: Binding(get: { note.text }, set: { notes.update(note.id, text: $0) }))
                    .focused(editorFocused)
            }
        }
        .themeFont(.body, size: Self.bodySize)
        .scrollContentBackground(.hidden)
        .accessibilityLabel("Note text")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: ColorPalette.gap) {
            Button {
                showsPalette.toggle()
            } label: {
                NoteDot(color: note.color, size: ColorPalette.dot)
                    .scaleEffect(showsPalette && !reduceMotion ? 1.2 : 1)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: showsPalette)
                    .contentShape(Circle().inset(by: -4))
            }
            .help(showsPalette ? "Close colors" : "Color")
            .accessibilityLabel(note.color.map { "Color: \($0.name)" } ?? "Color")
            // The palette opens over the other buttons, which step aside while it's out.
            ZStack(alignment: .leading) {
                HStack(spacing: 8) {
                    if note.hasOpenChecklist { sendToTasks.layoutPriority(1).transition(.opacity) }
                    ShareLink(item: note.text, subject: Text(note.title)) {
                        ThemeSymbol("square.and.arrow.up")
                    }
                    .help("Share to Notes, Mail, Messages, and more")
                    .accessibilityLabel("Share")
                    Spacer(minLength: 0)
                    status
                }
                .opacity(showsPalette ? 0 : 1)
                .allowsHitTesting(!showsPalette)
                .accessibilityHidden(showsPalette)
                // Out of the way at once; back once the swatches have folded up.
                .animation(
                    showsPalette ? .easeOut(duration: 0.1) : .easeIn(duration: 0.18).delay(0.12), value: showsPalette)
                ColorPalette(selected: note.color, open: showsPalette) { color in
                    notes.setColor(note.id, color)
                    showsPalette = false
                }
            }
        }
        .buttonStyle(.plain)
        .themeFont(.body, size: 10.5, weight: .medium)
        .foregroundStyle(.themeInk.opacity(0.7))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .overlay(alignment: .top) {
            // An outlined theme rules the footer off, dotted.
            if theme.controls?.style == .outline {
                Rule()
                    .stroke(
                        theme.controls?.lineColor?.color ?? theme.color(.ink).opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
                    .frame(height: 1)
                    .padding(.horizontal, 8)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: notes.notice)
    }

    private var sendToTasks: some View {
        let count = note.openChecklistItems.count
        return Button {
            _ = notes.sendToTasks(note.id)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    ThemeSymbol("checklist")
                    Text("Send \(count) to Tasks")
                }
                ThemeSymbol("checklist")
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .themePlatter(0.1, in: Capsule())
            .contentShape(Capsule())
        }
        .help("Send unticked items to Tasks")
        .accessibilityLabel(count == 1 ? "Send 1 unticked item to Tasks" : "Send \(count) unticked items to Tasks")
    }

    /// The note's length and when it was edited, or a notice such as "Sent 2 items to Tasks". A
    /// narrow page keeps what fits.
    @ViewBuilder private var status: some View {
        if let notice = notes.notice {
            Text(notice).foregroundStyle(.themeInk.opacity(0.85)).transition(.opacity)
        } else {
            let words = note.wordCount == 1 ? "1 word" : "\(note.wordCount) words"
            ViewThatFits(in: .horizontal) {
                Text("\(words) · Edited \(note.modified, format: .relative(presentation: .named))")
                Text("Edited \(note.modified, format: .relative(presentation: .named))")
                Text(words)
                Color.clear.frame(width: 0, height: 0)
            }
            .foregroundStyle(.themeInk.opacity(0.5))
        }
    }

    // MARK: Backing

    /// The page's sheet: the theme's platter, a print's offset backing on a light outlined theme,
    /// and the note's color, glowing at the top of a dark page or ruled across the top of a light one.
    @ViewBuilder private var backing: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(theme.controls?.radius ?? 12), style: .continuous)
        ZStack {
            if theme.appearance == .light, theme.controls?.style == .outline, theme.controls?.shadow != .hard {
                shape.fill(.themeInk.opacity(0.08)).offset(x: 3, y: 3)
                shape.fill(theme.surface.color.color)
            }
            Color.clear.themePlatter(0.06, in: shape)
            if let color = note.color?.swatch {
                if theme.appearance == .light {
                    color.frame(height: 3).frame(maxHeight: .infinity, alignment: .top).clipShape(shape)
                } else if !reduceTransparency {
                    RadialGradient(
                        colors: [color.opacity(0.22), .clear], center: UnitPoint(x: 0.25, y: 0), startRadius: 0,
                        endRadius: 170
                    )
                    .clipShape(shape)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The page's editor on macOS 26, where a TextEditor takes styled text: the note's Markdown shows
/// as it will read (headings, bold, ticked items struck through) while it's typed, with the marks
/// faint on the lines the caret or selection is on and hidden on the others; a list's marker and,
/// in a monospaced theme, every mark stay faint. The text is restyled only when the words, the
/// lines being edited, or the theme change, never while an input method is composing.
@available(macOS 26, *)
private struct MarkdownEditor: View {
    let notes: NotesFeature
    let note: Note
    let focus: FocusState<Bool>.Binding

    /// The editor starts with the note's text rather than filling in after, which Undo would empty
    /// again; each note gets its own editor (`id`), so Undo never brings back another note's text.
    @State private var text: AttributedString
    @State private var selection: AttributedTextSelection
    /// What `text` was last styled for, so the editor's own changes to it never restyle in a loop.
    @State private var styledFor: StyleKey?
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager

    private struct StyleKey: Equatable {
        let text: String
        let lines: ClosedRange<Int>
        let theme: String
    }

    init(notes: NotesFeature, note: Note, focus: FocusState<Bool>.Binding) {
        self.notes = notes
        self.note = note
        self.focus = focus
        let text = AttributedString(note.text)
        _text = State(initialValue: text)
        _selection = State(initialValue: AttributedTextSelection(insertionPoint: text.endIndex))
    }

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .focused(focus)
            .onAppear(perform: restyle)
            .onChange(of: note.text) {
                // Ticked on the page, or changed on disk: an edit Undo can take back.
                guard note.text != String(text.characters) else { return }
                text = AttributedString(note.text)
                selection = AttributedTextSelection(insertionPoint: text.endIndex)
            }
            .onChange(of: text) {
                let plain = String(text.characters)
                if plain != note.text { notes.update(note.id, text: plain) }
                restyle()
            }
            .onChange(of: selection) { restyle() }
            .onChange(of: theme.id) { restyle() }
    }

    private func restyle() {
        if (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true { return }
        let plain = String(text.characters)
        let key = StyleKey(text: plain, lines: editedLines(in: plain), theme: theme.id)
        guard key != styledFor else { return }
        styledFor = key
        let styled = Self.styled(plain, editing: key.lines, theme: theme)
        guard styled != text else { return }
        // Styling isn't an edit, so Undo skips it. The editor takes it within this update; registering
        // comes back on with the run loop's next pass.
        undoManager?.disableUndoRegistration()
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated { undoManager?.enableUndoRegistration() }
        }
        // Only the attributes change, run by run, so the caret and the selection stay put.
        text.transform(updating: &selection) { text in
            var start = text.startIndex
            for run in styled.runs {
                let end = text.characters.index(start, offsetBy: styled.characters[run.range].count)
                text[start..<end].setAttributes(run.attributes)
                start = end
            }
        }
    }

    /// The lines the caret or the selection is on.
    private func editedLines(in plain: String) -> ClosedRange<Int> {
        func offset(_ index: AttributedString.Index) -> Int {
            text.characters.distance(from: text.startIndex, to: index)
        }
        let range: Range<Int>
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            range = offset(index)..<offset(index)
        case .ranges(let ranges):
            let lower = ranges.ranges.first.map { offset($0.lowerBound) } ?? 0
            range = lower..<max(lower, ranges.ranges.last.map { offset($0.upperBound) } ?? 0)
        }
        return MarkdownLine.lines(touching: range, in: plain)
    }

    /// The text with every run styled as `MarkdownLine` reads it, the same characters throughout.
    static func styled(_ text: String, editing: ClosedRange<Int>, theme: Theme) -> AttributedString {
        let lines = Note.lines(of: text)
        let hidden = theme.font(.body, size: 0.01)  // all but no width
        let faint = theme.color(.tertiary)
        var result = AttributedString()
        func add(_ string: some StringProtocol, _ font: Font, _ color: Color, struck: Bool = false) {
            var piece = AttributedString(String(string))
            piece.font = font
            piece.foregroundColor = color
            piece.lineHeight = .leading(increase: 3)  // spaced as the page is while it's read
            if struck { piece.strikethroughStyle = .single }
            result.append(piece)
        }
        for (index, line) in lines.enumerated() {
            let parsed = MarkdownLine(line)
            let done = parsed.kind == .checkbox(done: true)
            let ink = theme.color(.ink).opacity(done ? 0.55 : 1)
            let (role, size, weight): (Theme.Fonts.Role, CGFloat, Font.Weight) =
                if case .heading(let level) = parsed.kind {
                    (.display, NotePage.headingSize(level), .semibold)
                } else {
                    (.body, NotePage.bodySize, .regular)
                }
            let font = theme.font(role, size: size, weight: weight)
            func mark(_ string: String, inPrefix: Bool) {
                let shows = MarkdownLine.showsMark(
                    inPrefix: inPrefix, of: parsed.kind, active: editing.contains(index), keepsMarks: theme.keepsMarks)
                add(string, shows ? font : hidden, shows ? faint : .clear)
            }
            mark(parsed.prefix, inPrefix: true)
            for part in parsed.parts {
                switch part.role {
                case .mark: mark(part.text, inPrefix: false)
                case .text: add(part.text, font, ink, struck: done)
                case .bold: add(part.text, theme.font(role, size: size, weight: .bold), ink, struck: done)
                }
            }
            if index + 1 < lines.count {
                add(text[line.endIndex..<lines[index + 1].startIndex], theme.font(.body, size: NotePage.bodySize), ink)
            }
        }
        return result
    }
}

/// A checklist item's box: filled once ticked on a dark page or where the theme selects on its
/// accent, or an inked box with a pen tick in the accent on a light one.
private struct CheckBox: View {
    let done: Bool
    let color: NoteColor?
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(min(theme.controls?.radius ?? 4, 4)), style: .continuous)
        let filled = done && (theme.selectsOnAccent || theme.appearance == .dark)
        let fill = theme.selectsOnAccent ? theme.color(.accent) : color?.swatch ?? theme.color(.accent)
        let tick =
            !filled ? theme.color(.accent) : theme.selectsOnAccent ? theme.color(.onAccent) : theme.surface.color.color
        ZStack {
            if filled {
                shape.fill(fill)
            } else {
                shape.strokeBorder(.themeInk.opacity(theme.appearance == .light ? 0.8 : 0.5), lineWidth: 1.3)
            }
            if done {
                ThemeSymbol("checkmark")
                    .themeFont(.body, size: 8, weight: .heavy)
                    .foregroundStyle(tick)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 12, height: 12)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
    }
}

/// A note's color: a dot in its swatch, glowing on a dark theme and ringed in ink on a light one,
/// square where the theme's controls are; a ring for no color.
struct NoteDot: View {
    let color: NoteColor?
    let size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = theme.controls?.radius == 0 ? AnyShape(Rectangle()) : AnyShape(Circle())
        Group {
            if let color {
                shape.fill(color.swatch)
                    .overlay {
                        if theme.appearance == .light { shape.stroke(.themeInk, lineWidth: 0.8) }
                    }
                    .shadow(color: theme.appearance == .dark ? color.swatch.opacity(0.7) : .clear, radius: 3)
            } else {
                shape.stroke(.themeInk.opacity(0.5), lineWidth: 1).padding(0.5)
            }
        }
        .frame(width: size, height: size)
    }
}

extension Theme {
    /// Whether Markdown's marks stay on the page, dim, as in a plain-text editor: in a theme whose
    /// text is monospaced. Other themes hide them where the page draws what they mean.
    @MainActor var keepsMarks: Bool {
        if let known = Self.keepsMarksByID[id] { return known }
        let keeps = nsFont(.body, size: NotePage.bodySize).isFixedPitch
        Self.keepsMarksByID[id] = keeps
        return keeps
    }

    /// By theme, as a theme's fonts never change: asked for every line drawn.
    @MainActor private static var keepsMarksByID: [String: Bool] = [:]
}

/// A line across, to stroke dotted.
private struct Rule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// The colour choices, as swatches that grow under the pointer. Opening, they spring out of the
/// colour dot one after another; closing, they fold back into it, the last one first.
private struct ColorPalette: View {
    /// The colour dot, and the gap between it and the first swatch.
    static let dot: CGFloat = 10
    static let gap: CGFloat = 10
    private static let side: CGFloat = 11
    private static let spacing: CGFloat = 5
    private static let choices: [NoteColor?] = [nil] + NoteColor.allCases.map(Optional.some)

    let selected: NoteColor?
    let open: Bool
    let choose: (NoteColor?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(Self.choices.enumerated()), id: \.offset) { index, color in
                Swatch(color: color, isSelected: selected == color) { choose(color) }
                    .scaleEffect(open || reduceMotion ? 1 : 0.2)
                    .offset(x: open || reduceMotion ? 0 : -folded(index))
                    .opacity(open ? 1 : 0)
                    .animation(animation(index), value: open)
            }
        }
        .allowsHitTesting(open)
        .accessibilityHidden(!open)
    }

    /// How far back swatch `index` sits when folded: centred on the colour dot.
    private func folded(_ index: Int) -> CGFloat {
        CGFloat(index) * (Self.side + Self.spacing) + Self.side / 2 + Self.gap + Self.dot / 2
    }

    private func animation(_ index: Int) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        let order = open ? index : Self.choices.count - 1 - index
        return .spring(response: 0.3, dampingFraction: 0.72).delay(Double(order) * 0.02)
    }

    private struct Swatch: View {
        let color: NoteColor?
        let isSelected: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Circle()
                    .fill(color?.swatch ?? .clear)
                    .overlay(
                        Circle().strokeBorder(.themeInk.opacity(isSelected ? 0.9 : 0.3), lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay {
                        if color == nil { ThemeSymbol("slash.circle").themeFont(.body, size: 8).opacity(0.6) }
                    }
                    .frame(width: 11, height: 11)
                    .scaleEffect(hovering ? 1.3 : 1)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
            .help(color?.name ?? "No Color")
            .accessibilityLabel(color?.name ?? "No Color")
        }
    }
}
