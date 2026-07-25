import Foundation

/// Schedules the single deferred "the number has settled, submit it" action.
/// Abstracted so the controller can be tested without real waits.
@MainActor
protocol SettleScheduling: AnyObject {
    /// Run `action` after `delay`, cancelling any previously-scheduled action.
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void)
    /// Cancel a pending action, if any.
    func cancel()
}

/// Real scheduler: one cancellable `Task.sleep`.
@MainActor
final class TaskSettleScheduler: SettleScheduling {
    private var task: Task<Void, Never>?

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
