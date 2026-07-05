import SwiftXState

nonisolated enum ToolchainEvent: EventIdentifying {
    case load(String)                        // (re)parse the preset file at this path
    case updateDraft(ToolchainRecipeDraft)   // authoritative composition edit
    case loadRecipe(ToolchainRecipeDraft)    // load a saved recipe into the draft
    case newRecipe                           // reset the draft

    static var _blank: ToolchainEvent { .newRecipe }
}
