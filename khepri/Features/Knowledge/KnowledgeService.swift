import Foundation
import NorthAPI
import OpenAPIRuntime

typealias KnowledgeDocument = Components.Schemas.KnowledgeDocument
typealias KnowledgeList = Components.Schemas.KnowledgeList
typealias KnowledgeHit = Components.Schemas.KnowledgeSearchResults.HitsPayloadPayload

protocol KnowledgeServicing: Sendable {
    func library() async throws -> KnowledgeList
    func search(_ query: String) async throws -> [KnowledgeHit]
    func text(_ id: String) async throws -> String
    func createNote(title: String, body: String) async throws
    /// The server reads the kind from the filename's extension and the bytes,
    /// not a declared type, so the name is what matters.
    func upload(filename: String, data: Data) async throws
    func delete(_ id: String) async throws
    func reindex(_ id: String) async throws
    /// Re-reads every document, after a change in how the server indexes.
    func reindexAll() async throws
}

struct KnowledgeService: KnowledgeServicing {
    var api: Client = API.shared

    func library() async throws -> KnowledgeList {
        try await NorthAPI.call { try await api.listKnowledge().ok.body.json }
    }

    func search(_ query: String) async throws -> [KnowledgeHit] {
        try await NorthAPI.call { try await api.searchKnowledge(query: .init(q: query, limit: 20)).ok.body.json.hits }
    }

    func text(_ id: String) async throws -> String {
        try await NorthAPI.call { try await api.getKnowledgeDocument(path: .init(documentID: id)).ok.body.json.value2.text }
    }

    func createNote(title: String, body: String) async throws {
        try await NorthAPI.call { _ = try await api.createKnowledgeNote(body: .json(.init(title: title, body: body))).created }
    }

    func upload(filename: String, data: Data) async throws {
        let part = OpenAPIRuntime.MultipartPart(
            payload: Operations.UploadKnowledge.Input.Body.MultipartFormPayload.FilePayload(body: HTTPBody(data)),
            filename: filename
        )
        try await NorthAPI.call {
            _ = try await api.uploadKnowledge(body: .multipartForm([.file(part)])).created
        }
    }

    func delete(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteKnowledgeDocument(path: .init(documentID: id)).noContent }
    }

    func reindex(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.reindexKnowledgeDocument(path: .init(documentID: id)).accepted }
    }

    func reindexAll() async throws {
        try await NorthAPI.call { _ = try await api.reindexKnowledge().accepted }
    }
}
