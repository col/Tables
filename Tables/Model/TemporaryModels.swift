import Foundation
import SwiftData

// Temporary placeholders so the app compiles before Task 8.
// Task 8 deletes this file and creates FactStat.swift / GameRun.swift.
@Model final class FactStat {
    var key: String = ""
    init(key: String) { self.key = key }
}

@Model final class GameRun {
    var configKey: String = ""
    init(configKey: String) { self.configKey = configKey }
}
