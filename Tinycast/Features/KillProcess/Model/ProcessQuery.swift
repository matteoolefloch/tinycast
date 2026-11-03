import Foundation

enum ProcessQuery {
    static let resultLimit = 300

    /// The order an empty query shows: the heaviest CPU users first, as Activity Monitor sorts.
    static func sorted(_ entries: [ProcessEntry]) -> [ProcessEntry] {
        entries.sorted { left, right in
            if left.cpuPercent != right.cpuPercent { return left.cpuPercent > right.cpuPercent }
            if left.memoryBytes != right.memoryBytes { return left.memoryBytes > right.memoryBytes }
            let names = left.name.localizedCaseInsensitiveCompare(right.name)
            if names != .orderedSame { return names == .orderedAscending }
            return left.pid < right.pid
        }
    }

    /// A typed number finds its PID first; ties keep the CPU order the snapshot arrived in.
    static func rank(_ entries: [ProcessEntry], for query: String) -> [ProcessEntry] {
        let folded = FuzzyMatch.Query(query)
        guard !folded.isEmpty else { return entries }
        let pid = Int32(query)
        return entries.enumerated()
            .compactMap { position, entry -> (ProcessEntry, Int, Int)? in
                if entry.pid == pid { return (entry, .max, position) }
                guard let quality = SearchRelevance.quality(folded, fields: entry.searchFields())
                else { return nil }
                return (entry, quality, position)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .prefix(resultLimit)
            .map(\.0)
    }
}
