import Foundation

/// Number-word reasoning over answer numbers (1…144) — the inverse of
/// `SpokenNumberParser`. Used to decide whether a partially-heard number could
/// still grow into the correct answer.
///
/// `nonisolated`: pure Sendable helper (see `SpokenNumberParser`).
nonisolated enum SpokenNumber {

    private static let ones = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    private static let tens = [
        20: "twenty", 30: "thirty", 40: "forty", 50: "fifty",
        60: "sixty", 70: "seventy", 80: "eighty", 90: "ninety",
    ]

    /// Canonical spoken words for `n` (1…144). 36 -> ["thirty","six"].
    static func words(_ n: Int) -> [String] {
        if n < 20 { return [ones[n]] }
        if n < 100 {
            let t = (n / 10) * 10
            let u = n % 10
            return u == 0 ? [tens[t]!] : [tens[t]!, ones[u]]
        }
        let rest = n - 100
        return rest == 0 ? ["one", "hundred"] : ["one", "hundred"] + words(rest)
    }

    /// Whether `n` could still grow if the child keeps speaking: the tens
    /// ("twenty" -> "twenty one"), "one" (-> "one hundred …"), and any hundred
    /// (over-inclusive on purpose — waiting a beat on 100–144 is cheap, clipping
    /// "one hundred forty four" is not).
    static func isExtendable(_ n: Int) -> Bool {
        n == 1 || (n >= 20 && n <= 90 && n % 10 == 0) || n >= 100
    }

    /// Status of a heard number against the expected answer, by comparing
    /// canonical-word prefixes (so "three"/3 is off-track for 36 but "thirty"/30
    /// is on-track).
    static func track(heard: Int, answer: Int) -> VoiceProgress.Status {
        if heard == answer { return .matches }
        let h = words(heard)
        let a = words(answer)
        return h.count < a.count && Array(a.prefix(h.count)) == h ? .onTrack : .offTrack
    }
}
