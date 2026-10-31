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

    /// macOS draws the password prompt; the script holds only two integers, so nothing is injectable.
    @concurrent
    static func sendAsAdministrator(
        _ signal: ProcessSignal, to entry: ProcessEntry
    ) async -> AdministratorOutcome {
        guard ProcessSampler.startTime(of: entry.pid) == entry.startTime else { return .gone }
        let command = "/bin/kill -\(signal.number) \(entry.pid)"
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
        let detail = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.contains(userCancelledCode) ? .cancelled : .failed(detail)
    }
}
