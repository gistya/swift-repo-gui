import AppKit
import SwiftUI

/// Live editor for the app theme. Everything here writes into `AppStyleStore`, which the whole UI
/// reads — so edits re-theme the app (including this tab) instantly. The "Follow System / Dark /
/// Light" switcher chooses which appearance you're editing, so you can tune Light while on a Dark Mac.
struct StyleView: View {
    @Bindable private var store = AppStyleStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                appearanceSection
                colorsSection
                gradientSection
                fontsSection
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(TerminalBackground().ignoresSafeArea())
        .terminalText()
        .navigationTitle("Style")
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        GroupBox("Appearance") {
            VStack(alignment: .leading, spacing: 8) {
                appearanceSwitcher

                Text(store.effectiveLight
                     ? "Editing the Light theme. It auto-applies whenever macOS is in Light Mode."
                     : "Editing the Dark theme. It's the default retro-terminal look.")
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.terminalGreen.opacity(0.75))
            }
            .padding(.vertical, 4)
        }
    }

    /// A themed replacement for the stock segmented control so its font and background follow the
    /// `switcherName` / `styleSwitcher` theme settings.
    private var appearanceSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(StylePreview.allCases) { option in
                let isOn = store.preview == option
                Text(option.title)
                    .font(.switcher(size: 12, weight: isOn ? .bold : .regular))
                    .foregroundStyle(isOn ? Color.terminalBlack : Color.terminalGreen.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isOn {
                            RoundedRectangle(cornerRadius: 6).fill(Color.terminalGreen)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.preview = option }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { store.preview = option }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.styleSwitcherBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.terminalGreen.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance to edit")
    }

    // MARK: Colors

    private var colorsSection: some View {
        GroupBox("Colors") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Randomize Colors 🎲") { store.randomizeActiveColors() }
                        .accessibilityHint("Sets every color to a random value.")
                    Button(store.effectiveLight ? "Reset to Light Preset" : "Reset to Dark Preset") {
                        store.resetActiveToPreset()
                    }
                    .accessibilityHint("Restores this appearance's built-in colors.")
                    Spacer(minLength: 0)
                }
                .font(.monaco(size: 12, weight: .bold))

                colorRow("Background", \.colors.terminalBlack)
                colorRow("Terminal Green (primary)", \.colors.terminalGreen)
                colorRow("Dim Green", \.colors.terminalDimGreen)
                colorRow("LCD Green", \.colors.lcdGreen)
                colorRow("Accent Orange", \.colors.swiftOrange)
                colorRow("Failure Red", \.colors.failureRed)
                colorRow("Button Top", \.colors.buttonTop)
                colorRow("Button Bottom", \.colors.buttonBottom)
                colorRow("Logo Shadow", \.colors.logoShadow)
                colorRow("Tab Bar Background", \.colors.tabBar)
                colorRow("Tab Fill", \.colors.tab)
                colorRow("Switcher Background", \.colors.styleSwitcher)
                colorRow("LED Background", \.colors.ledBackground)
                colorRow("Control Surface", \.colors.controlSurface)
                colorRow("Toggle Background", \.colors.toggleTint)
                colorRow("Toggle Button", \.colors.toggleThumb)
            }
            .padding(.vertical, 4)
        }
    }

    private func colorRow(_ label: LocalizedStringKey, _ keyPath: WritableKeyPath<AppStyle, StyleColor>) -> some View {
        ColorPicker(selection: colorBinding(keyPath), supportsOpacity: true) {
            Text(label)
                .font(.monaco(size: 12))
                .foregroundStyle(Color.terminalGreen)
        }
        .accessibilityLabel(label)
    }

    // MARK: Top-bar gradient

    /// One color well per brushed-metal stop (top → bottom). Stop positions are structural, so only the
    /// colors are editable.
    private var gradientSection: some View {
        GroupBox("Top Bar Gradient") {
            VStack(alignment: .leading, spacing: 10) {
                let stops = store.activeStyle.gradients.metalStops
                ForEach(Array(stops.indices), id: \.self) { i in
                    ColorPicker(selection: colorBinding(\.gradients.metalStops[i].color), supportsOpacity: true) {
                        Text("Gradient Stop \(i + 1)")
                            .font(.monaco(size: 12))
                            .foregroundStyle(Color.terminalGreen)
                    }
                    .accessibilityLabel("Gradient stop \(i + 1)")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Fonts

    private var fontsSection: some View {
        GroupBox("Fonts & Sizes") {
            VStack(alignment: .leading, spacing: 10) {
                fontPicker("Monospace font", \.fonts.monospaceName)
                fontPicker("LCD font", \.fonts.lcdName)
                fontPicker("Switcher font", \.fonts.switcherName)
                sizeStepper("Default text size", \.fonts.defaultSize, range: 9...20)
                sizeStepper("Small text size", \.fonts.smallSize, range: 8...16)
                sizeStepper("Title size", \.fonts.titleSize, range: 14...40)
            }
            .padding(.vertical, 4)
        }
    }

    /// A popup listing every installed font family. Built from `Menu` + a custom label (not `Picker`)
    /// so the color and background are actually themeable — a `.menu` Picker renders as a native
    /// `NSPopUpButton` that ignores `foregroundStyle`/`background`.
    private func fontPicker(_ label: LocalizedStringKey, _ keyPath: WritableKeyPath<AppStyle, String>) -> some View {
        let selection = binding(keyPath)
        return HStack {
            Text(label).font(.monaco(size: 12)).frame(width: 160, alignment: .leading)
            Menu {
                ForEach(SystemFonts.families(including: selection.wrappedValue), id: \.self) { family in
                    Button { selection.wrappedValue = family } label: {
                        if family == selection.wrappedValue {
                            Label(family, systemImage: "checkmark")
                        } else {
                            Text(family)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.wrappedValue)
                        .font(.custom(selection.wrappedValue, size: 13))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                }
                .foregroundStyle(Color.terminalGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.tabBarBackground))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.terminalGreen.opacity(0.35), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: 280, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(selection.wrappedValue)
    }

    private func sizeStepper(_ label: LocalizedStringKey, _ keyPath: WritableKeyPath<AppStyle, Double>, range: ClosedRange<Double>) -> some View {
        let value = binding(keyPath)
        return Stepper(value: value, in: range, step: 1) {
            HStack {
                Text(label).font(.monaco(size: 12)).frame(width: 160, alignment: .leading)
                Text("\(Int(value.wrappedValue)) pt")
                    .font(.monaco(size: 12, weight: .bold))
                    .foregroundStyle(Color.terminalGreen)
                    .backgroundStyle(Color.tabBarBackground)
            }
        }
        .accessibilityValue("\(Int(value.wrappedValue)) points")
    }

    // MARK: Bindings into the active style

    private func binding<Value>(_ keyPath: WritableKeyPath<AppStyle, Value>) -> Binding<Value> {
        Binding(
            get: { AppStyleStore.shared.activeStyle[keyPath: keyPath] },
            set: {
                var style = AppStyleStore.shared.activeStyle
                style[keyPath: keyPath] = $0
                AppStyleStore.shared.activeStyle = style
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<AppStyle, StyleColor>) -> Binding<Color> {
        Binding(
            get: { Color(AppStyleStore.shared.activeStyle[keyPath: keyPath]) },
            set: {
                var style = AppStyleStore.shared.activeStyle
                style[keyPath: keyPath] = StyleColor($0)
                AppStyleStore.shared.activeStyle = style
            }
        )
    }
}

/// Installed font families, fetched once. `availableFontFamilies` is a cheap cached lookup, but this
/// avoids re-sorting it on every re-render.
@MainActor
private enum SystemFonts {
    static let all: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    /// Guarantee the current selection is in the list so the popup shows it even when it's a bundled
    /// font (e.g. the LCD face) whose family name isn't among the system families.
    static func families(including current: String) -> [String] {
        all.contains(current) ? all : [current] + all
    }
}
