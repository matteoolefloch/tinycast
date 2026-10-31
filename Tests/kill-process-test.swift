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

    static func main() {
        parsing()
        parsingRejects()
        listing()
        bundles()
        names()
        ordering()
        ranking()
        outcomes()

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
}
