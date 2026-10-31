import SwiftUI

struct KillProcessList: View {

    @Environment(\.metrics) private var metrics
    let entries: [ProcessEntry]
    let selectedID: ProcessEntry.ID?
    let scroll: ScrollIntent
    let onActivate: (ProcessEntry) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == entries.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        KillProcessRow(entry: entry, selected: entry.id == selectedID)
                            .selectionFrame(entry.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(entry) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct KillProcessRow: View {

    @Environment(\.metrics) private var metrics
    let entry: ProcessEntry
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var cpu: String {
        String(
            localized:
                "\(entry.cpuPercent.formatted(.number.precision(.fractionLength(1))))% CPU")
    }

    private var memory: String {
        entry.memoryBytes.formatted(.byteCount(style: .memory))
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let bundleURL = entry.bundleURL {
                    EntryIconView(source: .file(stamp: entry.iconStamp), fileURL: bundleURL)
                } else {
                    EntryIconView(source: .symbol("terminal"))
                }
            }
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(entry.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .layoutPriority(1)
            HStack(spacing: metrics.spacing.xxs) {
                if !entry.isOwnedByUser { Image(systemName: "lock.fill") }
                Text(String(entry.pid))
            }
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            Text(cpu)
                .font(metrics.typography.rowTrailing.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(memory)
                .font(metrics.typography.rowTrailing.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .help(entry.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.name)
        .accessibilityValue(Text(verbatim: "\(cpu), \(memory)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
