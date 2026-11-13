import NorthKit
import RealityKit
import SwiftUI

/// The Khepri mascot in 3D, for the onboarding Welcome step.
///
/// A non-AR `RealityView` with a virtual camera, drawn transparent over
/// SwiftUI. The flat `KhepriMascot(.idle)` shows until the first frame and
/// stays under Reduce Motion, Low Power Mode, or a model that fails to load.
/// Motion values come from `MascotMotion` (mascot-motion.json); this view
/// applies them to the model's joint entities (`Mascot_body`, `_core`,
/// `_head`, `_eyes`, `_pupils`, written by north-web-app
/// `scripts/brand/mascot_3d.py`). DESIGN.md, 3D Mascot.
struct Mascot3DView: View {
    var size: CGFloat = 200

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var stage = MascotStage()

    private var draws: Bool { !reduceMotion && !lowPower && stage.motion != nil }

    var body: some View {
        ZStack {
            KhepriMascot(.idle)
                .opacity(draws && stage.isLive ? 0 : 1)
            if draws {
                RealityView { content in
                    content.camera = .virtual
                    await stage.load(into: &content)
                    stage.updates = content.subscribe(to: SceneEvents.Update.self) { event in
                        MainActor.assumeIsolated { stage.step(event.deltaTime) }
                    }
                }
                .opacity(stage.isLive ? 1 : 0)
                .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): stage.setPointer(location, in: size)
            case .ended: stage.clearPointer()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { stage.setPointer($0.location, in: size) }
                .onEnded { _ in stage.clearPointer() }
        )
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .accessibilityHidden(true)
    }
}

/// Holds the scene and turns each frame's time into joint transforms. Main
/// actor: RealityKit delivers scene updates there.
@MainActor @Observable
final class MascotStage {
    let motion = try? MascotMotion.load()
    private(set) var isLive = false
    @ObservationIgnored var updates: EventSubscription?

    private struct Joints {
        let body: Entity
        let head: Entity
        let eyes: Entity
        let pupils: Entity
        let bodyRest: SIMD3<Float>
        let pupilsRest: SIMD3<Float>
    }

    @ObservationIgnored private var joints: Joints?
    @ObservationIgnored private var glows: [(model: ModelEntity, base: Float)] = []
    @ObservationIgnored private var seconds: Double = 0
    @ObservationIgnored private var target = MascotMotion.Look.rest
    @ObservationIgnored private var now = MascotMotion.Look.rest

    private static let fov: Float = 30
    private static let margin: Float = 1.12

    func load(into content: inout RealityViewCameraContent) async {
        guard let model = try? await Entity(named: "Mascot") else { return }
        // The file wraps its joints in Mascot/Root; start below the wrapper.
        let root = model.findEntity(named: "Root") ?? model
        guard let body = root.findEntity(named: "Mascot_body"),
              let head = root.findEntity(named: "Mascot_head"),
              let eyes = root.findEntity(named: "Mascot_eyes"),
              let pupils = root.findEntity(named: "Mascot_pupils"),
              let core = root.findEntity(named: "Mascot_core")
        else { return }
        content.add(root)

        let bounds = root.visualBounds(relativeTo: nil)
        let extents = bounds.extents
        let distance = max(extents.x, extents.y) * Self.margin / 2 / tan(Self.fov * .pi / 360) + extents.z / 2
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = Self.fov
        camera.look(at: bounds.center, from: bounds.center + [0, 0, distance], relativeTo: nil)
        content.add(camera)

        // The body map's studio light, so gold reads as metal, as on the emblem.
        if let url = Bundle.main.url(forResource: "BodyStudio", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path)?.cgImage,
           let environment = try? await EnvironmentResource(equirectangular: image, withName: "MascotStudio") {
            let light = Entity()
            light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 1.2))
            content.add(light)
            for model in Self.models(in: root) {
                model.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            }
        }

        let key = DirectionalLight()
        key.light.color = UIColor(NorthColor.signal)
        key.light.intensity = 2200
        key.look(at: .zero, from: [-1.5, 2, 3], relativeTo: nil)
        content.add(key)
        let rim = DirectionalLight()
        rim.light.color = UIColor(NorthColor.mutedForeground)
        rim.light.intensity = 1200
        rim.look(at: .zero, from: [2, 1, -2], relativeTo: nil)
        content.add(rim)

        // The core's glowing meshes: the only ones the pulse touches.
        for model in Self.models(in: core) {
            guard let material = model.model?.materials.first as? PhysicallyBasedMaterial,
                  Self.glows(material) else { continue }
            glows.append((model, material.emissiveIntensity))
        }
        joints = Joints(body: body, head: head, eyes: eyes, pupils: pupils, bodyRest: body.position, pupilsRest: pupils.position)
    }

    func step(_ dt: TimeInterval) {
        guard let joints, let motion else { return }
        let dt = min(dt, 0.1)
        seconds += dt

        let entrance = motion.entrance.offsets(at: seconds)
        let hover = motion.hover?.value(at: seconds) ?? 0
        joints.body.position = joints.bodyRest + [0, Float(entrance.translateY + hover), 0]
        joints.body.orientation = simd_quatf(angle: Float(entrance.rotateYDegrees * .pi / 180), axis: [0, 1, 0])

        let tau = motion.lookAt.timeConstantSeconds
        now.headYawDegrees = MascotMotion.approach(now.headYawDegrees, target.headYawDegrees, dt: dt, tau: tau)
        now.headPitchDegrees = MascotMotion.approach(now.headPitchDegrees, target.headPitchDegrees, dt: dt, tau: tau)
        now.pupilX = MascotMotion.approach(now.pupilX, target.pupilX, dt: dt, tau: tau)
        now.pupilY = MascotMotion.approach(now.pupilY, target.pupilY, dt: dt, tau: tau)
        // Yaw, then pitch: the web's rotation order 'YXZ'.
        joints.head.orientation = simd_quatf(angle: Float(now.headYawDegrees * .pi / 180), axis: [0, 1, 0])
            * simd_quatf(angle: Float(now.headPitchDegrees * .pi / 180), axis: [1, 0, 0])
        joints.pupils.position = joints.pupilsRest + [Float(now.pupilX), Float(now.pupilY), 0]
        joints.eyes.scale = [1, Float(motion.blink.scaleY(at: seconds)), 1]

        if let glow = motion.coreGlow {
            let scale = Float(glow.value(at: seconds))
            for (model, base) in glows {
                guard var material = model.model?.materials.first as? PhysicallyBasedMaterial else { continue }
                let next = base * scale
                if abs(material.emissiveIntensity - next) > 0.01 {
                    material.emissiveIntensity = next
                    model.model?.materials = [material]
                }
            }
        }

        if !isLive, dt > 0 { isLive = true }
    }

    /// A point in the view's frame (side `size`), mapped to [-1, 1] with +y up.
    func setPointer(_ location: CGPoint, in size: CGFloat) {
        guard let motion, size > 0 else { return }
        let x = Double((location.x - size / 2) / (size / 2))
        let y = -Double((location.y - size / 2) / (size / 2))
        target = motion.lookAt.look(x: x, y: y)
    }

    func clearPointer() {
        target = .rest
    }

    private static func glows(_ material: PhysicallyBasedMaterial) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        material.emissiveColor.color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return r + g + b > 0.001
    }

    private static func models(in entity: Entity) -> [ModelEntity] {
        ((entity as? ModelEntity).map { [$0] } ?? []) + entity.children.flatMap { models(in: $0) }
    }
}
