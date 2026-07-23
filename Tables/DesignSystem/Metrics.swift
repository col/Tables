import CoreGraphics

/// Layout constants from the design system's spacing and radius tokens.
enum Metrics {
    // 4pt base rhythm.
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 26
    static let space7: CGFloat = 32
    static let space8: CGFloat = 40
    static let space9: CGFloat = 56
    static let space10: CGFloat = 72

    static let radiusSwatch: CGFloat = 6
    static let radiusKey: CGFloat = 8
    static let radiusTile: CGFloat = 10
    static let radiusCard: CGFloat = 14
    static let radiusPill: CGFloat = 999

    static let strokeTile: CGFloat = 2
    static let strokeCard: CGFloat = 1

    static let hitMin: CGFloat = 44

    /// The design is drawn for a phone. On iPad the content column is capped
    /// and centred rather than stretched.
    static let contentMaxWidth: CGFloat = 420
}
