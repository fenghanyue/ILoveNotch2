// SPDX-License-Identifier: MIT
import Testing

@testable import NotchFeatures

/// Following a script read aloud: what the recognizer hears, partial result by partial result, to
/// the next word to read.
struct PrompterTests {
    private let script = "Good morning, everyone. Today we're launching the notch teleprompter — finally!"
        .split(separator: " ").map(String.init)

    /// Each result is everything heard so far, the way the recognizer reports it.
    private func follow(_ results: [String], from start: Int = 0) -> [Int] {
        var alignment = ScriptAlignment(script, at: start)
        return results.map { alignment.match($0) }
    }

    @Test func followsTheWordsAsTheyAreSaid() {
        let heard = follow(["good", "good morning", "good morning everyone", "good morning everyone today"])
        #expect(heard == [1, 2, 3, 4])
    }

    @Test func toleratesMisheardWords() {
        // "were" for "we're", "lunching" for "launching", "nautch" for "notch", "teleprompters" for
        // "teleprompter": close enough to keep going.
        let opening = "good morning everyone today"
        let heard = follow([
            opening, "\(opening) were lunching", "\(opening) were lunching the nautch",
            "\(opening) were lunching the nautch teleprompters",
        ])
        // The dash on its own has nothing to hear, so the next word after "teleprompter" is "finally!".
        #expect(heard.last == 10)
        #expect(heard == heard.sorted(), "it only moves forward")
    }

    @Test func passesOverWordsThatArentInTheScriptAndWordsTheReaderSkips() {
        // An "um", then "everyone" left out.
        #expect(follow(["good um morning", "good um morning today"]) == [2, 4])
    }

    @Test func aLongLeapWaitsForASecondResult() {
        // A single result claiming eight words at once could be a stray match; two in a row aren't.
        let leap = "good morning everyone today were launching the notch"
        #expect(follow([leap]) == [0])
        #expect(follow([leap, leap]) == [0, 8])
    }

    @Test func aNewTranscriptPicksUpWhereTheLastLeftOff() {
        // A new recognition task starts from nothing, so its words are matched from word 4 on.
        #expect(follow(["were launching"], from: 4) == [6])
        #expect(follow(["good morning"], from: 4) == [4], "words already read don't count again")
    }

    @Test func shortWordsMustMatchExactly() {
        #expect(!ScriptAlignment.isFuzzyMatch("or", "organization"))
        #expect(!ScriptAlignment.isFuzzyMatch("we", "me"))
        #expect(ScriptAlignment.isFuzzyMatch("launching", "lunching"))
        #expect(!ScriptAlignment.isFuzzyMatch("morning", "evening"))
    }
}
