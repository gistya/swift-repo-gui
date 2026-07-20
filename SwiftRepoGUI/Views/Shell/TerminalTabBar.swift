import SwiftUI

struct TerminalTabBar: View {
    let sections: [AppSectionID]
    let selected: AppSectionID
    let onSelect: (AppSectionID) -> Void
    let onDetach: (AppSectionID) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(sections) { section in
                TerminalTabButton(
                    section: section,
                    isSelected: section == selected,
                    onSelect: onSelect,
                    onDetach: onDetach
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 0)
        .background(Color.tabBarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.terminalGreen.opacity(0.35))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        // Group the tab buttons under one navigable container for VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Section tabs")
    }
}
