import Testing
import Foundation
@testable import Tables

@MainActor
struct ManualSettleSchedulerTests {
    @Test("records delay and fires the latest action once")
    func recordsAndFires() {
        let scheduler = ManualSettleScheduler()
        var fired = 0
        scheduler.schedule(after: .milliseconds(400)) { fired += 1 }
        #expect(scheduler.lastDelay == .milliseconds(400))
        // A second schedule replaces the first.
        scheduler.schedule(after: .milliseconds(1200)) { fired += 10 }
        #expect(scheduler.lastDelay == .milliseconds(1200))
        scheduler.fire()
        #expect(fired == 10)          // only the latest action ran
        scheduler.fire()
        #expect(fired == 10)          // fire is one-shot
    }

    @Test("cancel prevents the action from firing")
    func cancelStops() {
        let scheduler = ManualSettleScheduler()
        var fired = false
        scheduler.schedule(after: .milliseconds(400)) { fired = true }
        scheduler.cancel()
        scheduler.fire()
        #expect(fired == false)
    }
}
