// SPDX-License-Identifier: MIT
// Adapted from Textream (https://github.com/f/textream) at 2c02f3e: SpeechRecognizer's word-level
// match and fuzzy word comparison, and SpeechTextAlignment's commit gate, counted in words.
// Copyright (c) 2026 Fatih Kadir Akin. MIT License; see THIRD_PARTY_NOTICES.md.

/// Follows a script as it's read aloud: which word comes next, given what the recognizer has heard.
/// A recognition task reports everything heard since it began, revised as it goes, so each result is
/// matched again from where that task started; a new task gets a new alignment from the current word.
/// The position only ever moves forward.
struct ScriptAlignment {
    /// The script's words as compared: lowercased letters and digits. Punctuation alone is empty.
    let words: [String]
    /// The next word to read.
    private(set) var current: Int
    /// Where in the script the transcript being matched began.
    private let anchor: Int
    /// The last few results' positions; a long jump needs two of them to agree.
    private var recent: [Int] = []

    init(_ words: [String], at current: Int = 0) {
        self.words = words.map(Self.normalized)
        self.current = min(max(current, 0), words.count)
        anchor = self.current
    }

    /// Moves on to where `transcript` reaches, and returns the next word to read.
    @discardableResult
    mutating func match(_ transcript: String) -> Int {
        let spoken = transcript.split(whereSeparator: \.isWhitespace).map { Self.normalized(String($0)) }
            .filter { !$0.isEmpty }
        let candidate = anchor + Self.matched(Array(words[anchor...]), spoken)
        guard candidate > current else { return current }
        recent = Array((recent + [candidate]).suffix(3))
        let confirmed = recent.filter { abs($0 - candidate) <= 2 }.count >= 2
        // ponytail: word-level only; Textream also runs a character-level match and averages the two.
        // Add it if following drifts on long or hyphenated words.
        // A few words at a time is reading; a longer leap must show up in two results before it's trusted.
        if candidate - current <= 3 || confirmed { current = candidate }
        return current
    }

    /// How many of `source`'s words `spoken` covers, in order: up to five words the recognizer added,
    /// or five the reader skipped, are passed over to find the thread again.
    static func matched(_ source: [String], _ spoken: [String]) -> Int {
        func matches(_ s: Int, _ r: Int) -> Bool {
            s < source.count && r < spoken.count && isFuzzyMatch(source[s], spoken[r])
        }
        var (s, r) = (0, 0)
        while s < source.count, r < spoken.count {
            if source[s].isEmpty {  // punctuation on its own: nothing to hear
                s += 1
            } else if matches(s, r) {
                (s, r) = (s + 1, r + 1)
            } else if let skip = (1...5).first(where: { matches(s, r + $0) }) {
                r += skip
            } else if let skip = (1...5).first(where: { matches(s + $0, r) }) {
                s += skip
            } else {
                r += 1  // a word that isn't in the script
            }
        }
        while s < source.count, source[s].isEmpty { s += 1 }
        return s
    }

    /// Whether two words are likely the same word misheard: the same, one starting the other, a long
    /// shared start, or a few letters apart, with less leeway the shorter they are.
    static func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let shorter = min(a.count, b.count)
        guard shorter > 2 else { return false }  // "or" mustn't match "organization"
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        let shared = zip(a, b).prefix { $0 == $1 }.count
        if shared >= max(3, shorter * 3 / 5) { return true }
        let distance = editDistance(a, b)
        if shorter <= 4 { return distance <= 1 }
        if shorter <= 8 { return distance <= 2 }
        return distance <= max(a.count, b.count) / 3
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let (a, b) = (Array(a), Array(b))
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let above = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = above
            }
        }
        return row[b.count]
    }

    static func normalized(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
