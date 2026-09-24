import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

public protocol Endpoint: Sendable {
    associatedtype Response: Decodable, Sendable

    var method: HTTPMethod { get }
    var path: String { get }
    var queryItems: [URLQueryItem]? { get }
    var headers: [String: String]? { get }
    var bodyData: Data? { get }
    var decoder: JSONDecoder { get }
}

public extension Endpoint {
    var queryItems: [URLQueryItem]? { nil }
    var headers: [String: String]? { nil }
    var bodyData: Data? { nil }
    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct EmptyResponse: Sendable {
    public init() {}
}

extension EmptyResponse: Decodable {
    public nonisolated init(from decoder: Decoder) throws {
        self.init()
    }
}
