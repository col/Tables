import Foundation

/// Turns a speech transcript into an answer number, or `nil`.
///
/// Scoped to the game's answer range (1–144), so background chatter and
/// out-of-range utterances resolve to nothing rather than a wrong guess.
///
/// `nonisolated`: a pure Sendable helper should not be main-actor-isolated
/// just because the app target defaults to `SWIFT_DEFAULT_ACTOR_ISOLATION`.
nonisolated enum SpokenNumberParser {

    private static let maxAnswer = 144

    /// Single-token words → value. Includes number words 0–20, the tens, and
    /// the homophones a child reliably triggers ("to"→2, "ate"→8, "tree"→3).
    private static let words: [String: Int] = [
        "zero": 0, "oh": 0,
        "one": 1, "won": 1,
        "two": 2, "to": 2, "too": 2,
        "three": 3, "free": 3, "tree": 3,
        "four": 4, "for": 4, "fore": 4,
        "five": 5, "six": 6, "sicks": 6,
        "seven": 7, "eight": 8, "ate": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "hundred": 100
    ]

    static func parse(_ transcript: String) -> Int? {
        let tokens = tokenize(transcript)
        guard !tokens.isEmpty else { return nil }

        // 1. A bare integer in range anywhere in the phrase wins
        //    ("the answer is 42" → 42). Out-of-range ints are skipped.
        for token in tokens {
            if let value = Int(token), inRange(value) { return value }
        }

        // 2. Gather the number-words in order, dropping filler words
        //    ("um forty two" → [40, 2]; "i think it's nine" → [9]).
        let values = tokens.compactMap { words[$0] }
        guard !values.isEmpty else { return nil }

        // 2a. Two or more spoken single digits are a digit sequence, not a sum:
        //     "four two" → "42", "eight eight" → "88".
        if values.count >= 2, values.allSatisfy({ (0...9).contains($0) }) {
            guard let value = Int(values.map(String.init).joined()) else { return nil }
            return inRange(value) ? value : nil
        }

        // 2b. Standard number-word accumulation: "forty two" → 42,
        //     "one hundred forty four" → 144, "two hundred" → 200 (rejected).
        let value = accumulate(values)
        return inRange(value) ? value : nil
    }

    private static func inRange(_ value: Int) -> Bool { value >= 1 && value <= maxAnswer }

    private static func tokenize(_ transcript: String) -> [String] {
        transcript
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "and" }
    }

    /// Classic accumulate: units/tens add to a running part, "hundred" scales it.
    private static func accumulate(_ values: [Int]) -> Int {
        var total = 0
        var current = 0
        for value in values {
            if value == 100 {
                current = max(current, 1) * 100
            } else {
                current += value
            }
            if current >= 100 {
                total += current
                current = 0
            }
        }
        return total + current
    }
}
