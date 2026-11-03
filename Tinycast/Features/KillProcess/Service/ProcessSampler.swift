import Darwin
import Foundation

/// One pass over every process: `ps` is setuid, so it sees other users' CPU and memory.
enum ProcessSampler {
    /// What `NSRunningApplication` knows, read on the main actor and handed in.
    struct Application: Sendable {
        let name: String
        let bundleURL: URL?
        let isRegular: Bool
    }

    @concurrent
    static func sample(applications: [Int32: Application], selfPID: Int32) async -> [ProcessEntry] {
        guard let output = runPS() else { return [] }
        let userID = getuid()
        var stamps: [URL: Int] = [:]
        return ProcessListParser.parse(output).compactMap { sample in
            guard ProcessListParser.isListed(pid: sample.pid, selfPID: selfPID),
                let started = startTime(of: sample.pid)
            else { return nil }
            let path = executablePath(of: sample.pid) ?? sample.command
            let application = applications[sample.pid]
            let bundleURL =
                application?.bundleURL
                ?? ProcessEntry.bundlePath(forExecutable: path).map { URL(fileURLWithPath: $0) }
            var iconStamp = 0
            if let bundleURL {
                if let known = stamps[bundleURL] {
                    iconStamp = known
                } else {
                    iconStamp = FileIconStamp.value(for: bundleURL)
                    stamps[bundleURL] = iconStamp
                }
            }
            return ProcessEntry(
                pid: sample.pid,
                name: application?.name ?? ProcessEntry.displayName(forExecutable: path),
                path: path, cpuPercent: sample.cpuPercent, memoryBytes: sample.memoryBytes,
                isOwnedByUser: sample.uid == userID, startTime: started, bundleURL: bundleURL,
                iconStamp: iconStamp, isApplication: application?.isRegular ?? false)
        }
    }

    /// Microseconds since the epoch; nil once the PID names no process at all.
    static func startTime(of pid: Int32) -> Int64? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Int64(start.tv_sec) * 1_000_000 + Int64(start.tv_usec)
    }

    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(bytes: buffer.prefix(Int(length)), encoding: .utf8)
    }

    /// Read before the wait: the listing outgrows a pipe's buffer, which would stall `ps` mid-write.
    private static func runPS() -> String? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ProcessListParser.arguments
        process.environment = ["LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard let exit = try? process.runObservingExit() else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        exit.wait()
        guard process.terminationStatus == 0 else { return nil }
        return (String(bytes: data, encoding: .utf8) ?? "")
    }
}
