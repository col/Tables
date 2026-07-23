import SwiftUI

/// Restrained motion: a pop on select, a flip on reveal, quiet colour fades
/// everywhere else. Nothing loops or bounces idly.
enum Motion {
    static let quick: TimeInterval = 0.08
    static let fade: TimeInterval = 0.18
    static let pop: TimeInterval = 0.30
    static let flip: TimeInterval = 0.40

    static let easeOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.22, y: 1),
        endControlPoint: UnitPoint(x: 0.36, y: 1)
    )

    static let fadeAnimation = Animation.easeInOut(duration: fade)
    static let popAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: pop)
    static let quickAnimation = Animation.easeOut(duration: quick)

    /// Single place where Reduce Motion is honoured, so no view has to
    /// remember to check it.
    static func animation(_ base: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }
}
