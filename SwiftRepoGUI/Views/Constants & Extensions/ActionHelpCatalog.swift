import SwiftUI

/// Context-rich "what it does / why you'd reach for it / how it differs" help for the app's
/// action buttons — the context a man page never gives. Generated from a reviewed content pass.
struct ActionHelpDescriptor: HelpDescribing, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let practicalAdvice: String
}

/// Build-setting descriptors already carry the same three fields, so they satisfy `HelpDescribing`.
extension BuildOptionDescriptor: HelpDescribing {}

enum ActionHelp {
    static func descriptor(for id: String) -> ActionHelpDescriptor? { catalog[id] }

    static let catalog: [String: ActionHelpDescriptor] = [
        "action.incrementalFrontend": ActionHelpDescriptor(
            id: "action.incrementalFrontend",
            title: "Rebuild Frontend Only",
            summary: "Runs `ninja bin/swift-frontend` in build/<subdir>/swift-macosx-arm64, relinking just the swift-frontend binary and the objects it depends on.",
            practicalAdvice: "Rung 1 of the build ladder (Frontend → Swift Repo → Entire Tree → Build-Script → Fresh Clean) and the button you live on during a tight edit/compile/debug loop when your change is confined to the compiler proper: Sema, the type checker, SILGen, the C++ SIL optimizer, IRGen, diagnostics. It links far less than rung 2 (Rebuild Swift Repo): no stdlib recompile, no SDK overlays, no sil-opt/swift-api-digester, so a one-file Sema edit relinks in seconds-to-a-minute. Step up to rung 2 the moment you touch something the frontend does NOT link but you need built — stdlib sources, the Swift-side optimizer in SwiftCompilerSources, or a separate tool binary — and note the trap shared by all three Ninja rungs: raw ninja trusts the existing CMake config, so a source file newly listed in a CMakeLists or a changed build setting is invisible until you drop to rung 4 (Run Build-Script) to reconfigure."
        ),
        "action.incrementalSwiftRepo": ActionHelpDescriptor(
            id: "action.incrementalSwiftRepo",
            title: "Rebuild Swift Repo",
            summary: "Runs `ninja` with no target in build/<subdir>/swift-macosx-arm64, building every default target of the swift repo: frontend, stdlib, overlays, and the compiler tools.",
            practicalAdvice: "Rung 2 of the ladder and the right default when your change reaches past the frontend binary but stays inside the swift repo — editing the standard library or SDK overlays, the Swift-implemented optimizer passes in SwiftCompilerSources, or needing auxiliary tools (sil-opt, swift-api-digester, lldb-moduleimport-test) that rung 1 never links. It is meaningfully slower than rung 1 because a stdlib touch re-compiles the standard library with your freshly built compiler, but still far cheaper than rung 3 (Rebuild Entire Tree), which drags in LLVM/Clang. Prefer this over rung 3 whenever LLVM/Clang are untouched — almost always — and over rung 4 (Run Build-Script) whenever the CMake config is already valid, since plain ninja skips build-script's per-run product orchestration and config regeneration."
        ),
        "action.incrementalEverything": ActionHelpDescriptor(
            id: "action.incrementalEverything",
            title: "Rebuild Entire Tree",
            summary: "Runs `ninja` with no target at build/<subdir>/ (the top of the unified build), rebuilding every product across all repos — LLVM, Clang, Swift, and the rest.",
            practicalAdvice: "Rung 3 of the ladder, needed only when your change actually crosses into LLVM or Clang: an LLVM IR/codegen tweak, a Clang-importer-adjacent header change, or a bumped llvm-project checkout the whole stack must rebuild against. A real LLVM edit forces a long LLVM/Clang recompile before Swift even starts, so don't reach here reflexively — if LLVM is clean, rung 2 (Rebuild Swift Repo) produces the identical Swift result for a fraction of the time. Like rungs 1–2 it is pure `ninja` and inherits the same stale-config trap: it will happily build against out-of-date generated CMake files, so if you added or moved sources or flipped a build flag, step up to rung 4 (Run Build-Script) so the configuration is regenerated first."
        ),
        "action.buildScript": ActionHelpDescriptor(
            id: "action.buildScript",
            title: "Run Build-Script",
            summary: "Invokes swift/utils/build-script (from the swift/ dir) with the flags from Settings — CMake configuration plus the full multi-product toolchain build — adding `--reconfigure` when that option is set.",
            practicalAdvice: "Rung 4 of the ladder: the canonical, blessed way to build the toolchain and the escape hatch from the Ninja rungs' central failure mode. When a raw `ninja` (rungs 1–3) silently builds against stale CMake — because you added a source file, changed a build variant (debug / release / RelWithDebInfo / assertions), or bumped a dependency — build-script re-runs CMake and reconciles the configuration for every product, which plain Ninja never does. Reach for it on the first build of a fresh checkout, after update-checkout pulls in changes, when you flip build options in Settings, or any time an incremental build fails in a config-mismatch way (missing symbols, targets Ninja claims don't exist, link errors after a rebase). It reconfigures and rebuilds in place rather than wiping, so it is far cheaper than rung 5 (Fresh Clean Build) — only escalate there when reconfigure alone can't dig you out."
        ),
        "action.freshBuild": ActionHelpDescriptor(
            id: "action.freshBuild",
            title: "Fresh Clean Build",
            summary: "Runs `build-script -c`, wiping the build directory first and rebuilding the whole toolchain from scratch with the configured Settings.",
            practicalAdvice: "Rung 5, the top of the ladder and the nuclear option: `-c` deletes build artifacts so everything, LLVM included, recompiles from zero — expect the better part of an hour on a laptop. Reserve it for what a rung-4 `--reconfigure` genuinely can't fix: a corrupted or half-written build dir, a CMake cache poisoned so badly reconfigure still misbehaves, a compiler/Xcode upgrade underneath you, or chasing a 'green on CI, red locally' ghost where you must eliminate stale state as a variable. Because it throws away all incremental progress it is the slowest path — always try rung 4 (Run Build-Script, reconfigure) first, and drop to fresh only when you specifically need a guaranteed-clean tree, e.g. before trusting benchmark numbers or a release-configuration validation run."
        ),
        "action.freshDependency": ActionHelpDescriptor(
            id: "action.freshDependency",
            title: "Fresh Dependency Rebuild",
            summary: "Runs `ninja -t clean` then a full `ninja` in the build dir of the single repo chosen in the Target Repository picker (swift if none), via one zsh command.",
            practicalAdvice: "A scalpel for when one component's Ninja state has gone stale or corrupt in a way an incremental build won't fix — CMake caches lying, or you rebased that one repo and want a clean object graph without nuking the whole toolchain. It wipes and rebuilds exactly one repo's ninja dir (only LLVM, or only swift), so it is dramatically cheaper than a rung-5 Fresh Clean Build that reconfigures and rebuilds every product. Gotcha: it clears only that repo's ninja artifacts, so it will NOT recover from a bad CMake configure (use Run Build-Script --reconfigure for that) and does not touch dependents — clean swift after LLVM headers changed and you still must rebuild LLVM first."
        ),
        "action.updateDependencies": ActionHelpDescriptor(
            id: "action.updateDependencies",
            title: "Update Dependencies",
            summary: "Runs update-checkout with the auto-resolved --scheme and --match-timestamp to move every sibling repo to the version matching your current swift commit, then refreshes the project.",
            practicalAdvice: "Run this after checking out a different swift branch/PR, or when a fresh pull moved the llvm-project pin and CI failed on an ABI/API mismatch you can't reproduce locally. --match-timestamp is the whole point: instead of fast-forwarding each sibling to its branch tip (which pairs your swift with an even-newer LLVM whose API the compiler doesn't yet call correctly, breaking the build), it checks out each sibling at the last commit dated at or before your swift HEAD's commit date, reconstructing the exact llvm-project/cmark/swift-syntax that swift commit was written against. The --scheme is inferred from your swift branch via swift/utils/update_checkout/update-checkout-config.json (its branch-schemes / default-branch-scheme keys, e.g. release/6.x or main), so per-branch repo pinning is respected. Don't run it when you haven't switched branches and the tree already builds — it just re-resolves repos to where they already are, and can surprise you by moving LLVM out from under a good build. Prefer Update & Rebuild Changed when you also want the changed repos rebuilt in one step."
        ),
        "action.updateAndRebuild": ActionHelpDescriptor(
            id: "action.updateAndRebuild",
            title: "Update & Rebuild Changed",
            summary: "Snapshots each repo's git revision, runs the same --match-timestamp update-checkout, diffs revisions to find which repos moved, then chains a ninja build for only those (bin/swift-frontend for swift).",
            practicalAdvice: "The everyday post-branch-switch button: it does what Update Dependencies does, then rebuilds precisely the repos the checkout actually moved — if only cmark shifted you rebuild cmark, and if nothing moved it short-circuits with 'All dependencies already matched the swift commit.' and builds nothing. That beats following update-checkout with a blind Rebuild Entire Tree or Run Build-Script, because ninja's own up-to-date check still walks and stats the entire graph of untouched repos, whereas this scopes the invocation to just the changed repos' build dirs up front. The revision diff is by commit hash before-vs-after, so it catches an LLVM bump you'd never notice by eye; gotcha: it rebuilds a changed repo but NOT its downstream dependents in the same run, so a big LLVM move that touches headers can leave swift needing a follow-up incremental build, and a dirty working tree that doesn't change HEAD is invisible to it."
        ),
        "action.cancel": ActionHelpDescriptor(
            id: "action.cancel",
            title: "Cancel Build",
            summary: "Sends the cancel event to the build state machine, terminating the running build-script/ninja process and marking the operation cancelled.",
            practicalAdvice: "Hit this the moment you realize the running config is wrong — wrong preset, `-R` when you wanted `-r`, forgot `--skip-build-benchmarks` — instead of waiting out a doomed multi-hour compiler build. A cancelled operation records exit code -1 and status 'Build cancelled.', deliberately distinguished from a real failure so it offers no Copy Failure Reason button and won't be misread as a compiler crash later in History. Gotcha: cancel stops the process but does NOT clean the build dir or undo a partial ninja link, so an incremental restart may pick up half-written objects; if you cancelled mid-CMake-reconfigure, prefer a Fresh Clean Build over a plain restart."
        ),
        "action.replay": ActionHelpDescriptor(
            id: "action.replay",
            title: "Replay Operation",
            summary: "Restores the recorded operation's project path, build subdir, target repo, and BuildOptions, then regenerates and runs a fresh build request from that snapshot.",
            practicalAdvice: "The fast path for 'run that exact build again' after you've since fiddled with Settings — it snaps every option back to the recorded state in one click instead of re-deriving a dozen build-script flags by hand and getting one wrong. Crucially it REGENERATES the command from the restored options against the current tree, so it is not a verbatim replay: if the checkout moved or the resolved checkout scheme changed, the actual argv can differ from the historical line (use Copy Command Line for the byte-for-byte original). It is disabled while a build is running, and unlike Import Operation it acts on a record already in your local History, not a file from someone else."
        ),
        "action.copyCommand": ActionHelpDescriptor(
            id: "action.copyCommand",
            title: "Copy Command Line",
            summary: "Copies the operation's exact shell command to the clipboard, prefixed with `cd <project-path> &&` unless the recorded line already contains a cd.",
            practicalAdvice: "Use this to drop into a real terminal and tweak something the GUI doesn't expose — add a one-off `--extra-cmake-options`, wrap the invocation in `lldb`/`rr`, prepend `caffeinate`, or splice it into a git-bisect run script. Because the copied string is already cd-wrapped and shell-quoted, it pastes and runs verbatim from any directory, which is exactly what you want when attaching a compiler repro to a bug report or Slack thread. Prefer this over Replay Operation when you need to modify flags or run outside the app; prefer Replay when you want to reproduce identically inside the GUI with progress tracking and a new History entry."
        ),
        "action.export": ActionHelpDescriptor(
            id: "action.export",
            title: "Export Operation",
            summary: "Writes the operation's kind, project path, build subdir, target repo, command line, full BuildOptions, and notes as JSON to a `.swiftbuildop` file in the Exports folder and reveals it in Finder.",
            practicalAdvice: "Export packages the reproducible essence of a build — the options snapshot and command, not the log tail or exit status — so a teammate can Import it and get byte-identical build settings without you dictating flags over chat. It is the right artifact to attach when filing a compiler bug ('here's the exact build that miscompiles') or handing off a bisect: the recipient replays your precise configuration against their own checkout. Note it is machine-portable only up to paths — the absolute project path travels inside the file, so an Import on a machine where that path doesn't exist fails validation until they repoint it. The file carries a `.swiftbuildop` extension even though its contents are plain JSON."
        ),
        "action.import": ActionHelpDescriptor(
            id: "action.import",
            title: "Import Operation",
            summary: "Opens a picker for a `.swiftbuildop` export, applies its project/settings, validates the project path, and inserts a new History record prefixed \"Imported:\".",
            practicalAdvice: "How you adopt a teammate's exact build configuration — reproducing a bug they saw, or standardizing on a shared preset — without hand-transcribing build-script flags. Import applies the settings AND validates the project path up front, so if the exported absolute path doesn't exist on your machine you get an immediate Import Error rather than a confusing failure three hours into a build. After a successful import the operation lands in History as a normal record, so the natural next step is to select it and hit Replay Operation; Import only stages the configuration, it does not start a build on its own."
        ),
        "action.copyFailureReason": ActionHelpDescriptor(
            id: "action.copyFailureReason",
            title: "Copy Failure Reason",
            summary: "Copies the build's failure status message to the clipboard.",
            practicalAdvice: "Appears only when the last build actually failed (non-zero exit) and was not a user cancellation, so its mere presence is a quick tell that something genuinely broke versus you having hit Cancel. Grab it to paste the top-line failure into a bug report or a search before you go spelunking in the full log — it's the summarized reason, not the raw ninja/compiler transcript, so for the actual error spew you still open the log file. It is deliberately hidden after a cancel (exit -1, 'Build cancelled.') because 'you stopped it' is not a failure reason worth copying."
        ),
        "action.openLogsFolder": ActionHelpDescriptor(
            id: "action.openLogsFolder",
            title: "Open Logs Folder",
            summary: "Opens ~/Library/Application Support/com.physicalsoftware.SwiftRepoGUI/logs/ in Finder, where every build writes one <operation-UUID>.log.",
            practicalAdvice: "Reach here to work with raw logs outside the app: grep across every build at once, tail -f a run, or pipe a log into a script. The in-app viewer holds only the newest 256 KB of a single log, so a full build-script or ninja log (easily hundreds of MB) lives in its entirety only here on disk. Files are named by UUID, not build kind, so sort by date or cross-reference the operation in History to find the right one; the folder is auto-created, so it opens even when empty."
        ),
        "action.openExportsFolder": ActionHelpDescriptor(
            id: "action.openExportsFolder",
            title: "Open Exports Folder",
            summary: "Opens the sibling exports/ directory (under the app's Application Support folder) holding the `.swiftbuildop` files produced by Export Operation.",
            practicalAdvice: "The pickup point for operation files you've exported to share, archive, or re-import on another machine (or attach to a bug report), kept separate from the logs/ folder that holds raw build output. Use it to grab the last export without re-running the export flow, or to diff two saved operation configs. Note it holds the serialized operation record (kind, BuildOptions, resolved checkout scheme) as JSON — not the build's log text."
        ),
        "action.openLog": ActionHelpDescriptor(
            id: "action.openLog",
            title: "Open Log in Editor",
            summary: "Opens this build's .log file in whatever app is registered for .log via NSWorkspace, falling back to the logs folder if the file doesn't exist yet.",
            practicalAdvice: "Prefer this over the in-app viewer the moment you need to actually search a long compiler build: your editor gives real find/regex, jump-to-error, and the whole file, whereas the embedded viewer shows only the trailing 256 KB with no search. Essential for hunting the FIRST error in a failed build-script run, since the earliest diagnostics have usually scrolled out of the in-app tail. Whichever app owns .log opens it (often Console or a plain-text editor) — retarget the extension via Finder's Get Info if it lands somewhere useless."
        ),
        "action.revealLog": ActionHelpDescriptor(
            id: "action.revealLog",
            title: "Reveal Log in Finder",
            summary: "Selects this build's .log file in Finder (activateFileViewerSelecting), falling back to opening the logs folder if the file isn't present.",
            practicalAdvice: "Use this instead of Open Log in Editor when you want the file object rather than its contents — to drag it onto a bug report or Slack, copy it, check its size before opening a giant log, or right-click into another tool. It pinpoints the exact UUID-named file among many, far faster than opening the logs folder and hunting by timestamp. If the build hasn't produced its log yet it degrades to just opening the logs folder, so a Finder window with nothing preselected means the file doesn't exist yet."
        ),
        "action.refreshLog": ActionHelpDescriptor(
            id: "action.refreshLog",
            title: "Refresh Log",
            summary: "Re-reads the log from disk into the viewer via the tail reader's reload(), pulling in newly written bytes and handling truncation/rotation.",
            practicalAdvice: "During a live build the viewer already follows the file through filesystem events, so you mainly need this after a build FINISHES — the watcher stops, and Refresh re-reads to capture the final flush (closing error summary, exit status) that landed after the last event. Also use it if the file was truncated or rotated out from under the viewer, since reload() detects a shrunk file and resets to the newest 256 KB rather than showing stale bytes. It never loads the full file — for the complete history use Open Log in Editor instead."
        ),
        "action.chooseProject": ActionHelpDescriptor(
            id: "action.chooseProject",
            title: "Choose Swift Project Root",
            summary: "Opens a folder picker to set the swift-project checkout root — the umbrella directory containing swift/ and build/ — that every build/test/update action resolves against.",
            practicalAdvice: "This is the anchor for the whole app: build-script is found at <root>/swift/utils/build-script, update-checkout at <root>/swift/utils/update-checkout, and ninja targets under <root>/build/<subdir>/swift-macosx-arm64. Point it at the umbrella checkout you cloned via `update-checkout --clone`, NOT at the inner swift/ repo — a common mistake that leaves the app unable to find the sibling repos (llvm-project, cmark, swift-syntax). If you keep several checkouts (a stable tree and a topic-branch tree), re-choosing here is how you switch which tree the buttons act on; the app derives all paths from this one choice rather than asking per-action."
        ),
        "action.saveProfile": ActionHelpDescriptor(
            id: "action.saveProfile",
            title: "Save Settings Profile",
            summary: "Serializes the current Build Settings (the full BuildOptions set plus default operation kind) to a named, SwiftData-backed profile you can recall later.",
            practicalAdvice: "The point is switching CONFIGURATIONS, not remembering one: keep a 'fast frontend hack' preset (RelWithDebInfo + --debug-swift + --skip-build-osx/--skip-ios + --skip-build-benchmarks for a tight swift-frontend loop), a 'release + tests' preset (-R, -t/-T, install products) for pre-PR validation, and an 'asan' preset (--enable-asan on its own --build-subdir so it never clobbers your normal objects). This beats hand-toggling a dozen checkboxes each time and beats a shell alias because the profile is structured and round-trips through the same command builder the buttons use. Gotcha: it snapshots values at save time — later editing the live settings does not update the profile, so re-save to capture changes. A saved profile is also what backs a named toolchain-override .ini in the Toolchain tab, so 'asan' the profile and 'asan' the override stay in lockstep."
        ),
        "action.loadProfile": ActionHelpDescriptor(
            id: "action.loadProfile",
            title: "Load Settings Profile",
            summary: "Applies a saved profile's stored BuildOptions into the live Build Settings, replacing whatever is currently set.",
            practicalAdvice: "The fast context switch between saved workflows — flip from your everyday RelWithDebInfo frontend loop to the asan or release+tests configuration in one click instead of re-toggling flags and risking a stray option that silently changes the build. It overwrites the current settings wholesale (it does not merge), so anything you tweaked and didn't save is discarded on load — save first if the live state is worth keeping. Because the profile also carries a default operation kind, loading it lines up both the flags and the button you'll most likely press next; and if the profile is bound to a toolchain-override .ini, loading it selects that named toolchain for the build."
        ),
        "action.deleteProfile": ActionHelpDescriptor(
            id: "action.deleteProfile",
            title: "Delete Settings Profile",
            summary: "Permanently removes the selected saved profile from the SwiftData store.",
            practicalAdvice: "Housekeeping for a configuration that's obsolete — an experiment branch that merged, an asan variant you no longer chase, or a duplicate saved under a slightly different name. Deletion drops only the stored settings snapshot; it does NOT touch the on-disk build tree, so any --build-subdir directory that profile pointed at (build/asan/…) still sits on disk and must be removed separately to reclaim the space. If the profile backs a named toolchain-override .ini in the Toolchain tab, delete it only after you've repointed or removed that override, or the override will reference a profile that no longer exists."
        ),
        "action.buildToolchain": ActionHelpDescriptor(
            id: "action.buildToolchain",
            title: "Build Toolchain",
            summary: "Runs swift/utils/build-toolchain with your tag, layering the generated overrides.ini over the base build-presets.ini via --preset-prefix, producing an installable .xctoolchain bundle and a distributable tarball.",
            practicalAdvice: "Reach for this over Run Build-Script when you need the compiler as a PRODUCT, not just a build tree: a versioned Swift-<tag>.xctoolchain you drop in ~/Library/Developer/Toolchains and select in Xcode's Toolchains menu (or via TOOLCHAINS=), hand to a teammate as a single tarball, or reproduce identically on another machine. build-toolchain is a thin wrapper that forces a preset build (it won't take the ad-hoc -R/-r/-a flags the Build tab uses) and additionally does the darwin bundling, Info.plist stamping, and packaging that build-script alone skips. Gotcha: this is a full install-style build (dylibs, SDK overlays, resource dirs), dramatically slower than an incremental ninja frontend relink, so keep it for cutting a shareable/installable artifact — not your edit-compile-test loop — and expect it to want install-* and dynamic-stdlib options that day-to-day frontend work leaves off."
        ),
        "action.toolchainTag": ActionHelpDescriptor(
            id: "action.toolchainTag",
            title: "Toolchain Tag",
            summary: "The identifier stamped into the bundle name and CFBundleIdentifier (e.g. 'gistya' → swift-gistya.xctoolchain, org.swift.gistya), passed as the positional argument to build-toolchain.",
            practicalAdvice: "This is the human-facing name your compiler shows up as in Xcode's Toolchains submenu and in `xcrun --toolchain <tag>`, so pick something you'll recognize among the stock nightly toolchains beside it. It is NOT a git tag or branch and checks nothing out (that's update-checkout's job) — it's purely the label for this packaging run. Gotcha: reusing a tag overwrites the previously installed bundle of that name, and because the CFBundleIdentifier is derived from it, two toolchains sharing a tag collide in Xcode's picker — bump the tag (or add a date suffix) when you want an old build to stay selectable alongside a new one."
        ),
        "action.presetPrefix": ActionHelpDescriptor(
            id: "action.presetPrefix",
            title: "Preset Prefix",
            summary: "The --preset-prefix string the app prepends to your override preset names so build-toolchain resolves e.g. <prefix>mixin instead of a stock preset.",
            practicalAdvice: "build-presets.ini is a flat global namespace shared with the CI bots (buildbot_incremental, mixin_lightweight_asserts, etc.), so a prefix like 'gistya_' keeps your generated preset names from colliding with upstream ones and makes it obvious in the emitted .ini which lines are yours. It matters because build-toolchain selects the preset by prefix+name and preset composition is name-based: everything under your prefix is your private layer, cleanly separable from the base file you inherit from. Gotcha: the prefix must exactly match what the generated overrides.ini declares its sections as (the app keeps these in sync), so change it here rather than hand-editing preset names, and avoid a prefix that already exists upstream or you'll silently shadow a real preset."
        ),
        "action.basePresetFile": ActionHelpDescriptor(
            id: "action.basePresetFile",
            title: "Base Preset File",
            summary: "The swift/utils/build-presets.ini passed as the first --preset-file, supplying the stock preset definitions and mixins your overrides layer on top of.",
            practicalAdvice: "Point this at the checked-out build-presets.ini so your overrides inherit the same battle-tested base the Swift CI uses (correct install-destdir/symroot layout, LTO/thin-LTO mixins, darwin arch handling) instead of re-specifying dozens of options by hand. Presets support `mixin-preset` inheritance, and build-toolchain reads multiple --preset-file arguments as one merged namespace — which is exactly why the app passes this file first and your generated overrides.ini second: later files win, so your diffs override the base. Gotcha: this must be the build-presets.ini from the SAME checkout you're building, because preset names and mixins drift across Swift releases; a stale copy will either fail to resolve your inherited preset or silently pull in options that no longer mean what they did."
        ),
        "action.toolchainOverride": ActionHelpDescriptor(
            id: "action.toolchainOverride",
            title: "Toolchain Override Profile",
            summary: "A named saved Settings profile the app serializes into overrides.ini, emitting ONLY the options whose values differ from BuildOptions.default as preset lines under your prefix.",
            practicalAdvice: "The composable unit of customization: rather than fork a giant preset, you save a small profile (say 'asan' or 'static-stdlib') and the app writes just its deltas, so an override reads as a handful of intentional lines instead of a wall of defaults. Emitting only diffs is what makes multiple enabled overrides stack predictably — each contributes a minimal, non-overlapping set of preset lines over the base, so a later override changing one option doesn't drag along a hundred redundant defaults that fight earlier layers or the base file. Gotcha: because unchanged options are omitted, an override can only SET a value away from default, never re-assert a default to undo a value another enabled override set — so if two overrides touch the same option, resolve it by editing the profile that owns that field rather than expecting a later empty profile to reset it."
        ),
    ]
}

/// A themed `(?)` help button for an action, looked up by id from `ActionHelp`. Renders nothing
/// if the id is unknown.
struct ActionHelpButton: View {
    let action: String
    init(_ action: String) { self.action = action }
    var body: some View {
        if let descriptor = ActionHelp.descriptor(for: action) {
            HelpButton(descriptor: descriptor)
        }
    }
}
