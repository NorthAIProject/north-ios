import NorthKit
import RealityKit
import SwiftUI

/// The body in 3D, built from primitives: a translucent mannequin whose parts
/// are named after the server's soreness regions, so a sore region tints red.
/// Drag to turn it; tap a part to say it is sore.
///
/// Primitives rather than a model file because RealityKit cannot read the
/// web's body.glb, and a region-per-part mannequin is exactly what soreness
/// needs. A USDZ with parts named the same way can replace `BodyBuilder`
/// later without touching anything else.
struct Body3DView: View {
    /// Sore regions and their severity, 1 to 3.
    let soreness: [String: Int]
    var onTapRegion: ((String) -> Void)?

    @State private var yaw: Float = 0
    @State private var dragStart: Float = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RealityView { content in
            let body = BodyBuilder.make()
            body.name = "body"
            content.add(body)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 35
            camera.position = [0, 0.05, 3.1]
            content.add(camera)

            let light = DirectionalLight()
            light.light.intensity = 2500
            light.look(at: .zero, from: [1, 2, 3], relativeTo: nil)
            content.add(light)
        } update: { content in
            guard let body = content.entities.first(where: { $0.name == "body" }) else { return }
            body.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            BodyBuilder.tint(body, soreness: soreness)
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in yaw = dragStart + Float(value.translation.width) * 0.01 }
                .onEnded { _ in dragStart = yaw }
        )
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    let region = value.entity.name
                    if DayMath.regions.contains(where: { $0.key == region }) { onTapRegion?(region) }
                }
        )
        .task {
            // A slow turn so it reads as 3D at a glance; still for reduced motion.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                yaw += 0.004
                dragStart = yaw
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Body")
        .accessibilityValue(soreness.keys.sorted().map(DayMath.regionName).joined(separator: ", "))
    }
}

/// Builds and tints the mannequin. Units are metres, feet at y = 0.
enum BodyBuilder {
    private struct Part {
        let region: String
        let mesh: MeshResource
        let position: SIMD3<Float>
        var tilt: Float = 0 // around z, radians
    }

    static let base = UIColor(NorthColor.Day.stand).withAlphaComponent(0.35)
    static let sore: [Int: UIColor] = [
        1: UIColor(NorthColor.Day.fat).withAlphaComponent(0.6),
        2: UIColor(NorthColor.Day.move).withAlphaComponent(0.7),
        3: UIColor(NorthColor.Day.move).withAlphaComponent(0.95),
    ]

    static func make() -> Entity {
        Tinted.registerComponent()
        let root = Entity()
        for part in parts() {
            for side in part.position.x == 0 ? [Float(1)] : [Float(1), -1] {
                let entity = ModelEntity(mesh: part.mesh, materials: [material(base)])
                entity.name = part.region
                entity.position = [part.position.x * side, part.position.y, part.position.z]
                entity.orientation = simd_quatf(angle: part.tilt * side, axis: [0, 0, 1])
                entity.generateCollisionShapes(recursive: false)
                entity.components.set(InputTargetComponent())
                root.addChild(entity)
            }
        }
        // Centre the figure on the origin so it turns about its own axis.
        root.position = [0, -0.9, 0]
        let holder = Entity()
        holder.addChild(root)
        holder.scale = [0.9, 0.9, 0.9]
        return holder
    }

    /// The soreness the figure was last tinted for, so turning it (which runs
    /// the view's update every frame) does not rebuild every material.
    struct Tinted: Component {
        var soreness: [String: Int]
    }

    static func tint(_ holder: Entity, soreness: [String: Int]) {
        if holder.components[Tinted.self]?.soreness == soreness { return }
        holder.components.set(Tinted(soreness: soreness))
        guard let root = holder.children.first else { return }
        for case let part as ModelEntity in root.children {
            let color = soreness[part.name].flatMap { sore[$0] } ?? base
            part.model?.materials = [material(color)]
        }
    }

    private static func material(_ color: UIColor) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = 0.6
        m.metallic = 0.0
        m.blending = .transparent(opacity: .init(scale: Float(color.cgColor.alpha)))
        return m
    }

    private static func limb(_ length: Float, _ radius: Float) -> MeshResource {
        .generateCylinder(height: length, radius: radius)
    }

    /// Parts off the midline are placed on the right and mirrored.
    private static func parts() -> [Part] {
        [
            Part(region: "neck", mesh: .generateSphere(radius: 0.1), position: [0, 1.68, 0]),
            Part(region: "neck", mesh: limb(0.08, 0.05), position: [0, 1.55, 0]),
            Part(region: "shoulders", mesh: .generateSphere(radius: 0.065), position: [0.2, 1.44, 0]),
            Part(region: "chest", mesh: .generateBox(size: [0.34, 0.2, 0.18], cornerRadius: 0.07), position: [0, 1.36, 0.01]),
            Part(region: "upper_back", mesh: .generateBox(size: [0.3, 0.18, 0.05], cornerRadius: 0.02), position: [0, 1.36, -0.08]),
            Part(region: "abs", mesh: .generateBox(size: [0.28, 0.2, 0.16], cornerRadius: 0.06), position: [0, 1.16, 0.01]),
            Part(region: "lower_back", mesh: .generateBox(size: [0.26, 0.16, 0.05], cornerRadius: 0.02), position: [0, 1.16, -0.07]),
            Part(region: "hips", mesh: .generateBox(size: [0.32, 0.12, 0.17], cornerRadius: 0.05), position: [0, 1.0, 0]),
            Part(region: "glutes", mesh: .generateSphere(radius: 0.08), position: [0.08, 0.97, -0.06]),
            Part(region: "biceps", mesh: limb(0.28, 0.045), position: [0.25, 1.26, 0.01], tilt: 0.12),
            Part(region: "triceps", mesh: limb(0.26, 0.035), position: [0.255, 1.27, -0.03], tilt: 0.12),
            Part(region: "forearms", mesh: limb(0.26, 0.037), position: [0.29, 0.99, 0.02], tilt: 0.06),
            Part(region: "quads", mesh: limb(0.4, 0.07), position: [0.09, 0.72, 0.01]),
            Part(region: "hamstrings", mesh: limb(0.38, 0.05), position: [0.09, 0.72, -0.04]),
            Part(region: "knees", mesh: .generateSphere(radius: 0.055), position: [0.09, 0.5, 0.01]),
            Part(region: "calves", mesh: limb(0.38, 0.05), position: [0.09, 0.28, -0.01]),
            Part(region: "feet", mesh: .generateBox(size: [0.08, 0.05, 0.2], cornerRadius: 0.02), position: [0.09, 0.03, 0.04]),
        ]
    }
}
