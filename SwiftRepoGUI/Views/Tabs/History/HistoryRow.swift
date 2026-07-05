import SwiftUI

struct HistoryRow: View {
    let operation: BuildOperationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: operation.kind.symbolName)
                    .accessibilityHidden(true)
                Text(operation.kind.title)
                    .font(.monaco(size: 13, weight: .bold))
                Spacer()
                statusBadge
            }
            Text(operation.createdAt, style: .date)
                .font(.monaco(size: 10))
                .foregroundStyle(Color.terminalGreen.opacity(0.75))
            if !operation.targetRepository.isEmpty {
                Text(operation.targetRepository)
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.terminalGreen.opacity(0.75))
            }
        }
        .padding(.vertical, 2)
        // Collapse the row into a single VoiceOver element that spells out the status
        // (which is otherwise conveyed only by the badge's color) alongside kind and date.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        let date = operation.createdAt.formatted(date: .abbreviated, time: .shortened)
        var parts = [operation.kind.title, operation.status.title]
        if !operation.targetRepository.isEmpty {
            parts.append(operation.targetRepository)
        }
        parts.append(date)
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var statusBadge: some View {
        let badgeColor = operation.status == .failed ? Color.terminalFailureRed : Color.terminalGreen
        Text(operation.status.title)
            .font(.monaco(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
            // Status is carried by the combined row label (color alone is not enough for VoiceOver).
            .accessibilityHidden(true)
    }
}
