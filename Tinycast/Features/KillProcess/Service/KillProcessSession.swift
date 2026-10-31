import AppKit

@MainActor
@Observable
final class KillProcessSession {
    enum State {
        case idle
        case loading
        case ready
    }

    private(set) var state: State = .idle
    private(set) var snapshot: [ProcessEntry] = []
    /// The rows the list reads: ranked once per query change, so one keystroke ranks once.
    private(set) var filtered: [ProcessEntry] = []

    private var query = ""
    private var revision = 0
    @ObservationIgnored private var sampleTask: Task<Void, Never>?

    /// A reload keeps the old rows up until the new sample lands, so the list never blanks.
    func load() {
        revision &+= 1
        sampleTask?.cancel()
        if snapshot.isEmpty { state = .loading }
        let revision = self.revision
        let applications = Self.runningApplications()
        let selfPID = ProcessInfo.processInfo.processIdentifier
        sampleTask = Task { [weak self] in
            let entries = await ProcessSampler.sample(applications: applications, selfPID: selfPID)
            guard let self, self.revision == revision else { return }
            self.snapshot = ProcessQuery.sorted(entries)
            self.state = .ready
            self.applyQuery()
            self.sampleTask = nil
        }
    }

    func reset() {
        revision &+= 1
        sampleTask?.cancel()
        sampleTask = nil
        state = .idle
        snapshot = []
        filtered = []
        query = ""
    }

    func filter(_ query: String) {
        self.query = query
        applyQuery()
    }

    func remove(_ pid: Int32) {
        snapshot.removeAll { $0.pid == pid }
        applyQuery()
    }

    private func applyQuery() {
        filtered = ProcessQuery.rank(
            snapshot, for: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func runningApplications() -> [Int32: ProcessSampler.Application] {
        var table: [Int32: ProcessSampler.Application] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName else { continue }
            table[app.processIdentifier] = ProcessSampler.Application(
                name: name, bundleURL: app.bundleURL, isRegular: app.activationPolicy == .regular)
        }
        return table
    }
}
