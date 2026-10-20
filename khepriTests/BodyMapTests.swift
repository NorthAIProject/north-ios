import RealityKit
import SwiftUI
import Testing
@testable import khepri

struct BodyMapTests {
    /// Only meshes named by a muscle key are muscles; the skin is not, so a
    /// tap can never land on it and heat never paints it.
    @MainActor @Test func musclesAreTheNamedMeshes() {
        let root = Entity()
        for name in ["shell", "quads", "delts", ""] {
            let model = ModelEntity(mesh: .generateBox(size: 0.1))
            model.name = name
            root.addChild(model)
        }
        #expect(BodyFigure.models(in: root).map(\.name).sorted() == ["delts", "quads", "shell"])
        #expect(BodyFigure.muscles(in: root).map(\.name).sorted() == ["delts", "quads"])
    }

    /// Untrained is idle; the faintest heat is already a little way up the
    /// ramp, and full heat is ember.
    @MainActor @Test func heatRampStartsAboveTheFloor() {
        let palette = BodyFigure.Palette(.dark)
        #expect(palette.color(heat: 0) == palette.idle)
        #expect(palette.color(heat: 1) == mixed(palette.heatLow, palette.ember, 1))
        #expect(palette.color(heat: 0.001) == mixed(palette.heatLow, palette.ember, 0.15 + 0.85 * 0.001))
    }

    private func mixed(_ from: UIColor, _ to: UIColor, _ fraction: CGFloat) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        return UIColor(red: fr + (tr - fr) * fraction, green: fg + (tg - fg) * fraction, blue: fb + (tb - fb) * fraction, alpha: 1)
    }

    // MARK: - The skin and its shape keys

    /// The bundled skin reads, with the four keys the server weights.
    @Test func bundledShellHasTheFourShapeKeys() throws {
        let shell = try #require(BodyShell.bundled)
        #expect(shell.points.count == shell.normals.count)
        #expect(shell.indices.count % 3 == 0)
        #expect(Set(shell.targets.keys) == ["waist", "hips", "chest", "overall"])
        for (name, target) in shell.targets {
            #expect(!target.vertices.isEmpty, "\(name) moves nothing")
            #expect(target.vertices.count == target.deltas.count)
        }
    }

    /// Modelled is the file's own points; a weight moves only its key's
    /// vertices, by the delta scaled; weights add.
    @Test func weightsScaleAndAddTheDeltas() throws {
        let shell = try BodyShell(data: Self.tinyShell)
        #expect(shell.points(.modelled) == shell.points)

        let half = shell.points(BodyShape(waist: 0.5))
        #expect(half[0] == SIMD3(0.005, 0, 0))
        #expect(half[1] == shell.points[1])
        #expect(half[2] == SIMD3(0, 1, 0.01))

        let both = shell.points(BodyShape(waist: 1, overall: 1))
        #expect(both[0] == SIMD3(0.01, 0, 0.002))
    }

    /// Reshaping swaps the skin's mesh for a wider one, once per shape: the
    /// per-frame update calls it 30 times a second.
    @MainActor @Test func reshapeWidensTheSkinOncePerShape() throws {
        let skin = try #require(BodyShell.bundled)
        let root = Entity()
        let shell = ModelEntity(mesh: try skin.mesh(.modelled))
        shell.name = BodyFigure.shellRegion
        root.addChild(shell)
        let modelled = try #require(shell.model?.mesh.bounds.extents)

        let wide = BodyShape(waist: 1, hips: 1, chest: 1, overall: 0.4)
        BodyFigure.reshape(root, to: wide)
        let widened = try #require(shell.model?.mesh)
        #expect(widened.bounds.extents.z > modelled.z + 0.02, "the belly did not come forward")

        BodyFigure.reshape(root, to: wide)
        #expect(shell.model?.mesh === widened, "the same shape rebuilt the mesh")
        BodyFigure.reshape(root, to: .modelled)
        #expect(abs((shell.model?.mesh.bounds.extents.z ?? 0) - modelled.z) < 0.001)
    }

    /// Weights outside 0…1, or not numbers, are held to the range, as the web
    /// viewer holds them.
    @Test func shapeClampsItsWeights() {
        let shape = BodyShape(waist: 1.4, hips: -0.2, chest: .nan, overall: 0.3)
        #expect(shape == BodyShape(waist: 1, hips: 0, chest: 0, overall: 0.3))
    }

    @Test func aFileThatIsNotAShellIsRefused() {
        #expect(throws: BodyShell.ReadError.notAShell) { try BodyShell(data: Data("glTF....".utf8)) }
        #expect(throws: BodyShell.ReadError.truncated) { try BodyShell(data: Self.tinyShell.prefix(30)) }
    }

    /// Three vertices, one triangle; waist moves vertices 0 and 2, overall
    /// moves vertex 0. Written in the layout scripts/bodymap/shell_bin.go
    /// documents.
    private static let tinyShell: Data = {
        var data = Data("KSHL".utf8)
        func put(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put(_ value: Float) { put(value.bitPattern) }
        func put(_ vector: SIMD3<Float>) { put(vector.x); put(vector.y); put(vector.z) }
        func put(_ name: String) { put(UInt32(name.utf8.count)); data.append(contentsOf: Array(name.utf8)) }
        put(UInt32(1))
        put(UInt32(3)); put(UInt32(1)); put(UInt32(2))
        for point in [SIMD3<Float>(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)] { put(point) }
        for _ in 0..<3 { put(SIMD3<Float>(0, 0, 1)) }
        for index in [UInt32(0), 1, 2] { put(index) }
        put("waist"); put(UInt32(2)); put(UInt32(0)); put(UInt32(2))
        put(SIMD3<Float>(0.01, 0, 0)); put(SIMD3<Float>(0, 0, 0.02))
        put("overall"); put(UInt32(1)); put(UInt32(0)); put(SIMD3<Float>(0, 0, 0.002))
        return data
    }()
}
