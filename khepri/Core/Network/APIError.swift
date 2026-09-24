import Foundation

public enum APIError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidResponse
    case invalidStatus(Int)
    case unauthorized(String?)
    case fieldValidation(message: String, fields: [String: String])
    case server(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Invalid server response."
        case .invalidStatus(let code):
            return "Request failed with status code \(code)."
        case .unauthorized(let msg):
            return msg ?? "Your session has expired. Please sign in again."
        case .fieldValidation(let msg, _):
            return msg
        case .server(let msg):
            return msg
        case .network(let msg):
            return msg
        }
    }

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        if case .invalidStatus(401) = self { return true }
        return false
    }
}
