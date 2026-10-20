import Foundation
import NorthAPI
import RealityKit

/// The body figure's skin and its four shape keys, read from `BodyShell.bin`.
///
/// The web repo's `scripts/bodymap` writes the file (its layout is in
/// `shell_bin.go`) from the same mesh as the web's GLB, so the same weights
/// give the same body on both. `BodyMap.usdz` carries only the muscles: the
/// app builds the skin itself so it can move it, since RealityKit applies USD
/// blend shapes only through a skeleton. Like the web, the keys move the
/// points and leave the modelled normals.
nonisolated struct BodyShell: Sendable {
    /// One shape key: the vertices it moves and how far, at full strength.
    struct Target: Sendable {
        var vertices: [Int]
        var deltas: [SIMD3<Float>]
    }

    enum ReadError: Error, Equatable {
        case notAShell
        case unsupportedVersion(UInt32)
        case truncated
        case badVertex(Int)
    }

    static let magic = Data("KSHL".utf8)
    static let version: UInt32 = 1

    let points: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
    let targets: [String: Target]

    init(data: Data) throws {
        var reader = Reader(data: data)
        guard try reader.bytes(4) == Self.magic else { throw ReadError.notAShell }
        let version = try reader.uint32()
        guard version == Self.version else { throw ReadError.unsupportedVersion(version) }
        let vertexCount = Int(try reader.uint32())
        let triangleCount = Int(try reader.uint32())
        let targetCount = Int(try reader.uint32())
        points = try reader.vectors(vertexCount)
        normals = try reader.vectors(vertexCount)
        indices = try reader.uint32s(triangleCount * 3)
        if let stray = indices.first(where: { Int($0) >= vertexCount }) { throw ReadError.badVertex(Int(stray)) }
        var targets: [String: Target] = [:]
        for _ in 0..<targetCount {
            guard let name = String(bytes: try reader.bytes(Int(try reader.uint32())), encoding: .utf8) else {
                throw ReadError.notAShell
            }
            let count = Int(try reader.uint32())
            let vertices = try reader.uint32s(count).map(Int.init)
            if let stray = vertices.first(where: { $0 >= vertexCount }) { throw ReadError.badVertex(stray) }
            targets[name] = Target(vertices: vertices, deltas: try reader.vectors(count))
        }
        self.targets = targets
    }

    /// The skin in the app bundle, read once; nil if the file is missing or
    /// unreadable, which leaves the figure without a skin rather than crashing.
    static let bundled: BodyShell? = Bundle.main.url(forResource: "BodyShell", withExtension: "bin")
        .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        .flatMap { try? BodyShell(data: $0) }

    /// The skin's points under a shape: each key's deltas scaled by its weight
    /// and added up.
    func points(_ shape: BodyShape) -> [SIMD3<Float>] {
        var out = points
        for (name, weight) in shape.weights where weight > 0 {
            guard let target = targets[name] else { continue }
            for (vertex, delta) in zip(target.vertices, target.deltas) {
                out[vertex] += delta * weight
            }
        }
        return out
    }

    @MainActor func mesh(_ shape: BodyShape) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: BodyFigure.shellRegion)
        descriptor.positions = MeshBuffer(points(shape))
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// Reads the file's little-endian fields in order.
    private struct Reader {
        let data: Data
        var offset = 0

        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, offset + count <= data.count else { throw ReadError.truncated }
            defer { offset += count }
            let start = data.startIndex + offset
            return data[start..<start + count]
        }

        mutating func uint32() throws -> UInt32 {
            try uint32s(1)[0]
        }

        mutating func uint32s(_ count: Int) throws -> [UInt32] {
            let raw = try bytes(count * 4)
            return raw.withUnsafeBytes { buffer in
                (0..<count).map { UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)) }
            }
        }

        mutating func vectors(_ count: Int) throws -> [SIMD3<Float>] {
            let raw = try bytes(count * 12)
            return raw.withUnsafeBytes { buffer in
                (0..<count).map { vector in
                    let component = { (axis: Int) in
                        let bits = buffer.loadUnaligned(fromByteOffset: vector * 12 + axis * 4, as: UInt32.self)
                        return Float(bitPattern: UInt32(littleEndian: bits))
                    }
                    return SIMD3(component(0), component(1), component(2))
                }
            }
        }
    }
}

/// How far each shape key pushes the skin out, 0 (as modelled) to 1. The
/// server works the weights out from the latest progress check
/// (`GET /body/current`), so every client draws the same body.
nonisolated struct BodyShape: Equatable, Sendable {
    var waist: Float = 0
    var hips: Float = 0
    var chest: Float = 0
    var overall: Float = 0

    static let modelled = BodyShape()

    init(waist: Float = 0, hips: Float = 0, chest: Float = 0, overall: Float = 0) {
        self.waist = Self.clamped(waist)
        self.hips = Self.clamped(hips)
        self.chest = Self.clamped(chest)
        self.overall = Self.clamped(overall)
    }

    init(_ morph: Components.Schemas.BodyMorph) {
        self.init(
            waist: Float(morph.waist), hips: Float(morph.hips), chest: Float(morph.chest), overall: Float(morph.overall)
        )
    }

    /// By the shape keys' names in the file.
    var weights: [(String, Float)] {
        [("waist", waist), ("hips", hips), ("chest", chest), ("overall", overall)]
    }

    private static func clamped(_ value: Float) -> Float {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
