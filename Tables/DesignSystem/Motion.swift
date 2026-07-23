import SwiftUI

/// Restrained motion: a pop on select, a flip on reveal, quiet colour fades
/// everywhere else. Nothing loops or bounces idly.
enum Motion {
    static let quick: TimeInterval = 0.08
    static let fade: TimeInterval = 0.18
    static let pop: TimeInterval = 0.30
    static let flip: TimeInterval = 0.40

    /// Single source of truth for the cubic-bezier(0.22, 1, 0.36, 1) curve
    /// shared by `easeOut` and `popAnimation`.
    private static let easeOutStartControlPoint = UnitPoint(x: 0.22, y: 1)
    private static let easeOutEndControlPoint = UnitPoint(x: 0.36, y: 1)

    static let easeOut = UnitCurve.bezier(
        startControlPoint: easeOutStartControlPoint,
        endControlPoint: easeOutEndControlPoint
    )

    static let fadeAnimation = Animation.easeInOut(duration: fade)
    static let popAnimation = Animation.timingCurve(
        easeOutStartControlPoint.x, easeOutStartControlPoint.y,
        easeOutEndControlPoint.x, easeOutEndControlPoint.y,
        duration: pop
    )

    /// Single place where Reduce Motion is honoured, so no view has to
    /// remember to check it.
    static func animation(_ base: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }
}
