import Darwin
import Foundation

/// Sends signals, and nothing else. Every send first proves the PID still names the sampled process.
enum ProcessKiller {
    enum AdministratorOutcome: Equatable, Sendable {
        case signalled
        case gone
        case cancelled
        case failed(String)
    }

    /// AppleScript's `userCanceledErr`, which is what dismissing the password prompt reports.
    private static let userCancelledCode = "-128"

    static func send(_ signal: ProcessSignal, to entry: ProcessEntry) -> ProcessKillOutcome {
        guard ProcessSampler.startTime(of: entry.pid) == entry.startTime else { return .gone }
        let result = kill(entry.pid, signal.number)
        return .from(killResult: result, errno: errno)
    }

    /// macOS draws the password prompt; the script carries integers and a vetted stamp, nothing else.
    @concurrent
    static func sendAsAdministrator(
        _ signal: ProcessSignal, to entry: ProcessEntry
    ) async -> AdministratorOutcome {
        guard ProcessSampler.startTime(of: entry.pid) == entry.startTime,
            let stamp = launchStamp(of: entry.pid),
            let command = AdministratorKillCommand.make(
                signal: signal.number, pid: entry.pid, stamp: stamp)
        else { return .gone }
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(command)\" with administrator privileges"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        guard let exit = try? process.runObservingExit() else {
            return .failed(String(localized: "The administrator prompt couldn’t open."))
        }
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        exit.wait()
        guard process.terminationStatus != 0 else { return .signalled }
        if ProcessSampler.startTime(of: entry.pid) != entry.startTime { return .gone }
        let detail = (String(bytes: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.contains(userCancelledCode) { return .cancelled }
        return .failed(detail.isEmpty ? String(localized: "The administrator command failed.") : detail)
    }

    /// `ps`'s own spelling of the start, so the root shell can compare it without parsing a date.
    private static func launchStamp(of pid: Int32) -> String? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = AdministratorKillCommand.stampArguments + [String(pid)]
        process.environment = ["LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard let exit = try? process.runObservingExit() else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        exit.wait()
        guard process.terminationStatus == 0 else { return nil }
        return (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
