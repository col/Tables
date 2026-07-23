import Foundation
import Observation

enum Route: Hashable {
    case setup(GameMode)
    case game(GameConfig)
    case results
    case progress
}

/// Owns navigation so no screen has to know what comes after it.
@MainActor
@Observable
final class AppRouter {
    var path: [Route] = []
    var isShowingSettings = false
    private(set) var summary: GameSession.Summary?

    func openSetup(_ mode: GameMode) {
        path.append(.setup(mode))
    }

    func startGame(_ config: GameConfig) {
        path.append(.game(config))
    }

    /// Replaces the stack rather than pushing, so Back from results goes home
    /// instead of re-entering a finished game.
    func showResults(_ summary: GameSession.Summary) {
        self.summary = summary
        path = [.results]
    }

    func playAgain() {
        guard let config = summary?.config else { return }
        path = [.game(config)]
    }

    func goHome() {
        summary = nil
        path = []
    }

    func openProgress() {
        path.append(.progress)
    }
}
