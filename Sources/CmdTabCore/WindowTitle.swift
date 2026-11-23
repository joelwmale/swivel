public enum WindowTitle {
    private static let separators = [" — ", " – ", " - "]

    /// Editors title their windows "file — project"; the project is what tells
    /// two windows apart, so it goes first.
    private static let projectLastApps: Set<String> = ["Code", "Code - Insiders", "Cursor", "VSCodium", "Windsurf"]

    public static func clean(_ title: String, appName: String) -> String {
        var cleaned = title

        if let parts = splitAtLastSeparator(cleaned), names(parts.tail, app: appName) {
            cleaned = parts.head
        }
        if projectLastApps.contains(appName), let parts = splitAtLastSeparator(cleaned) {
            cleaned = "\(parts.tail) — \(parts.head)"
        }

        return cleaned
    }

    private static func splitAtLastSeparator(_ title: String) -> (head: String, tail: String)? {
        let last = separators
            .compactMap { title.range(of: $0, options: .backwards) }
            .max { $0.lowerBound < $1.lowerBound }

        guard let last, last.lowerBound > title.startIndex, last.upperBound < title.endIndex else {
            return nil
        }
        return (String(title[..<last.lowerBound]), String(title[last.upperBound...]))
    }

    /// "Brave" names "Brave Browser"; "Visual Studio Code" names "Code".
    private static func names(_ segment: String, app: String) -> Bool {
        let segment = segment.lowercased()
        let app = app.lowercased()
        return segment == app || app.hasPrefix(segment + " ") || segment.hasSuffix(" " + app)
    }
}
