import Foundation
import SwiftData

/// One completed game, scoped to the exact configuration it was played under.
@Model
final class GameRun {
    var configKey: String = ""
    var score: Int = 0
    var answered: Int = 0
    var date: Date = Date(timeIntervalSince1970: 0)

    init(configKey: String, score: Int, answered: Int, date: Date) {
        self.configKey = configKey
        self.score = score
        self.answered = answered
        self.date = date
    }

    var record: RunRecord {
        RunRecord(score: score, answered: answered, date: date)
    }
}
