import Foundation

enum ProcessKillOutcome: Equatable, Sendable {
    case signalled
    /// Exited, or its PID now names a different process, before the signal was sent.
    case gone
    /// Another user's process: only an administrator may signal it.
    case notPermitted
    case failed(errno: Int32)

    /// `kill(2)`'s answer, read once so the coordinator never inspects `errno` itself.
    static func from(killResult: Int32, errno code: Int32) -> Self {
        guard killResult != 0 else { return .signalled }
        switch code {
        case ESRCH: return .gone
        case EPERM: return .notPermitted
        default: return .failed(errno: code)
        }
    }
}

enum ProcessSignal: Sendable {
    /// SIGTERM: the process may clean up, and may refuse.
    case terminate
    /// SIGKILL: cannot be caught, so nothing is saved.
    case forceKill

    var number: Int32 {
        switch self {
        case .terminate: SIGTERM
        case .forceKill: SIGKILL
        }
    }
}
