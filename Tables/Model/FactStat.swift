import Foundation
import SwiftData

/// Answering history for one multiplication fact.
///
/// `averageMillis` is an exponential moving average over *correct* answers
/// only, so it reflects how quickly the child can produce the fact now rather
/// than how long they took the first time they met it.
@Model
final class FactStat {
    @Attribute(.unique) var key: String = ""
    var a: Int = 0
    var b: Int = 0
    var attempts: Int = 0
    var correctCount: Int = 0
    var averageMillis: Double = 0
    var lastAnsweredAt: Date = Date(timeIntervalSince1970: 0)

    init(fact: Fact) {
        self.key = fact.key
        self.a = fact.a
        self.b = fact.b
        self.attempts = 0
        self.correctCount = 0
        self.averageMillis = 0
        self.lastAnsweredAt = Date(timeIntervalSince1970: 0)
    }

    var fact: Fact { Fact(a: a, b: b) }

    var history: FactHistory {
        FactHistory(
            attempts: attempts,
            // Untimed correct answers prove the child knew it, not that they
            // were quick. Mastery needs timed evidence.
            correctCount: timedCorrectCount,
            averageMillis: averageMillis
        )
    }

    /// `millis` is nil when the answer was correct but the timing is not
    /// trustworthy — a Countdown retry after a wrong first attempt.
    func recordCorrect(millis: Double?, at date: Date) {
        if let millis {
            averageMillis = Mastery.updatedAverage(
                current: averageMillis,
                correctCount: timedCorrectCount,
                latestMillis: millis
            )
            timedCorrectCount += 1
        }
        attempts += 1
        correctCount += 1
        lastAnsweredAt = date
    }

    func recordIncorrect(at date: Date) {
        attempts += 1
        lastAnsweredAt = date
    }

    /// Correct answers that carried a usable timing. Kept separate from
    /// `correctCount` so untimed answers cannot skew the moving average.
    private var timedCorrectCount: Int = 0
}
