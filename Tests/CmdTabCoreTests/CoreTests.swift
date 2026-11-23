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
    @Test func earlierAppsGetTheSingleLetter() {
        let hints = KeyHints.assign(["Brave Browser", "Bear", "Finder"], existing: [:])

        #expect(hints == ["Brave Browser": "b", "Bear": "be", "Finder": "f"])
    }

    @Test func learnedHintsNeverChange() {
        let hints = KeyHints.assign(["Bear", "Brave Browser"], existing: ["Brave Browser": "b"])

        #expect(hints["Brave Browser"] == "b")
        #expect(hints["Bear"] == "be")
    }

    @Test func neverAssignsADoubledInitial() {
        let hints = KeyHints.assign(["Brave Browser", "BBEdit"], existing: [:])

        #expect(hints["BBEdit"] == "be")
    }

    @Test func repeatingAHintCyclesInsteadOfRestarting() {
        let hints = ["b", "be", "f"]
        let first = KeyHints.step(typed: "", key: "b", hints: hints)
        let second = KeyHints.step(typed: first.typed, key: "b", hints: hints)

        #expect(first == KeyHints.Step(typed: "b", hint: "b", cycles: false))
        #expect(second == KeyHints.Step(typed: "b", hint: "b", cycles: true))
    }

    @Test func secondLetterReachesTheLongerHint() {
        let step = KeyHints.step(typed: "b", key: "e", hints: ["b", "be", "f"])

        #expect(step == KeyHints.Step(typed: "be", hint: "be", cycles: false))
    }

    @Test func unrelatedKeyStartsOver() {
        #expect(KeyHints.step(typed: "b", key: "f", hints: ["b", "be", "f"]).hint == "f")
        #expect(KeyHints.step(typed: "b", key: "z", hints: ["b", "be", "f"]).hint == nil)
    }
}

@Suite struct WindowTitleTests {
    @Test func stripsTheAppNameSuffix() {
        #expect(WindowTitle.clean("Pull requests - Brave", appName: "Brave Browser") == "Pull requests")
        #expect(WindowTitle.clean("Inbox — Mail", appName: "Mail") == "Inbox")
    }

    @Test func putsTheProjectFirstForEditors() {
        let title = WindowTitle.clean("AppDelegate.swift — cmd-tab — Visual Studio Code", appName: "Code")

        #expect(title == "cmd-tab — AppDelegate.swift")
    }

    @Test func leavesUnrelatedSuffixesAlone() {
        #expect(WindowTitle.clean("Project Plan – Milestone 2", appName: "Pages") == "Project Plan – Milestone 2")
        #expect(WindowTitle.clean("Notes - B", appName: "Brave Browser") == "Notes - B")
        #expect(WindowTitle.clean("Brave", appName: "Brave Browser") == "Brave")
    }
}
