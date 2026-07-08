nonisolated enum SwiftBuilderStyle {
    /// The live style. Now dynamic: it reads the observable `AppStyleStore`, so changing colors/fonts
    /// (or switching to the Light preset) re-themes the whole UI. `Color.terminalGreen` &c. and the
    /// `.monaco` fonts route through here, so nothing at the call sites had to change.
    static var current: AppStyle { AppStyleStore.shared.current }
}
