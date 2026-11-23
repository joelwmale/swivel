import Foundation

public enum KeyHints {
    private static let fallbackSecondKeys = Array("asdfghjklqwertyuiopzxcvbnm")

    public struct Step: Equatable {
        public let typed: String
        public let hint: String?
        /// The same hint was asked for again: move to that app's next window.
        public let cycles: Bool
    }

    /// Gives each new name a hint and leaves `existing` ones alone, so a hint
    /// never changes once learned. Earlier names get first pick: the initial,
    /// then the initial plus a later letter of the name.
    public static func assign(_ names: [String], existing: [String: String]) -> [String: String] {
        var hints = existing
        var taken = Set(existing.values)

        for name in names where hints[name] == nil {
            let letters = name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .filter { $0.isLetter || $0.isNumber }
            guard let initial = letters.first else {
                continue
            }

            // A doubled initial is reserved: pressing a hint's last key again cycles.
            let secondKeys = (Array(letters.dropFirst()) + fallbackSecondKeys).filter { $0 != initial }
            let options = [String(initial)] + secondKeys.map { "\(initial)\($0)" }

            if let free = options.first(where: { !taken.contains($0) }) {
                hints[name] = free
                taken.insert(free)
            }
        }

        return hints
    }

    /// `hints` are the visible apps' hints in list order.
    public static func step(typed: String, key: String, hints: [String]) -> Step {
        func target(_ prefix: String) -> String? {
            hints.first { $0 == prefix } ?? hints.first { $0.hasPrefix(prefix) }
        }

        if let hint = target(typed + key) {
            return Step(typed: typed + key, hint: hint, cycles: false)
        }
        if hints.contains(typed), typed.hasSuffix(key) {
            return Step(typed: typed, hint: typed, cycles: true)
        }
        if let hint = target(key) {
            return Step(typed: key, hint: hint, cycles: false)
        }
        return Step(typed: "", hint: nil, cycles: false)
    }
}
