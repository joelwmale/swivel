public struct FuzzyMatch: Equatable {
    public let score: Int
    public let indices: [Int]
}

public enum FuzzyMatcher {
    private static let wordStartBonus = 8
    private static let consecutiveBonus = 9
    private static let firstCharacterBonus = 4
    private static let gapPenalty = 2
    private static let unreachable = Int.min / 2

    /// Case-insensitive subsequence match. Returns nil when `query` is not a
    /// subsequence of `candidate`; `indices` are character offsets into `candidate`.
    public static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        let original = Array(candidate)
        let haystack = original.map { Character($0.lowercased()) }

        guard !needle.isEmpty else {
            return FuzzyMatch(score: 0, indices: [])
        }
        guard needle.count <= haystack.count else {
            return nil
        }

        let bonuses = original.indices.map { positionBonus(at: $0, in: original) }

        // score[i][j]: best score with needle[i] matched at haystack[j].
        var score = Array(repeating: Array(repeating: unreachable, count: haystack.count), count: needle.count)
        var previous = Array(repeating: Array(repeating: -1, count: haystack.count), count: needle.count)

        for i in needle.indices {
            var bestGapScore = unreachable
            var bestGapIndex = -1

            for j in haystack.indices {
                // Candidates at j - 2 and earlier become reachable through a gap.
                if i > 0, j >= 2, score[i - 1][j - 2] > bestGapScore {
                    bestGapScore = score[i - 1][j - 2]
                    bestGapIndex = j - 2
                }

                guard needle[i] == haystack[j] else {
                    continue
                }

                if i == 0 {
                    score[i][j] = bonuses[j]
                    continue
                }

                let consecutive = j >= 1 && score[i - 1][j - 1] > unreachable
                    ? score[i - 1][j - 1] + consecutiveBonus
                    : unreachable
                let gapped = bestGapScore > unreachable ? bestGapScore - gapPenalty : unreachable

                guard max(consecutive, gapped) > unreachable else {
                    continue
                }

                if consecutive >= gapped {
                    score[i][j] = consecutive + bonuses[j]
                    previous[i][j] = j - 1
                } else {
                    score[i][j] = gapped + bonuses[j]
                    previous[i][j] = bestGapIndex
                }
            }
        }

        let lastRow = score[needle.count - 1]
        guard let best = lastRow.max(), best > unreachable, var j = lastRow.firstIndex(of: best) else {
            return nil
        }

        var indices: [Int] = []
        for i in needle.indices.reversed() {
            indices.append(j)
            j = previous[i][j]
        }

        return FuzzyMatch(score: best, indices: indices.reversed())
    }

    private static func positionBonus(at index: Int, in characters: [Character]) -> Int {
        guard index > 0 else {
            return wordStartBonus + firstCharacterBonus
        }

        let current = characters[index]
        let before = characters[index - 1]

        if !before.isLetter && !before.isNumber {
            return wordStartBonus
        }
        if before.isLowercase && current.isUppercase {
            return wordStartBonus
        }
        return 0
    }
}
