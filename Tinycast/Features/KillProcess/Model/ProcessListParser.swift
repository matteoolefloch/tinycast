import Foundation

/// Reads `ps -axww -o pid=,uid=,%cpu=,rss=,comm=` output; pure, so the harness feeds it text.
enum ProcessListParser {
    struct Sample: Hashable, Sendable {
        let pid: Int32
        let uid: UInt32
        let cpuPercent: Double
        let memoryBytes: Int64
        let command: String
    }

    static let arguments = ["-axww", "-o", "pid=,uid=,%cpu=,rss=,comm="]

    static func parse(_ output: String) -> [Sample] {
        output.split(whereSeparator: \.isNewline).compactMap { parse(line: Substring($0)) }
    }

    /// The command is the line's remainder, since an executable path may itself hold spaces.
    static func parse(line: Substring) -> Sample? {
        var rest = line[...]
        var fields: [Substring] = []
        for _ in 0..<4 {
            rest = rest.drop { $0 == " " || $0 == "\t" }
            guard let end = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
            fields.append(rest[..<end])
            rest = rest[end...]
        }
        let command = rest.trimmingCharacters(in: .whitespaces)
        guard let pid = Int32(fields[0]), let uid = UInt32(fields[1]),
            let cpu = Double(fields[2].replacingOccurrences(of: ",", with: ".")),
            let residentKilobytes = Int64(fields[3]), !command.isEmpty
        else { return nil }
        return Sample(
            pid: pid, uid: uid, cpuPercent: cpu, memoryBytes: residentKilobytes * 1024,
            command: command)
    }

    /// The kernel and `launchd` can never be killed, and Tinycast must not list itself.
    static func isListed(pid: Int32, selfPID: Int32) -> Bool {
        pid > 1 && pid != selfPID
    }
}
