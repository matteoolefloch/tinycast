import Foundation

/// The root shell line: it re-proves the start stamp itself, since the password prompt can outlast it.
enum AdministratorKillCommand {
    static let stampArguments = ["-o", "lstart=", "-p"]

    /// Nil unless `stamp` is letters, digits, colons and spaces, so it can sit inside single quotes.
    static func make(signal: Int32, pid: Int32, stamp: String) -> String? {
        let stamp = stamp.trimmingCharacters(in: .whitespaces)
        guard !stamp.isEmpty,
            stamp.unicodeScalars.allSatisfy({
                ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                    || $0 == ":" || $0 == " "
            })
        else { return nil }
        let lookup = (["LC_ALL=C", "/bin/ps"] + stampArguments + [String(pid)]).joined(separator: " ")
        return "\(lookup) | /usr/bin/grep -qF '\(stamp)' && /bin/kill -\(signal) \(pid)"
    }
}
