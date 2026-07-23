import Foundation
import Observation

@MainActor
@Observable
final class SetupModel {
    enum Section: Hashable {
        case tables
        case answerMode
        case length
    }

    let mode: GameMode
    var tables: Set<Int>
    var answerMode: AnswerMode
    var length: GameLength
    var openSection: Section?

    init(mode: GameMode) {
        self.mode = mode
        self.tables = [3, 6, 7, 8]
        self.answerMode = .multipleChoice
        self.length = mode == .countdown ? .seconds(60) : .questions(20)
        self.openSection = .tables
    }

    var config: GameConfig {
        GameConfig(mode: mode, tables: tables, answerMode: answerMode, length: length)
    }

    var lengthOptions: [GameLength] {
        mode == .countdown ? GameLength.countdownOptions : GameLength.revisionOptions
    }

    var allSelected: Bool { tables == GameConfig.allTables }

    var selectAllLabel: String { allSelected ? "Clear all" : "Select all" }

    func toggle(table: Int) {
        if tables.contains(table) {
            tables.remove(table)
        } else {
            tables.insert(table)
        }
    }

    func toggleAll() {
        tables = allSelected ? [] : GameConfig.allTables
    }

    func toggle(section: Section) {
        openSection = openSection == section ? nil : section
    }
}
