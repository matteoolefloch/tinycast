import SwiftUI

struct KillProcessScreen: PaletteScreen {
    let session: KillProcessSession
    let core: AppCore

    var rows: [ProcessEntry] { session.filtered }

    var primaryActionTitle: String { String(localized: "Kill Process") }

    private func entry(at selection: Int) -> ProcessEntry? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasActions(at selection: Int) -> Bool { entry(at: selection) != nil }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else { return nil }
        let coordinator = core.killProcessCoordinator
        var items = [
            PopoverMenuItem(
                title: String(localized: "Kill Process"), systemImage: "xmark.octagon",
                shortcut: "↵", isDestructive: true
            ) {
                coordinator.kill(entry, with: .terminate)
            },
            PopoverMenuItem(
                title: String(localized: "Force Kill Process"), systemImage: "bolt.horizontal.circle",
                shortcut: "⌘↵", isDestructive: true
            ) {
                coordinator.kill(entry, with: .forceKill)
            },
            PopoverMenuItem(
                title: String(localized: "Copy Name"), systemImage: "doc.on.doc", startsSection: true,
                shortcut: "⌥⌘C"
            ) {
                coordinator.copyName(entry)
            },
            PopoverMenuItem(
                title: String(localized: "Copy Path"), systemImage: "folder", shortcut: "⌃⌘C"
            ) {
                coordinator.copyPath(entry)
            },
            PopoverMenuItem(title: String(localized: "Copy PID"), systemImage: "number") {
                coordinator.copyPID(entry)
            }
        ]
        if coordinator.canShowInFinder(entry) {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Show in Finder"), systemImage: "finder", shortcut: "⌘F"
                ) {
                    coordinator.showInFinder(entry)
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Reload Processes"), systemImage: "arrow.clockwise",
                startsSection: true, shortcut: "⌘R"
            ) {
                coordinator.load()
            })
        return PopoverMenuContent(header: entry.name, items: items)
    }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        core.killProcessCoordinator.kill(entry, with: .terminate)
    }

    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        core.killProcessCoordinator.kill(entry, with: .forceKill)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        let coordinator = core.killProcessCoordinator
        if shortcut == .restart {
            coordinator.load()
            return true
        }
        guard let entry = entry(at: selection) else { return false }
        switch shortcut {
        case .copyName: coordinator.copyName(entry)
        case .copyPath: coordinator.copyPath(entry)
        case .showInFinder:
            guard coordinator.canShowInFinder(entry) else { return false }
            coordinator.showInFinder(entry)
        default: return false
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if session.state == .loading {
            EmptyResults(text: String(localized: "Reading processes…"))
        } else if rows.isEmpty {
            EmptyResults(text: String(localized: "No processes found"))
        } else {
            KillProcessList(
                entries: rows,
                selectedID: entry(at: selection)?.id,
                scroll: scroll,
                onActivate: { core.killProcessCoordinator.kill($0, with: .terminate) })
        }
    }
}
