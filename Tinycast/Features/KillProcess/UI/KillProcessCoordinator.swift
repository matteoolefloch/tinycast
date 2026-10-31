import AppKit

@MainActor
final class KillProcessCoordinator {
    private let session: KillProcessSession
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(session: KillProcessSession, paletteCoordinator: PaletteCoordinator, core: AppCore) {
        self.session = session
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func show() {
        paletteCoordinator.togglePalette(mode: .killProcess)
    }

    /// Every open samples anew, a restore included: hiding dropped the last snapshot.
    func load() {
        session.load()
    }

    /// The palette stays up after a kill, so a runaway family can be cleared one row at a time.
    func kill(_ entry: ProcessEntry, with signal: ProcessSignal) {
        switch ProcessKiller.send(signal, to: entry) {
        case .signalled:
            session.remove(entry.pid)
            core.showMessage(String(localized: "Killed \(entry.name)"))
        case .gone:
            session.remove(entry.pid)
            core.showMessage(String(localized: "\(entry.name) is no longer running"), tone: .neutral)
        case .notPermitted:
            Task { await self.killAsAdministrator(entry, with: signal) }
        case .failed(let code):
            Task { await self.reportFailure(entry, detail: String(cString: strerror(code))) }
        }
    }

    func copyName(_ entry: ProcessEntry) {
        Paster.copyPlainText(entry.name)
        core.showMessage(String(localized: "Copied name"))
    }

    func copyPath(_ entry: ProcessEntry) {
        Paster.copyPlainText(entry.path)
        core.showMessage(String(localized: "Copied path"))
    }

    func copyPID(_ entry: ProcessEntry) {
        Paster.copyPlainText(String(entry.pid))
        core.showMessage(String(localized: "Copied PID"))
    }

    /// The bundle when there is one: Finder selecting a binary deep inside `Contents` reads as noise.
    func showInFinder(_ entry: ProcessEntry) {
        guard let url = revealURL(for: entry) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(url)
    }

    func canShowInFinder(_ entry: ProcessEntry) -> Bool { revealURL(for: entry) != nil }

    private func revealURL(for entry: ProcessEntry) -> URL? {
        if let bundleURL = entry.bundleURL { return bundleURL }
        return entry.path.hasPrefix("/") ? URL(fileURLWithPath: entry.path) : nil
    }

    private func killAsAdministrator(_ entry: ProcessEntry, with signal: ProcessSignal) async {
        let confirmed = await core.confirm(
            title: String(localized: "Kill “\(entry.name)” as Administrator?"),
            message: String(
                localized: "It belongs to another user, so macOS asks for an administrator password."),
            symbol: "xmark.octagon", confirmTitle: String(localized: "Kill as Administrator"))
        guard confirmed else { return }
        switch await ProcessKiller.sendAsAdministrator(signal, to: entry) {
        case .signalled:
            session.remove(entry.pid)
            core.showMessage(String(localized: "Killed \(entry.name)"))
        case .gone:
            session.remove(entry.pid)
            core.showMessage(String(localized: "\(entry.name) is no longer running"), tone: .neutral)
        case .cancelled:
            break
        case .failed(let detail):
            await reportFailure(entry, detail: detail)
        }
    }

    private func reportFailure(_ entry: ProcessEntry, detail: String) async {
        await core.showNotice(
            title: String(localized: "Couldn’t Kill “\(entry.name)”"), message: detail,
            symbol: "xmark.octagon", tone: .danger)
    }
}
