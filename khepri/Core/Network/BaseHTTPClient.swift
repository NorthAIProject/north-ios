import Foundation
import OSLog

public protocol HTTPClientSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClientSession {}

public final class BaseHTTPClient: Sendable {
    private let baseURL: URL
    private let session: any HTTPClientSession
    private let authTokenProvider: (@Sendable () async -> String?)?
    private let logger: Logger

    public init(
        baseURL: URL,
        session: any HTTPClientSession = URLSession.shared,
        authTokenProvider: (@Sendable () async -> String?)? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authTokenProvider = authTokenProvider
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "khepri", category: "HTTPClient")
    }

    public func execute<E: Endpoint>(_ endpoint: E) async throws -> (Data, HTTPURLResponse) {
        let request = try await buildRequest(for: endpoint)
        logger.debug("🌐 [\(endpoint.method.rawValue)] \(request.url?.absoluteString ?? "")")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("❌ Network error: \(error.localizedDescription)")
            throw APIError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        logger.debug("📥 Status: \(httpResponse.statusCode) for \(request.url?.path ?? "")")

        if (200...299).contains(httpResponse.statusCode) {
            return (data, httpResponse)
        }

        // Parse possible server JSON error response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let errorMsg = (json["error"] as? String) ?? (json["message"] as? String)
            if let fields = json["fields"] as? [String: String] {
                throw APIError.fieldValidation(message: errorMsg ?? "Validation failed.", fields: fields)
            }
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized(errorMsg)
            }
            if let errorMsg {
                throw APIError.server(errorMsg)
            }
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized(nil)
        }

        throw APIError.invalidStatus(httpResponse.statusCode)
    }

    public func call<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        let (data, _) = try await execute(endpoint)
        if E.Response.self == EmptyResponse.self {
            return EmptyResponse() as! E.Response
        }
        do {
            return try endpoint.decoder.decode(E.Response.self, from: data)
        } catch {
            logger.error("❌ Decoding error: \(error.localizedDescription)")
            throw APIError.server("Failed to decode response: \(error.localizedDescription)")
        }
    }

    private func buildRequest<E: Endpoint>(for endpoint: E) async throws -> URLRequest {
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)
        if let queryItems = endpoint.queryItems, !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if endpoint.bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = endpoint.bodyData
        }

        if let headers = endpoint.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let authToken = await authTokenProvider?(), !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }
}
