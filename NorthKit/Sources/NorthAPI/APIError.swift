import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A failed API call, carrying the server's own message where it sent one.
///
/// Every non-2xx response becomes one of these before the generated client
/// sees it (see `ErrorMappingMiddleware`), so call sites only ever unwrap the
/// documented success case and handle failures in one `catch`.
public enum APIError: LocalizedError, Sendable, Equatable {
    case invalidResponse
    case invalidStatus(Int)
    case unauthorized(String?)
    /// The thing asked for does not exist, or not for this account.
    case notFound(String?)
    case fieldValidation(message: String, fields: [String: String])
    case server(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid server response."
        case .invalidStatus(let code):
            "Request failed with status code \(code)."
        case .unauthorized(let message):
            message ?? "Your session has expired. Please sign in again."
        case .notFound(let message):
            message ?? "That could not be found."
        case .fieldValidation(let message, _), .server(let message), .network(let message):
            message
        }
    }

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        if case .invalidStatus(401) = self { return true }
        return false
    }

    public var isNotFound: Bool {
        if case .notFound = self { return true }
        if case .invalidStatus(404) = self { return true }
        return false
    }

    /// Unwraps what the generated client throws. The runtime wraps every
    /// failure in `ClientError`; the cause is what callers care about.
    public init(_ error: any Error) {
        switch error {
        case let error as APIError:
            self = error
        case let error as ClientError:
            self = APIError(error.underlyingError)
        case let error as URLError:
            self = .network(error.localizedDescription)
        case is DecodingError:
            self = .invalidResponse
        default:
            self = .server(error.localizedDescription)
        }
    }
}

public extension NorthAPI {
    /// Runs a generated call and rethrows any failure as `APIError`.
    ///
    ///     let me = try await NorthAPI.call { try await client.getMe().ok.body.json }
    static func call<T: Sendable>(_ operation: () async throws -> T) async throws(APIError) -> T {
        do {
            return try await operation()
        } catch {
            throw APIError(error)
        }
    }
}

/// Turns non-2xx responses carrying the server's `ErrorBody` into a thrown
/// `APIError`, with its message and any per-field errors. A non-2xx response
/// with some other JSON body is a documented answer of its own and passes
/// through to the generated client.
struct ErrorMappingMiddleware: ClientMiddleware {
    /// Error bodies are a sentence or two; this bounds a misbehaving proxy.
    static let maxErrorBodyBytes = 64 * 1024

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard response.status.kind != .successful else {
            return (response, responseBody)
        }

        guard let responseBody else {
            throw Self.error(status: response.status.code, detail: nil)
        }
        let data = try await Data(collecting: responseBody, upTo: Self.maxErrorBodyBytes)
        if let detail = try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error {
            throw Self.error(status: response.status.code, detail: detail)
        }
        // Not an ErrorBody: a documented non-2xx answer with its own shape,
        // such as a 409 carrying the newest version of an edited plan. Hand it
        // on, with the bytes already read, for the generated client to decode
        // as that operation's case. An undocumented one surfaces there too.
        if !data.isEmpty, response.headerFields[.contentType]?.hasPrefix("application/json") == true {
            return (response, HTTPBody(data))
        }
        throw Self.error(status: response.status.code, detail: nil)
    }

    static func error(status: Int, detail: ErrorDetail?) -> APIError {
        switch (status, detail) {
        case (401, _):
            .unauthorized(detail?.message)
        case (404, _):
            .notFound(detail?.message)
        case (_, let detail?) where !(detail.fields ?? [:]).isEmpty:
            .fieldValidation(message: detail.message, fields: detail.fields ?? [:])
        case (_, let detail?):
            .server(detail.message)
        default:
            .invalidStatus(status)
        }
    }

    struct ErrorEnvelope: Decodable {
        let error: ErrorDetail
    }

    struct ErrorDetail: Decodable {
        let message: String
        let fields: [String: String]?
    }
}
