/// Most-recently-used ordering of identifiers, most recent first.
public struct MRUList<ID: Hashable> {
    public private(set) var order: [ID] = []

    public init() {}

    public mutating func touch(_ id: ID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    /// Appends identifiers that are not tracked yet, keeping their given order.
    public mutating func seed(_ ids: [ID]) {
        let known = Set(order)
        order.append(contentsOf: ids.filter { !known.contains($0) })
    }

    public mutating func prune(keeping valid: Set<ID>) {
        order.removeAll { !valid.contains($0) }
    }

    /// Tracked items first in MRU order, then untracked items in their given order.
    public func sorted<T>(_ items: [T], by id: (T) -> ID) -> [T] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })

        return items.enumerated()
            .sorted { lhs, rhs in
                let left = rank[id(lhs.element)] ?? order.count + lhs.offset
                let right = rank[id(rhs.element)] ?? order.count + rhs.offset
                return left < right
            }
            .map(\.element)
    }
}
