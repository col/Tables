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

    // Tables and answer mode are shared across both modes — they are the
    // child's preferences. Length is remembered per mode, since a Countdown
    // time and a Revision length are different kinds of choice.
    private static let tablesKey = "setup.tables"
    private static let answerModeKey = "setup.answerMode"
    private static func lengthKey(_ mode: GameMode) -> String { "setup.length.\(mode.rawValue)" }

    @ObservationIgnored private let defaults: UserDefaults
    // UI tests always start from a cold setup so their taps are deterministic.
    @ObservationIgnored private let persists: Bool

    init(mode: GameMode, defaults: UserDefaults = .standard) {
        self.mode = mode
        self.defaults = defaults
        self.persists = !ProcessInfo.processInfo.arguments.contains("-uiTesting")

        if persists {
            self.tables = Self.loadTables(from: defaults)
            self.answerMode = Self.loadAnswerMode(from: defaults)
            self.length = Self.loadLength(from: defaults, mode: mode) ?? Self.defaultLength(mode)
        } else {
            self.tables = []
            self.answerMode = .multipleChoice
            self.length = Self.defaultLength(mode)
        }
        self.openSection = .tables
    }

    /// Persist the current selections so they become the defaults next time.
    /// Called when a game is started.
    func rememberSelections() {
        guard persists else { return }
        defaults.set(tables.sorted(), forKey: Self.tablesKey)
        defaults.set(answerMode.rawValue, forKey: Self.answerModeKey)
        if let data = try? JSONEncoder().encode(length) {
            defaults.set(data, forKey: Self.lengthKey(mode))
        }
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

    // MARK: Persistence helpers

    private static func defaultLength(_ mode: GameMode) -> GameLength {
        mode == .countdown ? .seconds(60) : .questions(20)
    }

    private static func loadTables(from defaults: UserDefaults) -> Set<Int> {
        guard let stored = defaults.array(forKey: tablesKey) as? [Int] else { return [] }
        return Set(stored.filter { GameConfig.allTables.contains($0) })
    }

    private static func loadAnswerMode(from defaults: UserDefaults) -> AnswerMode {
        guard let raw = defaults.string(forKey: answerModeKey),
              let mode = AnswerMode(rawValue: raw) else { return .multipleChoice }
        return mode
    }

    private static func loadLength(from defaults: UserDefaults, mode: GameMode) -> GameLength? {
        guard let data = defaults.data(forKey: lengthKey(mode)),
              let length = try? JSONDecoder().decode(GameLength.self, from: data) else { return nil }
        // Ignore a stored value that isn't a valid option for this mode.
        let valid = mode == .countdown ? GameLength.countdownOptions : GameLength.revisionOptions
        return valid.contains(length) ? length : nil
    }
}
