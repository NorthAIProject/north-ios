import Foundation
import NorthAPI
import OpenAPIRuntime

typealias ProgressCheck = Components.Schemas.ProgressCheck
typealias ProgressChecks = Components.Schemas.ProgressChecks
typealias ProgressCheckInput = Components.Schemas.ProgressCheckInput
typealias ProgressComparison = Components.Schemas.ProgressComparison
typealias ProgressAssist = Components.Schemas.ProgressAssist
typealias ProgressEstimateResult = Components.Schemas.ProgressEstimateResult
typealias ProgressSchedule = Components.Schemas.ProgressSchedule

/// The three photos a check can carry, in the order the form shows them.
/// Front and side make a complete check; back is optional.
enum ProgressPose: String, CaseIterable, Identifiable, Sendable {
    case front, side, back
    var id: Self { self }

    var isRequired: Bool { self != .back }

    var title: String {
        switch self {
        case .front: String(localized: "Front")
        case .side: String(localized: "Side")
        case .back: String(localized: "Back")
        }
    }
}

/// The photos chosen for a new check, as JPEGs ready to send.
typealias ProgressPhotos = [ProgressPose: Data]

protocol ProgressCheckServicing: Sendable {
    func checks() async throws -> ProgressChecks
    func assist() async throws -> ProgressAssist
    func save(_ input: ProgressCheckInput, photos: ProgressPhotos) async throws -> ProgressCheck
    /// Reads waist, hips and chest off the photos. Stores nothing.
    func estimate(_ photos: ProgressPhotos) async throws -> ProgressEstimateResult
    /// Compares the first and latest checks with photos, replacing the last
    /// comparison.
    func compare() async throws -> ProgressComparison
    func delete(_ id: String) async throws -> ProgressChecks
    /// weekly, biweekly or monthly; empty turns the reminder off.
    func setCadence(_ cadence: String) async throws -> ProgressSchedule
}

struct ProgressCheckService: ProgressCheckServicing {
    var api: Client = API.shared
    /// Estimates and comparisons wait on a model reading photos.
    var generationAPI: Client = API.generation

    func checks() async throws -> ProgressChecks {
        try await NorthAPI.call { try await api.listProgressChecks().ok.body.json }
    }

    func assist() async throws -> ProgressAssist {
        try await NorthAPI.call { try await api.getProgressAssist().ok.body.json }
    }

    func save(_ input: ProgressCheckInput, photos: ProgressPhotos) async throws -> ProgressCheck {
        typealias Part = Operations.CreateProgressCheck.Input.Body.MultipartFormPayload
        let json = try JSONEncoder().encode(input)
        let check: Part = .check(.init(payload: .init(body: HTTPBody(json))))
        let form: [Part] = [check] + photoParts(photos) { pose, body, name in
            switch pose {
            case .front: .front(.init(payload: .init(body: body), filename: name))
            case .side: .side(.init(payload: .init(body: body), filename: name))
            case .back: .back(.init(payload: .init(body: body), filename: name))
            }
        }
        return try await BackgroundActivity.run("Progress check") {
            try await NorthAPI.call {
                try await api.createProgressCheck(body: .multipartForm(.init(form))).created.body.json.check
            }
        }
    }

    func estimate(_ photos: ProgressPhotos) async throws -> ProgressEstimateResult {
        typealias Part = Operations.EstimateProgressCheck.Input.Body.MultipartFormPayload
        let form: [Part] = photoParts(photos) { pose, body, name in
            switch pose {
            case .front: .front(.init(payload: .init(body: body), filename: name))
            case .side: .side(.init(payload: .init(body: body), filename: name))
            case .back: .back(.init(payload: .init(body: body), filename: name))
            }
        }
        return try await NorthAPI.call {
            try await generationAPI.estimateProgressCheck(body: .multipartForm(.init(form))).ok.body.json
        }
    }

    func compare() async throws -> ProgressComparison {
        try await NorthAPI.call { try await generationAPI.compareProgressChecks().ok.body.json }
    }

    func delete(_ id: String) async throws -> ProgressChecks {
        try await NorthAPI.call { try await api.deleteProgressCheck(path: .init(checkID: id)).ok.body.json }
    }

    func setCadence(_ cadence: String) async throws -> ProgressSchedule {
        try await NorthAPI.call { try await api.setProgressSchedule(body: .json(.init(cadence: cadence))).ok.body.json }
    }

    /// One part per chosen photo, in pose order; each operation names its
    /// own part types, so the caller makes the part.
    private func photoParts<Part>(
        _ photos: ProgressPhotos, _ make: (ProgressPose, HTTPBody, String) -> Part
    ) -> [Part] {
        ProgressPose.allCases.compactMap { pose in
            photos[pose].map { make(pose, HTTPBody($0), "\(pose.rawValue).jpg") }
        }
    }
}
