import Foundation

enum Endpoint {
    case messages
    case nextMessages(path: String)

    func getPath() -> String {
        switch self {
        case .messages:
            return "messaging/message"
        case .nextMessages(let path):
            return "messaging/\(path)"
        }
    }
}
