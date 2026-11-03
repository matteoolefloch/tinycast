import Foundation

@main
@MainActor
struct KillProcessTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func entry(
        _ pid: Int32, name: String = "proc", path: String = "/usr/bin/proc", cpu: Double = 0,
        memory: Int64 = 0
    ) -> ProcessEntry {
        ProcessEntry(
            pid: pid, name: name, path: path, cpuPercent: cpu, memoryBytes: memory,
            isOwnedByUser: true, startTime: 1, bundleURL: nil, iconStamp: 0, isApplication: false)
    }

    static func main() async {
        parsing()
        parsingRejects()
        listing()
        bundles()
        names()
        ordering()
        ranking()
        outcomes()
        administratorCommand()
        await sessionPublishes()
        await sessionDiscardsStaleSamples()
        await sessionKeepsSignalledRows()
        identityGuard()

        print(failures == 0 ? "Kill process tests passed" : "\(failures) kill process tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func parsing() {
        let output = """
              812   501  12.5  204800 /Applications/Safari.app/Contents/MacOS/Safari
              90     0   0.0    1024 /usr/libexec/logd
             4411   501   3,2     512 /Applications/My App.app/Contents/MacOS/My App
            """
        let samples = ProcessListParser.parse(output)
        expect(samples.count == 3, "every well-formed line becomes a sample")
        expect(samples.first?.pid == 812, "the pid is the first column")
        expect(samples.first?.uid == 501, "the uid is the second column")
        expect(samples.first?.cpuPercent == 12.5, "the CPU share is the third column")
        expect(samples.first?.memoryBytes == 204_800 * 1024, "RSS arrives in kilobytes")
        expect(samples[1].uid == 0, "a root process keeps uid 0")
        expect(
            samples[2].command == "/Applications/My App.app/Contents/MacOS/My App",
            "a path with spaces survives whole, since the command is the line's remainder")
        expect(samples[2].cpuPercent == 3.2, "a comma decimal still parses")
    }

    static func parsingRejects() {
        expect(ProcessListParser.parse(line: "") == nil, "a blank line is no process")
        expect(ProcessListParser.parse(line: "  12  501  0.0") == nil, "a short line is no process")
        expect(
            ProcessListParser.parse(line: "abc 501 0.0 10 /bin/x") == nil,
            "a non-numeric pid is no process")
        expect(
            ProcessListParser.parse(line: "  12  501  0.0  10   ") == nil,
            "a process with no command is no process")
    }

    static func listing() {
        expect(!ProcessListParser.isListed(pid: 0, selfPID: 500), "kernel_task is never offered")
        expect(!ProcessListParser.isListed(pid: 1, selfPID: 500), "launchd is never offered")
        expect(!ProcessListParser.isListed(pid: 500, selfPID: 500), "Tinycast never lists itself")
        expect(ProcessListParser.isListed(pid: 501, selfPID: 500), "any other process is offered")
    }

    static func bundles() {
        expect(
            ProcessEntry.bundlePath(forExecutable: "/Applications/Safari.app/Contents/MacOS/Safari")
                == "/Applications/Safari.app",
            "an app's executable belongs to its bundle")
        let helper =
            "/Applications/Chrome.app/Contents/Frameworks/C.framework/Helpers/Chrome Helper.app/Contents/MacOS/Chrome Helper"
        expect(
            ProcessEntry.bundlePath(forExecutable: helper)
                == "/Applications/Chrome.app/Contents/Frameworks/C.framework/Helpers/Chrome Helper.app",
            "a nested helper app wins over its host")
        expect(
            ProcessEntry.bundlePath(forExecutable: "/usr/sbin/cfprefsd") == nil,
            "a bare binary has no bundle")
        expect(
            ProcessEntry.bundlePath(forExecutable: "/opt/apps/notreally.application/bin/x") == nil,
            "only a real .app component counts")
    }

    static func names() {
        expect(
            ProcessEntry.displayName(forExecutable: "/usr/sbin/cfprefsd") == "cfprefsd",
            "the last component names it")
        expect(ProcessEntry.displayName(forExecutable: "-zsh") == "-zsh", "a bare command is its own name")
    }

    static func ordering() {
        let sorted = ProcessQuery.sorted([
            entry(10, name: "b", cpu: 1, memory: 10),
            entry(11, name: "a", cpu: 50, memory: 1),
            entry(12, name: "c", cpu: 1, memory: 99),
            entry(13, name: "a", cpu: 1, memory: 10)
        ])
        expect(sorted.map(\.pid) == [11, 12, 13, 10], "CPU first, then memory, then name")
    }

    static func ranking() {
        let entries = [
            entry(4242, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari"),
            entry(77, name: "node", path: "/opt/homebrew/bin/node"),
            entry(42, name: "Safari Networking", path: "/System/Library/Safari Networking")
        ]
        expect(ProcessQuery.rank(entries, for: "").count == 3, "an empty query lists everything")
        expect(ProcessQuery.rank(entries, for: "node").first?.pid == 77, "a name finds its process")
        expect(ProcessQuery.rank(entries, for: "42").first?.pid == 42, "a typed PID ranks its process first")
        expect(ProcessQuery.rank(entries, for: "zzzz").isEmpty, "an unrelated query finds nothing")
        expect(
            ProcessQuery.rank(entries, for: "homebrew").first?.pid == 77,
            "the path finds a process too")
    }

    static func outcomes() {
        expect(ProcessKillOutcome.from(killResult: 0, errno: 0) == .signalled, "zero is a sent signal")
        expect(ProcessKillOutcome.from(killResult: -1, errno: ESRCH) == .gone, "ESRCH means it exited")
        expect(
            ProcessKillOutcome.from(killResult: -1, errno: EPERM) == .notPermitted,
            "EPERM means another user owns it")
        expect(
            ProcessKillOutcome.from(killResult: -1, errno: EINVAL) == .failed(errno: EINVAL),
            "anything else is reported as it is")
        expect(ProcessSignal.terminate.number == SIGTERM, "Kill sends SIGTERM")
        expect(ProcessSignal.forceKill.number == SIGKILL, "Force Kill sends SIGKILL")
    }

    static func administratorCommand() {
        let command = AdministratorKillCommand.make(
            signal: SIGKILL, pid: 812, stamp: " Sat Oct 31 10:22:01 2026 ")
        expect(
            command
                == "LC_ALL=C /bin/ps -o lstart= -p 812 | /usr/bin/grep -qF 'Sat Oct 31 10:22:01 2026' && /bin/kill -9 812",
            "the root line re-checks the stamp before it kills")
        expect(
            AdministratorKillCommand.make(signal: SIGTERM, pid: 1, stamp: "Sat' ; rm -rf ~ ; '") == nil,
            "a stamp that could leave its quotes is refused")
        expect(
            AdministratorKillCommand.make(signal: SIGTERM, pid: 1, stamp: "  ") == nil,
            "an empty stamp is refused")
    }

    /// Hands each load its own entries after its own delay, so supersession is deterministic.
    static func session(_ batches: [(delay: Duration, entries: [ProcessEntry])]) -> KillProcessSession {
        let queue = BatchQueue(batches)
        return KillProcessSession { _, _ in
            let batch = queue.next()
            // Detached, so a superseding load's cancel cannot cut the delay short.
            await Task.detached { try? await Task.sleep(for: batch.delay) }.value
            return batch.entries
        }
    }

    static func loaded(_ session: KillProcessSession) async {
        await withCheckedContinuation { continuation in
            session.load { continuation.resume() }
        }
    }

    static func sessionPublishes() async {
        let session = session([(.zero, [entry(10, cpu: 1), entry(11, cpu: 9)])])
        await loaded(session)
        expect(session.state == .ready, "a landed sample is ready")
        expect(session.filtered.map(\.pid) == [11, 10], "a landed sample is CPU-sorted")
    }

    static func sessionDiscardsStaleSamples() async {
        let reset = session([(.milliseconds(50), [entry(10)])])
        reset.load()
        reset.reset()
        try? await Task.sleep(for: .milliseconds(150))
        expect(reset.snapshot.isEmpty && reset.state == .idle, "a sample landing after a reset is dropped")

        let superseded = session([(.milliseconds(80), [entry(10)]), (.zero, [entry(20)])])
        superseded.load()
        try? await Task.sleep(for: .milliseconds(20))
        await loaded(superseded)
        try? await Task.sleep(for: .milliseconds(150))
        expect(superseded.snapshot.map(\.pid) == [20], "an older sample never overwrites a newer one")
    }

    static func sessionKeepsSignalledRows() async {
        let session = session([(.zero, [entry(10), entry(11)]), (.zero, [entry(11)])])
        await loaded(session)
        session.markSignalled(10)
        expect(session.filtered.map(\.pid) == [10, 11], "a killed row stays, so the next row never slides up")
        expect(session.signalledPIDs == [10], "the killed row is marked")
        await loaded(session)
        expect(session.signalledPIDs.isEmpty, "a fresh sample clears the marks")
    }

    /// Signals only a child this harness started, so nothing the machine shares is touched.
    static func identityGuard() {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        guard (try? child.run()) != nil, let started = ProcessSampler.startTime(of: child.processIdentifier)
        else {
            expect(false, "the harness could start its own child")
            return
        }
        func target(startTime: Int64) -> ProcessEntry {
            ProcessEntry(
                pid: child.processIdentifier, name: "sleep", path: "/bin/sleep", cpuPercent: 0,
                memoryBytes: 0, isOwnedByUser: true, startTime: startTime, bundleURL: nil, iconStamp: 0,
                isApplication: false)
        }
        expect(
            ProcessKiller.send(.terminate, to: target(startTime: started - 1)) == .gone,
            "a PID whose start stamp moved is treated as gone")
        expect(child.isRunning, "and it is never signalled")
        expect(
            ProcessKiller.send(.terminate, to: target(startTime: started)) == .signalled,
            "a match is signalled")
        child.waitUntilExit()
        expect(child.terminationReason == .uncaughtSignal, "SIGTERM ended the child")
        expect(
            ProcessKiller.send(.terminate, to: target(startTime: started)) == .gone, "an exited PID is gone")
    }
}

/// Batches handed out in load order; locked because the operations run off the main actor.
final class BatchQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [(delay: Duration, entries: [ProcessEntry])]

    init(_ batches: [(delay: Duration, entries: [ProcessEntry])]) { self.batches = batches }

    func next() -> (delay: Duration, entries: [ProcessEntry]) {
        lock.withLock { batches.isEmpty ? (.zero, []) : batches.removeFirst() }
    }
}
