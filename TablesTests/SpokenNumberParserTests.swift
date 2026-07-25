import Testing
@testable import Tables

struct SpokenNumberParserTests {

    @Test("plain digits parse", arguments: [
        ("42", 42), ("7", 7), ("144", 144), ("1", 1)
    ])
    func digits(input: String, expected: Int) {
        #expect(SpokenNumberParser.parse(input) == expected)
    }

    @Test("number words parse", arguments: [
        ("forty-two", Optional(42)), ("forty two", 42), ("seven", 7),
        ("one hundred forty-four", 144), ("one hundred and forty four", 144),
        ("twelve", 12), ("forty", 40)
    ])
    func words(input: String, expected: Int?) {
        #expect(SpokenNumberParser.parse(input) == expected)
    }

    @Test("digit-sequence fallback: 'four two' -> 42")
    func digitSequence() {
        #expect(SpokenNumberParser.parse("four two") == 42)
    }

    @Test("kid homophones", arguments: [
        ("to", 2), ("too", 2), ("for", 4), ("ate", 8), ("free", 3), ("tree", 3)
    ])
    func homophones(input: String, expected: Int) {
        #expect(SpokenNumberParser.parse(input) == expected)
    }

    @Test("extracts a number from a phrase", arguments: [
        ("um forty two", 42), ("the answer is 42", 42), ("i think it's nine", 9)
    ])
    func phrases(input: String, expected: Int) {
        #expect(SpokenNumberParser.parse(input) == expected)
    }

    @Test("rejects out-of-range and noise", arguments: [
        "banana", "two hundred", "1000", "", "hello there", "145"
    ])
    func rejects(input: String) {
        #expect(SpokenNumberParser.parse(input) == nil)
    }
}
