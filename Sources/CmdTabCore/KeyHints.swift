import Foundation

public enum KeyHints {
    /// Second keys are handed out from the home row first.
    private static let suffixes = Array("asdfghjklqwertyuiopzxcvbnm")

    /// One hint per name, in order. A name whose initial is unique gets that
    /// letter; names sharing an initial get the letter plus a second key, so no
    /// hint is a prefix of another and typing one is never ambiguous.
    public static func assign(to names: [String]) -> [String] {
        let initials = names.map { name in
            name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .first { $0.isLetter || $0.isNumber }
                .map { String($0) } ?? ""
        }
        let counts = Dictionary(initials.map { ($0, 1) }, uniquingKeysWith: +)
        var used: [String: Int] = [:]

        return initials.map { initial in
            guard !initial.isEmpty else {
                return ""
            }
            guard counts[initial, default: 0] > 1 else {
                return initial
            }

            let position = used[initial, default: 0]
            used[initial] = position + 1
            return position < suffixes.count ? initial + String(suffixes[position]) : ""
        }
    }
}
