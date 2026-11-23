import Testing
@testable import CmdTabCore

@Suite struct FuzzyMatcherTests {
    @Test func rejectsQueriesThatAreNotASubsequence() {
        #expect(FuzzyMatcher.match("xyz", in: "Brave Browser") == nil)
        #expect(FuzzyMatcher.match("rb", in: "Brave") == nil)
    }

    @Test func matchesAcrossAppNameAndTitleIgnoringCase() {
        let match = FuzzyMatcher.match("cdapp", in: "Code AppDelegate.swift")

        #expect(match != nil)
    }

    @Test func prefersWordStartsOverScatteredLetters() throws {
        let initials = try #require(FuzzyMatcher.match("pp", in: "Project Plan"))
        let scattered = try #require(FuzzyMatcher.match("pp", in: "Skipping steps"))

        #expect(initials.score > scattered.score)
        #expect(initials.indices == [0, 8])
    }

    @Test func prefersConsecutiveRunsOverGaps() throws {
        let run = try #require(FuzzyMatcher.match("cal", in: "Calendar"))
        let gapped = try #require(FuzzyMatcher.match("cal", in: "Chat about lunch"))

        #expect(run.score > gapped.score)
        #expect(run.indices == [0, 1, 2])
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatcher.match("", in: "Anything") == FuzzyMatch(score: 0, indices: []))
    }
}

@Suite struct MRUListTests {
    @Test func touchMovesItemToFront() {
        var mru = MRUList<String>()
        mru.seed(["a", "b", "c"])
        mru.touch("c")
        mru.touch("b")

        #expect(mru.order == ["b", "c", "a"])
    }

    @Test func sortedPutsUntrackedItemsLastInGivenOrder() {
        var mru = MRUList<String>()
        mru.seed(["a", "b"])
        mru.touch("b")

        #expect(mru.sorted(["x", "a", "y", "b"]) { $0 } == ["b", "a", "x", "y"])
    }

    @Test func pruneDropsClosedWindows() {
        var mru = MRUList<String>()
        mru.seed(["a", "b", "c"])
        mru.prune(keeping: ["a", "c"])

        #expect(mru.order == ["a", "c"])
    }
}

@Suite struct KeyHintsTests {
    @Test func uniqueInitialGetsOneLetter() {
        #expect(KeyHints.assign(to: ["Brave Browser", "Finder", "1Password"]) == ["b", "f", "1"])
    }

    @Test func sharedInitialGetsASecondKeyAndNoHintPrefixesAnother() {
        let hints = KeyHints.assign(to: ["Brave Browser", "Code", "Brave Browser", "Bear"])

        #expect(hints == ["ba", "c", "bs", "bd"])
        for hint in hints {
            #expect(hints.filter { $0.hasPrefix(hint) }.count == 1)
        }
    }
}
