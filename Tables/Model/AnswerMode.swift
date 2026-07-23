import Foundation

enum AnswerMode: String, CaseIterable, Codable, Sendable {
    case multipleChoice
    case numberPad

    var title: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .numberPad: "Number pad"
        }
    }

    var subtitle: String {
        switch self {
        case .multipleChoice: "Pick from the tiles"
        case .numberPad: "Type the answer"
        }
    }
}
