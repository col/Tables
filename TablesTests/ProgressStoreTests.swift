import Testing
import Foundation
import SwiftData
@testable import Tables

@MainActor
struct ProgressStoreTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSwiftDataStore() throws -> SwiftDataProgressStore {
        let container = try ModelContainer(
            for: FactStat.self, GameRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataProgressStore(context: ModelContext(container))
    }

    private func stores() throws -> [(String, any ProgressRecording)] {
        [("in-memory", InMemoryProgressStore()), ("SwiftData", try makeSwiftDataStore())]
    }

    @Test("an empty store reports no history")
    func emptyStore() throws {
        for (name, store) in try stores() {
            #expect(store.history().isEmpty, "\(name) was not empty")
            #expect(store.runs(forConfigKey: "anything").isEmpty, "\(name) had runs")
        }
    }

    @Test("recording a correct answer creates and updates history")
    func recordsCorrect() throws {
        for (name, store) in try stores() {
            let fact = Fact(a: 7, b: 8)
            store.recordCorrect(fact, millis: 2000, at: start)
            store.recordCorrect(fact, millis: 2000, at: start)

            let history = try #require(store.history()["7x8"], "\(name) lost the fact")
            #expect(history.attempts == 2, "\(name)")
            #expect(history.correctCount == 2, "\(name)")
            #expect(abs(history.averageMillis - 2000) < 0.0001, "\(name)")
        }
    }

    @Test("recording a wrong answer counts the attempt without a timing")
    func recordsIncorrect() throws {
        for (name, store) in try stores() {
            let fact = Fact(a: 6, b: 9)
            store.recordIncorrect(fact, at: start)

            let history = try #require(store.history()["6x9"], "\(name)")
            #expect(history.attempts == 1, "\(name)")
            #expect(history.correctCount == 0, "\(name)")
        }
    }

    @Test("runs are returned only for their own configuration, newest data intact")
    func runsAreScopedByConfig() throws {
        for (name, store) in try stores() {
            store.recordRun(configKey: "a", score: 10, answered: 12, at: start)
            store.recordRun(configKey: "a", score: 4, answered: 5, at: start.addingTimeInterval(60))
            store.recordRun(configKey: "b", score: 99, answered: 99, at: start)

            let runsForA = store.runs(forConfigKey: "a")
            #expect(runsForA.count == 2, "\(name)")
            #expect(Set(runsForA.map(\.score)) == [10, 4], "\(name)")
            #expect(store.runs(forConfigKey: "b").map(\.score) == [99], "\(name)")
            #expect(store.runs(forConfigKey: "c").isEmpty, "\(name)")
        }
    }

    @Test("mastery levels reflect recorded history and default to Not yet")
    func masteryLevels() throws {
        for (name, store) in try stores() {
            let mastered = Fact(a: 2, b: 3)
            for _ in 0..<3 { store.recordCorrect(mastered, millis: 1200, at: start) }
            store.recordIncorrect(Fact(a: 11, b: 12), at: start)

            let levels = store.masteryLevels()
            #expect(levels["2x3"] == .mastered, "\(name)")
            #expect(levels["11x12"] == .gettingThere, "\(name)")
            #expect(levels["9x9"] == nil, "\(name) invented history")
        }
    }

    // MARK: - Task 8 persistence risk closed here

    @Test("a correct answer's timed evidence survives a save and a fresh fetch")
    func timedCorrectCountSurvivesRoundTrip() throws {
        let container = try ModelContainer(
            for: FactStat.self, GameRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let writeContext = ModelContext(container)
        let store = SwiftDataProgressStore(context: writeContext)
        let fact = Fact(a: 4, b: 6)

        store.recordCorrect(fact, millis: 1800, at: start)
        try writeContext.save()

        // A fresh context on the same container forces a real fetch from the
        // persisted store rather than returning the object already held in
        // memory, which is the only way to catch a private stored property
        // (`timedCorrectCount`) failing to persist.
        let readContext = ModelContext(container)
        let key = fact.key
        let descriptor = FetchDescriptor<FactStat>(predicate: #Predicate { $0.key == key })
        let fetched = try #require(readContext.fetch(descriptor).first, "fact did not persist")

        #expect(fetched.history.correctCount == 1, "timedCorrectCount did not survive the round trip")
        #expect(abs(fetched.history.averageMillis - 1800) < 0.0001, "averageMillis did not survive the round trip")
    }
}
