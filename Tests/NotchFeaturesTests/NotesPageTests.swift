// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchFeatures

/// The page's Markdown: what each line is, which characters are marks, ticking a box, ⌘L, and which
/// marks stay faint in the editor.
@MainActor
struct NotesPageTests {
    private func parts(_ line: String) -> [String] {
        let parsed = MarkdownLine(line)
        return (parsed.prefix.isEmpty ? [] : ["[\(parsed.prefix)]"])
            + parsed.parts.map { $0.role == .mark ? "[\($0.text)]" : $0.role == .bold ? "*\($0.text)*" : $0.text }
    }

    @Test func linesSplitIntoTheirMarksAndText() {
        #expect(MarkdownLine("## Before Friday").kind == .heading(2))
        #expect(parts("## Before Friday") == ["[## ]", "Before Friday"])
        #expect(MarkdownLine("  * [x] tickets").kind == .checkbox(done: true))
        #expect(parts("  * [x] tickets") == ["[  * [x] ]", "tickets"])
        #expect(MarkdownLine("- [ ]").kind == .checkbox(done: false))
        #expect(parts("214 **Sponsors** hear") == ["214 ", "[**]", "*Sponsors*", "[**]", " hear"])
        #expect(MarkdownLine("- milk").kind == .bullet)
        #expect(MarkdownLine("- [ ]x").kind == .bullet, "not a box, as openChecklistItems reads it")
        for text in ["#tag", "---", "**", "a ** b", "1. pack", ""] {
            #expect(MarkdownLine(text).kind == .text, "\(text)")
            #expect(MarkdownLine(text).parts.allSatisfy { $0.role == .text }, "\(text) has no marks")
        }
    }

    @Test func tickingAndChecklistingKeepTheRestOfTheLine() {
        #expect(MarkdownLine.togglingCheckbox("  - [ ] passport") == "  - [x] passport")
        #expect(MarkdownLine.togglingCheckbox("- [X] done") == "- [ ] done")
        #expect(MarkdownLine.togglingCheckbox("plain") == "plain")
        #expect(MarkdownLine.togglingChecklist("Reply to App Review") == "- [ ] Reply to App Review")
        #expect(MarkdownLine.togglingChecklist("  - socks") == "  - [ ] socks")
        #expect(MarkdownLine.togglingChecklist("# Trip") == "- [ ] Trip")
        #expect(MarkdownLine.togglingChecklist("  - [x] socks") == "  socks")

        let text = "Trip\r\n- [ ] passport\n- socks"
        let ticked = Note.replacingLine(1, in: text, with: MarkdownLine.togglingCheckbox)
        #expect(ticked == "Trip\r\n- [x] passport\n- socks", "the other lines and their breaks stay")
        #expect(Note.replacingLine(9, in: text, with: { _ in "x" }) == text)

        let notes = NotesFeature(directory: FileManager.default.temporaryDirectory.appending(path: "NP-\(UUID())"))
        let id = notes.add("Trip\n- [ ] passport")
        notes.toggleCheckbox(id, line: 1)
        #expect(notes.selected?.text == "Trip\n- [x] passport")
        #expect(notes.selected?.excerpt == "passport")
    }

    @Test func marksAreFaintOnTheEditedLinesAndHiddenElsewhere() {
        let heading = MarkdownLine.Kind.heading(1)
        #expect(MarkdownLine.showsMark(inPrefix: true, of: heading, active: true, keepsMarks: false))
        #expect(!MarkdownLine.showsMark(inPrefix: true, of: heading, active: false, keepsMarks: false))
        #expect(!MarkdownLine.showsMark(inPrefix: false, of: .text, active: false, keepsMarks: false), "bold's **")
        #expect(MarkdownLine.showsMark(inPrefix: true, of: .checkbox(done: false), active: false, keepsMarks: false))
        #expect(!MarkdownLine.showsMark(inPrefix: false, of: .checkbox(done: false), active: false, keepsMarks: false))
        #expect(MarkdownLine.showsMark(inPrefix: false, of: .text, active: false, keepsMarks: true), "a mono theme's")

        let text = "Title\n\n- [ ] one\ntwo"
        #expect(MarkdownLine.lines(touching: 0..<0, in: text) == 0...0)
        #expect(MarkdownLine.lines(touching: 5..<5, in: text) == 0...0, "the caret at the end of a line")
        #expect(MarkdownLine.lines(touching: 6..<6, in: text) == 1...1)
        #expect(MarkdownLine.lines(touching: 3..<10, in: text) == 0...2)
        #expect(MarkdownLine.lines(touching: 2..<6, in: text) == 0...0, "a selection ending on a break")
        #expect(MarkdownLine.lines(touching: 20..<20, in: text) == 3...3)
    }
}
