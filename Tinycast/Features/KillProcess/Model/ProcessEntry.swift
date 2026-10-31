import Foundation

/// One running process the Kill Process screen offers, as one `ps` sample saw it.
struct ProcessEntry: Identifiable, Hashable, Sendable {
    let pid: Int32
    let name: String
    /// The executable's path, or the bare command name when the process hides it.
    let path: String
    let cpuPercent: Double
    let memoryBytes: Int64
    /// False for a process another user owns, which only an administrator can signal.
    let isOwnedByUser: Bool
    /// The kernel's start stamp, so a recycled PID can never be mistaken for the sampled process.
    let startTime: Int64
    /// The innermost `.app` the executable lives in, which is the icon its row paints.
    let bundleURL: URL?
    let iconStamp: Int
    /// A Dock app rather than a helper, agent or daemon.
    let isApplication: Bool

    /// A string, because every palette list identifies its rows by one.
    var id: String { String(pid) }

    // The path rides as owner: a helper is found through the app that ships it.
    func searchFields() -> SearchFields {
        [SearchAlias.name(name), SearchAlias.owner(path)]
    }

    /// `…/Foo.app/Contents/MacOS/Foo` belongs to `…/Foo.app`; a nested helper app wins over its host.
    static func bundlePath(forExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/", options: .backwards) else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    /// The command name `ps` reports when a process exposes no path is already its name.
    static func displayName(forExecutable path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}
