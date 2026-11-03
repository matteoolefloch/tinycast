import AppKit

@MainActor
@Observable
final class KillProcessSession {
    typealias SampleOperation =
        @Sendable (_ applications: [Int32: ProcessSampler.Application], _ selfPID: Int32) async
        -> [ProcessEntry]

    enum State {
        case idle
        case loading
        case ready
    }

    private(set) var state: State = .idle
    private(set) var snapshot: [ProcessEntry] = []
    /// The rows the list reads: ranked once per query change, so one keystroke ranks once.
    private(set) var filtered: [ProcessEntry] = []
    /// Killed rows stay put, dimmed: removing one would slide the next process under a repeated ↵.
    private(set) var signalledPIDs: Set<Int32> = []

    private var query = ""
    private var revision = 0
    @ObservationIgnored private var sampleTask: Task<Void, Never>?
    @ObservationIgnored private let sampleOperation: SampleOperation

    init() {
        sampleOperation = { await ProcessSampler.sample(applications: $0, selfPID: $1) }
    }

    init(sampleOperation: @escaping SampleOperation) {
        self.sampleOperation = sampleOperation
    }

    /// A reload keeps the old rows up until the new sample lands, so the list never blanks.
    func load(then onLoaded: (@MainActor () -> Void)? = nil) {
        revision &+= 1
        sampleTask?.cancel()
        if snapshot.isEmpty { state = .loading }
        let revision = self.revision
        let applications = Self.runningApplications()
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let operation = sampleOperation
        sampleTask = Task { [weak self] in
            let entries = await operation(applications, selfPID)
            guard let self, self.revision == revision else { return }
            self.snapshot = ProcessQuery.sorted(entries)
            self.signalledPIDs = []
            self.state = .ready
            self.applyQuery()
            self.sampleTask = nil
            onLoaded?()
        }
    }

    func reset() {
        revision &+= 1
        sampleTask?.cancel()
        sampleTask = nil
        state = .idle
        snapshot = []
        filtered = []
        signalledPIDs = []
        query = ""
    }

    func filter(_ query: String) {
        self.query = query
        applyQuery()
    }

    func markSignalled(_ pid: Int32) {
        signalledPIDs.insert(pid)
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
