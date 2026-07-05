import Foundation

/// Runs short-lived helper processes (git, etc.) without ever blocking a cooperative-executor thread.
///
/// The previous implementation polled `process.isRunning` in a `Thread.sleep` loop. Fanned out one
/// task per repository through a `TaskGroup`, that parked every thread in the cooperative pool at
/// once, starving the runtime and hanging project inspection ("stuck loading the dependencies").
/// Here the process exit is delivered via `terminationHandler` and awaited through a one-shot signal,
/// so each waiter *suspends* rather than blocks — the fan-out is genuinely concurrent.
nonisolated enum AsyncProcess {
    /// Runs `git` with `arguments`, returning trimmed stdout when it exits 0 within `timeout`.
    /// Returns `nil` on launch failure, non-zero exit, empty output, or timeout.
    static func gitOutput(
        _ arguments: [String],
        timeout: Duration = .seconds(2)
    ) async -> String? {
        await trimmedStdout(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            timeout: timeout
        )
    }

    static func trimmedStdout(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async -> String? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        // Set the handler before `run()` so an exit can never be missed. A racing timeout task
        // terminates a hung process, which fires the same handler and lets the await complete.
        let exited = ProcessExitSignal()
        process.terminationHandler = { _ in exited.fire() }
        do {
            try process.run()
        } catch {
            return nil
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        await exited.wait()
        timeoutTask.cancel()

        guard process.terminationStatus == 0 else { return nil }
        // Safe to read to end after exit: these helpers emit far less than the pipe buffer, so the
        // child never blocks on a full pipe while we are suspended.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (output?.isEmpty ?? true) ? nil : output
    }
}

