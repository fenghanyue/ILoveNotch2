// SPDX-License-Identifier: MIT
// Adapted from Textream (https://github.com/f/textream) at 2c02f3e: PresentationNotesExtractor.
// Copyright (c) 2026 Fatih Kadir Akin. MIT License; see THIRD_PARTY_NOTICES.md.
import Foundation

/// The speaker notes of a PowerPoint (.pptx) deck, one slide's after another. A .pptx is a zip of XML
/// files with each slide's notes in ppt/notesSlides/notesSlideN.xml.
enum PresentationNotes {
    enum Failure: LocalizedError {
        case unreadable, noNotes

        var errorDescription: String? {
            switch self {
            case .unreadable: "That presentation couldn't be opened."
            case .noNotes: "That presentation has no speaker notes."
            }
        }
    }

    /// Each slide's notes in slide order, skipping slides without any.
    static func slides(in url: URL) async throws -> [String] {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appending(path: "Prompter-\(UUID().uuidString)")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        // A copy in our own temporary folder first: in the App Sandbox, unzip runs in our sandbox and
        // can't read a file only we were given access to.
        let deck = folder.appending(path: "deck.pptx")
        do { try files.copyItem(at: url, to: deck) } catch { throw Failure.unreadable }
        let unzip = await Subprocess.run(
            "/usr/bin/unzip", ["-q", "-o", deck.path, "ppt/notesSlides/*.xml", "-d", folder.path])
        // 11: nothing matched, a deck without notes.
        guard unzip.status == 0 || unzip.status == 11 else { throw Failure.unreadable }
        let notes = folder.appending(path: "ppt/notesSlides")
        let pages = ((try? files.contentsOfDirectory(at: notes, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("notesSlide") && $0.pathExtension == "xml" }
            .sorted { slideNumber($0) < slideNumber($1) }
            .compactMap { try? Data(contentsOf: $0) }
            .map { NotesXML(data: $0).text().trimmingCharacters(in: .whitespacesAndNewlines) }
            // A slide's number placeholder alone isn't a note.
            .filter { !$0.isEmpty && Int($0) == nil }
        guard !pages.isEmpty else { throw Failure.noNotes }
        return pages
    }

    // ponytail: notesSlideN is N-th by creation, which matches slide order in decks PowerPoint and
    // Keynote write; reading ppt/_rels/presentation.xml.rels would cover reordered decks.
    private static func slideNumber(_ url: URL) -> Int {
        Int(url.deletingPathExtension().lastPathComponent.filter(\.isNumber)) ?? 0
    }
}

/// The text of one notes slide: its paragraphs, leaving out placeholders such as the slide number,
/// image, date, header, and footer.
private final class NotesXML: NSObject, XMLParserDelegate {
    private let data: Data
    private var paragraphs: [String] = []
    private var paragraph: String?
    private var run: String?
    private var inBody = false
    private var skipsShape = false

    init(data: Data) { self.data = data }

    func text() -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return paragraphs.joined(separator: "\n")
    }

    /// The element's name without its namespace prefix, so "a:t" and "t" read alike.
    private func local(_ name: String) -> Substring { name.split(separator: ":").last ?? Substring(name) }

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        switch local(name) {
        case "sp": skipsShape = false
        case "ph": skipsShape = ["sldNum", "sldImg", "dt", "hdr", "ftr"].contains(attributes["type"] ?? "")
        case "txBody": inBody = true
        case "p" where inBody && !skipsShape: paragraph = ""
        case "t" where paragraph != nil: run = ""
        case "br" where paragraph != nil: paragraph? += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        run? += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch local(name) {
        case "t":
            if let run { paragraph? += run }
            run = nil
        case "p":
            if let paragraph { paragraphs.append(paragraph) }
            paragraph = nil
        case "txBody": inBody = false
        case "sp": skipsShape = false
        default: break
        }
    }
}
