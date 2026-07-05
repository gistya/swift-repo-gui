import SwiftUI

struct HistoryRow: View {
    let operation: BuildOperationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: operation.kind.symbolName)
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
    }
}
