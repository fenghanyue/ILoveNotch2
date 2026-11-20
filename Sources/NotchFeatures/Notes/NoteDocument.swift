// SPDX-License-Identifier: MIT
import Foundation

/// A note's colour, stored by name so other Markdown apps see a readable value.
public enum NoteColor: String, CaseIterable, Identifiable, Sendable {
    case red
    case orange
    case yellow
    case green
    case mint
    case blue
    case purple
    case pink

    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
}

/// One note: a Markdown file. Its colour and pin live in a small front matter block at the top of the
/// file (the `---` header Obsidian and other Markdown apps read), written only when one is set, so an
/// uncoloured note stays plain text.
public struct Note: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The note's text, without the front matter.
    public var text: String
    public var modified: Date
    public var created: Date
    public var color: NoteColor?
    public var isPinned = false
    /// The file's name in the notes folder; nil until the note is first saved.
    var fileName: String?
    /// Whether the file is named after the title the way ILoveNotch names notes, so a new title
    /// renames it. A file the user named, say in a Markdown app's folder, keeps its name.
    var followsTitle = true
    /// Front matter lines other apps wrote, kept as they were.
    var otherFields: [String] = []

    public init(
        id: UUID, text: String, modified: Date, created: Date? = nil, color: NoteColor? = nil, isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.modified = modified
        self.created = created ?? modified
        self.color = color
        self.isPinned = isPinned
    }

    /// Reads a note file's contents.
    init(id: UUID, fileName: String, contents: String, modified: Date, created: Date?) {
        let (fields, body) = Self.splitFrontMatter(contents)
        self.init(id: id, text: body, modified: modified, created: created)
        self.fileName = fileName
        for line in fields {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            switch (parts.first?.lowercased(), parts.count == 2 ? parts[1] : nil) {
            case ("color"?, let value?), ("colour"?, let value?):
                color = NoteColor(rawValue: value.lowercased())
            case ("pinned"?, let value?):
                isPinned = value.lowercased() == "true"
            default:
                otherFields.append(line)
            }
        }
        let base = (fileName as NSString).deletingPathExtension
        followsTitle = UUID(uuidString: base) != nil || Self.isNamed(base, after: title)
    }

    /// Whether `base` is a file name ILoveNotch gives a note titled `title`: "Groceries", or
    /// "Groceries 2" next to another note of that title.
    static func isNamed(_ base: String, after title: String) -> Bool {
        guard let name = base.range(of: fileBase(for: title), options: [.anchored, .caseInsensitive]) else {
            return false
        }
        let rest = base[name.upperBound...]
        return rest.isEmpty || (rest.first == " " && rest.count > 1 && rest.dropFirst().allSatisfy(\.isNumber))
    }

    /// The first non-empty line, without Markdown heading marks, or "New Note".
    public var title: String {
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line ?? "New Note"
    }

    /// A few lines after the title, for the hover preview.
    public var preview: String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.dropFirst().prefix(4).joined(separator: "\n")
    }

    public var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The checklist items not yet ticked, like "passport" from "- [ ] passport", in order. Empty
    /// ones are left out.
    public var openChecklistItems: [String] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let marker = trimmed.first, "-*+".contains(marker), trimmed.dropFirst().hasPrefix(" [ ]") else {
                return nil
            }
            let rest = trimmed.dropFirst(5)
            guard rest.isEmpty || rest.first == " " else { return nil }  // "- [ ]x" isn't a checkbox
            let item = rest.trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
    }

    /// Whether the note has checklist items not yet ticked.
    public var hasOpenChecklist: Bool { !openChecklistItems.isEmpty }

    /// What goes on disk: front matter, when there's anything for it, then the text.
    var fileContents: String {
        var fields: [String] = []
        if let color { fields.append("color: \(color.rawValue)") }
        if isPinned { fields.append("pinned: true") }
        fields += otherFields
        guard !fields.isEmpty else { return text }
        return "---\n" + fields.joined(separator: "\n") + "\n---\n" + text
    }

    /// A file name from the title: "Groceries.md". Characters Finder and iCloud reject become dashes.
    static func fileBase(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.newlines).union(.controlCharacters)
        var base = String(String.UnicodeScalarView(title.unicodeScalars.map { forbidden.contains($0) ? "-" : $0 }))
        base = base.trimmingCharacters(in: .whitespaces)
        while base.hasPrefix(".") { base.removeFirst() }
        base = String(base.prefix(80)).trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? "Note" : base
    }

    /// Splits a leading `---` block off a file. Anything else, including a lone `---` rule, is text.
    static func splitFrontMatter(_ contents: String) -> (fields: [String], body: String) {
        let lines = contents.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return ([], contents) }
        let header = lines[1..<end].map(String.init)
        // Front matter is "key: value" lines; anything else means the dashes were a rule.
        let isField = { (line: String) in line.contains(":") || line.trimmingCharacters(in: .whitespaces).isEmpty }
        guard header.allSatisfy(isField) else { return ([], contents) }
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (header.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, body)
    }

    /// The text's lines, as slices of it, empty ones too; "\r\n" counts as one break.
    static func lines(of text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    /// The first non-empty line after the title, without its Markdown marks, for the list.
    public var excerpt: String {
        Self.lines(of: text).lazy.map(MarkdownLine.init)
            .map { $0.parts.filter { $0.role != .mark }.map(\.text).joined().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.dropFirst().first ?? ""
    }

    /// The text with line `index` (as `lines(of:)` counts them) passed through `change`; the other
    /// lines, and their breaks, stay as they were.
    static func replacingLine(_ index: Int, in text: String, with change: (String) -> String) -> String {
        let lines = lines(of: text)
        guard lines.indices.contains(index) else { return text }
        var text = text
        text.replaceSubrange(lines[index].startIndex..<lines[index].endIndex, with: change(String(lines[index])))
        return text
    }
}

/// One line of a note's Markdown as the page draws it: a heading, a checklist item, a list item, or
/// text, split into its marks and the text they format. Only what the page shows is read: `#`
/// headings, `- [ ]` boxes, `-` items, and `**bold**`.
struct MarkdownLine: Equatable {
    enum Kind: Equatable {
        case text
        /// `#` to `######`, by its number of marks.
        case heading(Int)
        /// `- `, `* `, or `+ `.
        case bullet
        /// `- [ ]`, or `- [x]` once ticked.
        case checkbox(done: Bool)
    }

    enum Role: Equatable {
        case mark, text, bold
    }

    struct Part: Equatable {
        let role: Role
        let text: String
    }

    let kind: Kind
    /// The leading mark with the indent before it, as typed: "  - [ ] " or "## "; empty for text.
    let prefix: String
    /// The rest of the line in order: text, and each bold span between its two `**` marks.
    let parts: [Part]
    /// Spaces or tabs before the mark, for nesting.
    let indent: Int

    init(_ line: some StringProtocol) {
        let characters = Array(line)
        indent = characters.prefix { $0 == " " || $0 == "\t" }.count
        let rest = characters[indent...]
        let hashes = rest.prefix { $0 == "#" }.count
        var end = indent
        if let marker = rest.first, "-*+".contains(marker), rest.dropFirst().first == " " {
            let box = Array(rest.dropFirst(2).prefix(4))
            if box.count >= 3, box[0] == "[", box[2] == "]", " xX".contains(box[1]), box.count == 3 || box[3] == " " {
                kind = .checkbox(done: box[1] != " ")
                end = indent + 2 + box.count
            } else {
                kind = .bullet
                end = indent + 2
            }
        } else if (1...6).contains(hashes), hashes == rest.count || rest.dropFirst(hashes).first == " " {
            kind = .heading(hashes)
            end = min(characters.count, indent + hashes + 1)
        } else {
            kind = .text
        }
        prefix = kind == .text ? "" : String(characters[..<end])
        parts = Self.parts(characters[(kind == .text ? 0 : end)...])
    }

    /// Text and `**bold**` spans; a `**` without a partner, or around nothing, stays text.
    private static func parts(_ characters: ArraySlice<Character>) -> [Part] {
        var parts: [Part] = []
        var start = characters.startIndex
        var index = start
        func add(_ role: Role, _ range: Range<Int>) {
            if !range.isEmpty { parts.append(Part(role: role, text: String(characters[range]))) }
        }
        func isMark(_ at: Int) -> Bool {
            at + 1 < characters.endIndex && characters[at] == "*" && characters[at + 1] == "*"
        }
        while index < characters.endIndex {
            guard isMark(index), index + 3 <= characters.endIndex,
                let close = (index + 3..<characters.endIndex).first(where: isMark)
            else {
                index += 1
                continue
            }
            add(.text, start..<index)
            add(.mark, index..<index + 2)
            add(.bold, index + 2..<close)
            add(.mark, close..<close + 2)
            index = close + 2
            start = index
        }
        add(.text, start..<characters.endIndex)
        return parts
    }

    /// The line with its box ticked, or unticked; any other line as it is.
    static func togglingCheckbox(_ line: String) -> String {
        let parsed = MarkdownLine(line)
        guard case .checkbox(let done) = parsed.kind else { return line }
        var characters = Array(line)
        characters[parsed.indent + 3] = done ? " " : "x"  // between the brackets of "- [ ]"
        return String(characters)
    }

    /// ⌘L: the line as a checklist item, keeping its indent and text; a checklist item goes back to
    /// plain text.
    static func togglingChecklist(_ line: String) -> String {
        let parsed = MarkdownLine(line)
        let indent = line.prefix(parsed.indent)
        let text = line.dropFirst(parsed.kind == .text ? parsed.indent : parsed.prefix.count)
        if case .checkbox = parsed.kind { return String(indent + text) }
        return String(indent) + "- [ ] " + text
    }

    /// Whether a mark shows in the editor, faintly: on the lines being edited, and always in a theme
    /// that keeps its marks or for a list's marker (the page's box or dot while reading). A heading's
    /// and bold text's marks hide on the other lines.
    static func showsMark(inPrefix: Bool, of kind: Kind, active: Bool, keepsMarks: Bool) -> Bool {
        if active || keepsMarks { return true }
        switch kind {
        case .bullet, .checkbox: return inPrefix
        case .text, .heading: return false
        }
    }

    /// The lines (as `Note.lines(of:)` counts them) that the characters `range` of `text` touch; an
    /// empty range is the caret, on one line.
    static func lines(touching range: Range<Int>, in text: String) -> ClosedRange<Int> {
        func line(at offset: Int) -> Int { text.prefix(offset).filter(\.isNewline).count }
        let first = line(at: range.lowerBound)
        return first...max(first, line(at: max(range.lowerBound, range.upperBound - 1)))
    }
}
