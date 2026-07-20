import SwiftXState

public struct BuildSettingsMachine: StateMachine {
    public typealias Context = BuildSettingsContext
    public typealias StateID = BuildSettingsState
    public typealias EventID = BuildSettingsEvent
    
    public init() {}

    public var context: BuildSettingsContext { .init() }

    public var machine: some XStateMachine {
        State(.ready) {
            Transition(on: BuildSettingsEvent.setOptions, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .setOptions(options)? = args.event { ctx.options = options }
                return ctx
            }

            Transition(on: BuildSettingsEvent.setRepository, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .setRepository(repo)? = args.event { ctx.selectedRepository = repo }
                return ctx
            }

            Transition(on: BuildSettingsEvent.setBoolOption, to: .ready).action { args, _ in
                guard case let .setBoolOption(key, value)? = args.event else { return args.context }
                return args.context.updatingBool(key: key, value: value)
            }

            Transition(on: BuildSettingsEvent.setIntOption, to: .ready).action { args, _ in
                guard case let .setIntOption(key, value)? = args.event else { return args.context }
                return args.context.updatingInt(key: key, value: value)
            }

            Transition(on: BuildSettingsEvent.setStringOption, to: .ready).action { args, _ in
                guard case let .setStringOption(key, value)? = args.event else { return args.context }
                return args.context.updatingString(key: key, value: value)
            }

            Transition(on: BuildSettingsEvent.applyPreset, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .applyPreset(name)? = args.event {
                    ctx.options.applyPreset(name)
                }
                return ctx
            }

            Transition(on: BuildSettingsEvent.restore, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .restore(options, repo)? = args.event {
                    ctx.options = options
                    ctx.selectedRepository = repo.isEmpty ? "swift" : repo
                }
                return ctx
            }
        }
        .initial()
    }
}

