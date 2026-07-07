import SwiftData
import SwiftUI
import SwiftXStateSwiftUI

struct SaveProfileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var profileName: String
    @Binding var showSaveSheet: Bool
    let settings: MachineStore<BuildSettingsMachine>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Build Profile")
                .font(.monaco(size: 18, weight: .bold))
                .accessibilityAddTraits(.isHeader)
                .foregroundStyle(Color.terminalGreen)
            
            TextField("Profile name", text: $profileName)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(Color.terminalGreen)
                .accessibilityLabel("Profile name")
                .accessibilityHint("Enter a name for this build settings profile.")
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    showSaveSheet = false
                }
                .foregroundStyle(Color.terminalGreen)
                .accessibilityLabel("Cancel")
                .accessibilityHint("Dismisses the sheet without saving.")
                .buttonStyle(RetroMetalButtonStyle())

                Button("Save") {
                    let profile = SavedBuildProfile(name: profileName, options: settings.context.options)
                    modelContext.insert(profile)
                    profileName = ""
                    showSaveSheet = false
                }
                .buttonStyle(RetroMetalButtonStyle())
                .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Save")
                .accessibilityHint("Saves the current build settings under this name.")
            }
        }
        .padding()
        .frame(width: 360)
        .background(TerminalBackground())
    }
}

#Preview {
    SaveProfileSheet(profileName: .constant("ProfileName"), showSaveSheet: .constant(true), settings: MachineStore(BuildSettingsMachine()))
}
