import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// Builds the generated `/api/v1` client.
///
/// `Client` and every request and response type come from `openapi.yaml`,
/// generated at build time by swift-openapi-generator. Nothing in this module
/// hand-writes a route or a DTO: a server change reaches Swift by syncing the
/// spec (`scripts/sync-openapi.sh`) and rebuilding.
public enum NorthAPI {
    /// A client for the server at `baseURL` (the host, without `/api/v1`).
    ///
    /// - Parameter token: returns the current session token, or nil when
    ///   signed out. Called before every request so a refreshed or cleared
    ///   session takes effect immediately.
    /// - Parameter onUnauthorized: called when the server rejects the token,
    ///   so the app can sign out.
    public static func client(
        baseURL: URL,
        token: @escaping @Sendable () async -> String?,
        onUnauthorized: @escaping @Sendable () async -> Void = {},
        session: URLSession = .shared
    ) -> Client {
        client(
            baseURL: baseURL,
            token: token,
            onUnauthorized: onUnauthorized,
            transport: URLSessionTransport(configuration: .init(session: session))
        )
    }

    /// The same client over any transport; tests pass a canned one.
    public static func client(
        baseURL: URL,
        token: @escaping @Sendable () async -> String?,
        onUnauthorized: @escaping @Sendable () async -> Void = {},
        transport: any ClientTransport
    ) -> Client {
        Client(
            serverURL: baseURL.appending(path: "api/v1"),
            configuration: configuration,
            transport: transport,
            // Outermost first. Error mapping wraps the bearer middleware so
            // the bearer middleware still sees a raw 401 and can sign out.
            middlewares: [
                ErrorMappingMiddleware(),
                BearerAuthMiddleware(token: token, onUnauthorized: onUnauthorized),
            ]
        )
    }

    /// Shared by the client and by tests that decode fixtures, so both read
    /// dates the same way.
    public static let configuration = Configuration(dateTranscoder: FlexibleISO8601DateTranscoder())
}

/// Adds `Authorization: Bearer` to operations that need it and reports 401s.
///
/// Sign-in operations carry `security: []` in the spec; sending a stale token
/// to them would be harmless, but leaving it off keeps the rule simple: the
/// token goes wherever the spec asks for it.
struct BearerAuthMiddleware: ClientMiddleware {
    let token: @Sendable () async -> String?
    let onUnauthorized: @Sendable () async -> Void

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        let sentToken = !Self.publicOperations.contains(operationID)
        if sentToken, let token = await token() {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        let (response, responseBody) = try await next(request, body, baseURL)
        if sentToken, response.status == .unauthorized {
            await onUnauthorized()
        }
        return (response, responseBody)
    }

    /// Operations the spec marks `security: []`, except log-out, which sends
    /// the token it revokes.
    static let publicOperations: Set<String> = [
        "signUp", "logIn", "signInWithGoogle", "signInWithApple", "requestPasswordReset",
        "beginPasskeyRegistration", "finishPasskeyRegistration", "beginPasskeyLogin", "finishPasskeyLogin",
    ]
}

/// Reads RFC 3339 timestamps with or without fractional seconds.
///
/// Go's encoding/json writes `time.Time` with nanoseconds when it has them
/// (`2026-09-24T07:15:00.123456789Z`) and without when it does not. The
/// generator's default transcoder accepts only the second form, so a real
/// server response would fail to decode while every fixture passed.
public struct FlexibleISO8601DateTranscoder: DateTranscoder {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    public init() {}

    public func encode(_ date: Date) throws -> String {
        Self.fractional.format(date)
    }

    public func decode(_ string: String) throws -> Date {
        if let date = try? Self.whole.parse(string) {
            return date
        }
        // Foundation keeps at most millisecond precision; trim the rest first.
        if let date = try? Self.fractional.parse(Self.millisecondPrecision(string)) {
            return date
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not an RFC 3339 date: \(string)"))
    }

    /// `…:00.123456789Z` → `…:00.123Z`; anything else is returned unchanged.
    static func millisecondPrecision(_ string: String) -> String {
        guard let dot = string.lastIndex(of: "."),
              let zone = string[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        else { return string }
        let digits = string[string.index(after: dot)..<zone]
        guard digits.count > 3 else { return string }
        return String(string[..<dot]) + "." + digits.prefix(3) + String(string[zone...])
    }
}
