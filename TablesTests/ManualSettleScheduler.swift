import Foundation
@testable import Tables

/// Test scheduler: records the requested delay and lets the test fire the
/// pending action manually, so settle behaviour is verified without waiting.
@MainActor
final class ManualSettleScheduler: SettleScheduling {
    private(set) var lastDelay: Duration?
    private var action: (@MainActor () -> Void)?

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        lastDelay = delay
        self.action = action
    }

    /// Cancels the pending action. `lastDelay` is left as-is so a test can still
    /// inspect the most recently requested delay after a submit cancels it.
    func cancel() {
        action = nil
    }

    /// Invoke the currently-scheduled action, as the real timer would on timeout.
    func fire() {
        let action = self.action
        self.action = nil
        action?()
    }

    var hasPendingAction: Bool { action != nil }
}
