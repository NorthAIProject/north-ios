#if DEBUG || BETA
import NorthKit
import RealityKit
import SwiftUI

/// The Khepri emblem in 3D, for the login screen (Debug and Beta only).
///
/// A non-AR `RealityView` with a virtual camera, drawn transparent over
/// SwiftUI. The flat `NorthBrand.mark` shows until the first frame and stays
/// under Reduce Motion, Low Power Mode, or a model that fails to load. Motion
/// values come from `EmblemMotion` (emblem-motion.json); this view applies
/// them. Release excludes this file, `EmblemMotion.swift`, `Emblem.usdz` and
/// `emblem-motion.json` (`scripts/configure-build-variants.rb`), and
/// `scripts/verify-release-excludes.sh` proves it. DESIGN.md, 3D Emblem.
struct Emblem3DView: View {
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var stage = EmblemStage()

    private var draws: Bool { !reduceMotion && !lowPower && stage.motion != nil }

    var body: some View {
        ZStack {
            NorthBrand.mark
                .resizable()
                .scaledToFit()
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

/// Holds the scene and turns each frame's time into transforms. Main actor:
/// RealityKit delivers scene updates there.
@MainActor @Observable
final class EmblemStage {
    let motion = try? EmblemMotion.load()
    private(set) var isLive = false
    @ObservationIgnored var updates: EventSubscription?

    @ObservationIgnored private let pivot = Entity()
    @ObservationIgnored private let key = DirectionalLight()
    @ObservationIgnored private var sun: ModelEntity?
    @ObservationIgnored private var sunBase: Float = 1
    @ObservationIgnored private var seconds: Double = 0
    @ObservationIgnored private var target = (yaw: 0.0, pitch: 0.0)
    @ObservationIgnored private var yaw = 0.0
    @ObservationIgnored private var pitch = 0.0
    @ObservationIgnored private var loaded = false

    private static let fov: Float = 30
    private static let margin: Float = 1.08
    private static let keyRadius: Float = 3
    private static let keyElevation: Float = 0.6

    func load(into content: inout RealityViewCameraContent) async {
        guard let model = try? await Entity(named: "Emblem") else { return }
        // The file wraps its meshes in Emblem/Root; start below the wrapper.
        let root = model.findEntity(named: "Root") ?? model
        pivot.addChild(root)
        content.add(pivot)

        let extents = root.visualBounds(relativeTo: nil).extents
        let distance = max(extents.x, extents.y) * Self.margin / 2 / tan(Self.fov * .pi / 360) + extents.z / 2
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = Self.fov
        camera.look(at: .zero, from: [0, 0, distance], relativeTo: nil)
        content.add(camera)

        // The body map's studio light, so gold reads as metal on both screens.
        if let url = Bundle.main.url(forResource: "BodyStudio", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path)?.cgImage,
           let environment = try? await EnvironmentResource(equirectangular: image, withName: "EmblemStudio") {
            let light = Entity()
            light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 1.2))
            content.add(light)
            for model in Self.models(in: root) {
                model.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            }
        }

        key.light.color = UIColor(NorthColor.signal)
        key.light.intensity = 2200
        content.add(key)
        let rim = DirectionalLight()
        rim.light.color = UIColor(NorthColor.mutedForeground)
        rim.light.intensity = 1200
        rim.look(at: .zero, from: [2, 1, -2], relativeTo: nil)
        content.add(rim)

        if let face = root.findEntity(named: "Emblem_sun_face") as? ModelEntity,
           let material = face.model?.materials.first as? PhysicallyBasedMaterial {
            sun = face
            sunBase = material.emissiveIntensity
        }
        loaded = true
    }

    func step(_ dt: TimeInterval) {
        guard loaded, let motion else { return }
        let dt = min(dt, 0.1)
        seconds += dt

        let entrance = motion.entrance.offsets(at: seconds)
        let tau = motion.pointer.timeConstantSeconds
        yaw = EmblemMotion.approach(yaw, target.yaw, dt: dt, tau: tau)
        pitch = EmblemMotion.approach(pitch, target.pitch, dt: dt, tau: tau)
        pivot.position = [0, Float(entrance.translateY), 0]
        // Yaw, then pitch: the web's rotation order 'YXZ'.
        pivot.orientation = simd_quatf(angle: Float((entrance.rotateYDegrees + yaw) * .pi / 180), axis: [0, 1, 0])
            * simd_quatf(angle: Float(pitch * .pi / 180), axis: [1, 0, 0])

        if let sun, let pulse = motion.sunPulse, var material = sun.model?.materials.first as? PhysicallyBasedMaterial {
            let next = sunBase * Float(pulse.value(at: seconds))
            if abs(material.emissiveIntensity - next) > 0.01 {
                material.emissiveIntensity = next
                sun.model?.materials = [material]
            }
        }
        let azimuth = Float((motion.lightSweep?.value(at: seconds) ?? 0) * .pi / 180)
        key.look(
            at: .zero,
            from: [sin(azimuth) * Self.keyRadius, Self.keyElevation * Self.keyRadius, cos(azimuth) * Self.keyRadius],
            relativeTo: nil
        )

        if !isLive, dt > 0 { isLive = true }
    }

    /// A point in the emblem's frame (side `size`), mapped to [-1, 1] with +y up.
    func setPointer(_ location: CGPoint, in size: CGFloat) {
        guard let motion, size > 0 else { return }
        let x = Double((location.x - size / 2) / (size / 2))
        let y = -Double((location.y - size / 2) / (size / 2))
        let tilt = motion.pointer.tilt(x: x, y: y)
        target = (tilt.yawDegrees, tilt.pitchDegrees)
    }

    func clearPointer() {
        target = (0, 0)
    }

    private static func models(in entity: Entity) -> [ModelEntity] {
        ((entity as? ModelEntity).map { [$0] } ?? []) + entity.children.flatMap { models(in: $0) }
    }
}
#endif
