import NorthAPI
import NorthKit
import RealityKit
import SwiftUI

/// The body figure: the muscles of an anatomical atlas, one mesh per muscle
/// key, inside the skin of a body, coloured by how much recent training heated
/// each one. The same figure and the same payload (`GET /body/map`) as the
/// web; this view only paints it.
///
/// The web repo's `scripts/bodymap` writes `BodyMap.usdz`, one mesh per muscle
/// named by its key (`quads`, `delts`…), and `BodyShell.bin`, the skin with
/// its shape keys. The skin is an outline only: clear facing the camera, firm
/// at the silhouette, so the muscles read as the body. Recolouring sets one
/// material per muscle, and a tap resolves to a key by the entity's name; the
/// skin is not a tap target.
struct BodyMapView: View {
    /// Muscle key → 0…1. Missing means untrained.
    let heat: [String: Double]
    /// Show the back instead of the front; nil lets the heat decide.
    var side: BodySide?
    /// The person's shape, from their latest progress check. Only their own
    /// figure is shaped; one that shows what an exercise works stays as
    /// modelled.
    var shape: BodyShape = .modelled
    var onSelect: ((String) -> Void)?

    @State private var dragOffset: Float = 0
    @State private var dragStart: Float = 0
    @State private var lastDrag: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            RealityView { content in
                guard let figure = await BodyFigure.load() else { return }
                content.add(figure)
                await BodyFigure.addCameraAndLights(to: &content, around: figure)
            } update: { content in
                guard let figure = content.entities.first(where: { $0.name == BodyFigure.rootName }) else { return }
                figure.orientation = simd_quatf(angle: yaw(at: context.date), axis: [0, 1, 0])
                BodyFigure.reshape(figure, to: shape)
                BodyFigure.paint(figure, heat: heat, palette: .init(colorScheme))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    dragOffset = dragStart + Float(value.translation.width) * 0.012
                    lastDrag = .now
                }
                .onEnded { _ in dragStart = dragOffset }
        )
        .gesture(
            // Only the muscles carry collision, so only they can be hit.
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in onSelect?(value.entity.name) }
        )
        .accessibilityElement()
        .accessibilityLabel("Body")
        .accessibilityValue(BodyMapText.summary(heat))
    }

    /// Faces a front three-quarter (or the back, when back muscles are the
    /// hottest) and sways slowly about it, except for reduced motion or for a
    /// few seconds after a drag.
    private func yaw(at date: Date) -> Float {
        let facing = (side ?? BodySide.hottest(heat)) == .back ? Float.pi + BodyFigure.frontYaw : BodyFigure.frontYaw
        guard !reduceMotion, date.timeIntervalSince(lastDrag) > 4 else { return facing + dragOffset }
        let phase = date.timeIntervalSinceReferenceDate / BodyFigure.swayPeriod * 2 * .pi
        return facing + dragOffset + Float(sin(phase)) * BodyFigure.sway
    }
}

enum BodySide: String, CaseIterable, Identifiable {
    case front, back
    var id: Self { self }

    /// Muscles mostly seen from behind; when one of these is the hottest the
    /// figure turns its back, so a back day is not hidden.
    static let backRegions: Set<String> = ["traps", "lats", "erectors", "glutes", "hamstrings", "calves", "triceps", "neck"]

    static func hottest(_ heat: [String: Double]) -> BodySide {
        let back = heat.filter { backRegions.contains($0.key) }.values.max() ?? 0
        let front = heat.filter { !backRegions.contains($0.key) }.values.max() ?? 0
        return back > front ? .back : .front
    }
}

/// Loading, lighting and colouring the figure.
enum BodyFigure {
    static let rootName = "body-map"
    static let shellRegion = "shell"
    /// The skin's edge, as on the web (viewer.js SHELL_EDGE_ALPHA and
    /// SHELL_EDGE_POWER): how opaque the silhouette gets, and how thin it is.
    static let shellEdgeAlpha: Float = 0.9
    static let shellEdgePower: Float = 4
    static let frontYaw: Float = 0.45
    static let sway: Float = 0.35
    static let swayPeriod = 8.0
    /// The figure's height in metres, soles at y = 0 (see scripts/bodymap).
    static let height: Float = 1.44

    /// Built once per process and cloned per view: Today and Training each
    /// show a figure, and the collision meshes are the expensive part.
    @MainActor private static var template: Task<Entity?, Never>?

    /// A figure of its own, or nil if the bundle has no BodyMap.usdz, which
    /// leaves the card without a figure rather than crashing it.
    @MainActor static func load() async -> Entity? {
        if template == nil { template = Task { await build() } }
        return await template?.value?.clone(recursive: true)
    }

    @MainActor private static func build() async -> Entity? {
        guard let loaded = try? await Entity(named: "BodyMap") else { return nil }
        let root = Entity()
        root.name = rootName
        root.addChild(loaded)
        if let skin = BodyShell.bundled, let mesh = try? skin.mesh(.modelled) {
            let shell = ModelEntity(mesh: mesh)
            shell.name = shellRegion
            root.addChild(shell)
        }
        for muscle in muscles(in: root) {
            muscle.components.set(InputTargetComponent())
            if let mesh = muscle.model?.mesh, let shape = try? await ShapeResource.generateStaticMesh(from: mesh) {
                muscle.components.set(CollisionComponent(shapes: [shape]))
            }
        }
        return root
    }

    @MainActor static func addCameraAndLights(to content: inout RealityViewCameraContent, around figure: Entity) async {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 30
        let distance = height * 1.04 / 2 / tan(Float.pi / 12)
        camera.look(at: [0, height * 0.5, 0], from: [0, height * 0.52, distance], relativeTo: nil)
        content.add(camera)

        // The web viewer's studio rig, rendered by scripts/bodymap into
        // BodyStudio.png: the same light on both platforms.
        if let url = Bundle.main.url(forResource: "BodyStudio", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path)?.cgImage,
           let environment = try? await EnvironmentResource(equirectangular: image, withName: "BodyStudio") {
            let light = Entity()
            // The image stores radiance over the rig's brightest panel (6.5);
            // the exponent brings it back to the web's level, environment
            // intensity included.
            light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 2.0))
            content.add(light)
            for model in models(in: figure) {
                model.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            }
        }

        // Shaping only: a warm key and a cool rim; the environment does the rest.
        for (color, intensity, from) in [
            (UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1), Float(1200), SIMD3<Float>(2, 3, 3)),
            (UIColor(red: 0.56, green: 0.78, blue: 1, alpha: 1), Float(900), SIMD3<Float>(-2, 1, -3)),
        ] {
            let light = DirectionalLight()
            light.light.color = color
            light.light.intensity = intensity
            light.look(at: [0, height * 0.5, 0], from: from, relativeTo: nil)
            content.add(light)
        }

        if let shadow = await contactShadow() { content.add(shadow) }
    }

    /// A soft disc under the feet, so the figure stands on something: a
    /// black texture whose alpha fades out from the centre, drawn with the
    /// texture's alpha as its opacity.
    @MainActor private static func contactShadow() async -> ModelEntity? {
        let size = 128
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let centre = CGPoint(x: size / 2, y: size / 2)
            let colors = [UIColor(white: 0, alpha: 0.5).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: CGFloat(size) / 2, options: [])
            }
        }
        guard let cgImage = image.cgImage, let texture = try? await TextureResource(image: cgImage, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        // Narrower than the web's disc: the Today card frames the figure
        // tall and narrow, and a wider disc would be cut off at the sides.
        let disc = ModelEntity(mesh: .generatePlane(width: height * 0.4, depth: height * 0.4), materials: [material])
        disc.position.y = 0.001
        return disc
    }

    /// Every mesh of the figure: the muscles and the skin.
    static func models(in root: Entity) -> [ModelEntity] {
        var out: [ModelEntity] = []
        var stack = [root]
        while let entity = stack.popLast() {
            if let model = entity as? ModelEntity, !model.name.isEmpty { out.append(model) }
            stack.append(contentsOf: entity.children)
        }
        return out
    }

    /// The muscles alone: the meshes named by a muscle key.
    static func muscles(in root: Entity) -> [ModelEntity] {
        models(in: root).filter { BodyMapText.names[$0.name] != nil }
    }

    /// What the figure was last painted with, so the per-frame update (the
    /// sway runs it 30 times a second) does not rebuild every material.
    struct Painted: Component, Equatable {
        var heat: [String: Double]
        var dark: Bool
    }

    /// The shape the skin was last built for, so the per-frame update only
    /// rebuilds it when a new check changes the weights.
    struct Shaped: Component, Equatable {
        var shape: BodyShape
    }

    static func reshape(_ root: Entity, to shape: BodyShape) {
        Shaped.registerComponent()
        let before = root.components[Shaped.self]?.shape ?? .modelled
        guard before != shape,
              let shell = root.findEntity(named: shellRegion) as? ModelEntity,
              let skin = BodyShell.bundled,
              let mesh = try? skin.mesh(shape)
        else { return }
        shell.model?.mesh = mesh
        root.components.set(Shaped(shape: shape))
    }

    struct Palette {
        let idle: UIColor
        let shell: UIColor
        let rim: UIColor
        let rimStrength: Float
        let heatLow: UIColor
        let ember: UIColor
        let dark: Bool

        init(_ scheme: ColorScheme) {
            let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
            idle = UIColor(NorthColor.Body.idle).resolvedColor(with: traits)
            shell = UIColor(NorthColor.Body.shell).resolvedColor(with: traits)
            // The web viewer's rim colours (viewer.js PALETTES).
            rim = scheme == .dark
                ? UIColor(red: 0x8E / 255, green: 0xC6 / 255, blue: 1, alpha: 1)
                : UIColor(red: 0x2B / 255, green: 0x3A / 255, blue: 0x52 / 255, alpha: 1)
            rimStrength = scheme == .dark ? 0.3 : 0.15
            heatLow = UIColor(NorthColor.Body.heatLow).resolvedColor(with: traits)
            ember = UIColor(NorthColor.ember).resolvedColor(with: traits)
            dark = scheme == .dark
        }

        /// Untrained is idle; any heat starts a little way up the ramp, so a
        /// light touch still reads as warm. Same ramp as the web.
        func color(heat: Double) -> UIColor {
            guard heat > 0 else { return idle }
            return mix(heatLow, ember, CGFloat(0.15 + 0.85 * min(heat, 1)))
        }

        private func mix(_ from: UIColor, _ to: UIColor, _ fraction: CGFloat) -> UIColor {
            let start = rgb(from)
            let mixed = start + (rgb(to) - start) * Double(fraction)
            return UIColor(red: mixed.x, green: mixed.y, blue: mixed.z, alpha: 1)
        }

        private func rgb(_ color: UIColor) -> SIMD3<Double> {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return SIMD3(Double(red), Double(green), Double(blue))
        }
    }

    static func paint(_ root: Entity, heat: [String: Double], palette: Palette) {
        Painted.registerComponent()
        let painted = Painted(heat: heat, dark: palette.dark)
        let before = root.components[Painted.self]
        if before == painted { return }
        root.components.set(painted)
        for muscle in muscles(in: root) {
            muscle.model?.materials = [material(tint: palette.color(heat: heat[muscle.name] ?? 0), roughness: 0.55)]
        }
        guard before?.dark != palette.dark,
              let shell = root.findEntity(named: shellRegion) as? ModelEntity
        else { return }
        // Without the outline shader there is no skin at all: a flat
        // translucent fill is the grey second body the outline replaced.
        if let outline = outline(palette) {
            shell.model?.materials = [outline]
        } else {
            shell.isEnabled = false
        }
    }

    /// The skin's material: `bodyShellOutline` in BodyShell.metal.
    @MainActor private static let outlineShader: CustomMaterial.SurfaceShader? = {
        guard let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary() else { return nil }
        return CustomMaterial.SurfaceShader(named: "bodyShellOutline", in: library)
    }()

    @MainActor private static func outline(_ palette: Palette) -> CustomMaterial? {
        guard let shader = outlineShader,
              var material = try? CustomMaterial(surfaceShader: shader, lightingModel: .lit)
        else { return nil }
        material.baseColor = .init(tint: palette.shell)
        material.emissiveColor = .init(color: palette.rim)
        material.roughness = .init(floatLiteral: 0.4)
        material.custom.value = SIMD4(shellEdgeAlpha, shellEdgePower, palette.rimStrength, 0)
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.faceCulling = .back
        return material
    }

    private static func material(tint: UIColor, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = 0.0
        return material
    }
}

/// The figure's words: muscle names, dates and the summary VoiceOver reads.
enum BodyMapText {
    static let names: [String: String.LocalizationValue] = [
        "abs": "Abs", "adductors": "Adductors", "biceps": "Biceps", "calves": "Calves", "chest": "Chest",
        "delts": "Shoulders", "erectors": "Lower back", "forearms": "Forearms", "glutes": "Glutes",
        "hamstrings": "Hamstrings", "lats": "Lats", "neck": "Neck", "quads": "Quads", "traps": "Upper back",
        "triceps": "Triceps",
    ]

    /// A muscle's name; an id this build does not know shows as itself.
    static func name(_ id: String) -> String {
        names[id].map { String(localized: $0) } ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func lastTrained(_ day: String?) -> String {
        guard let day, let date = CalendarDay.date(from: day) else { return String(localized: "Not trained yet") }
        return String(localized: "Last trained \(date.formatted(.dateTime.day().month(.wide)))")
    }

    static func summary(_ heat: [String: Double]) -> String {
        let hot = heat.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { name($0.key) }
        return hot.isEmpty ? String(localized: "No recent training") : String(localized: "Trained recently: \(hot.formatted(.list(type: .and)))")
    }
}

extension BodyMap {
    /// Muscle key → intensity, the shape `BodyMapView` paints.
    var heat: [String: Double] {
        Dictionary(muscles.map { ($0.id, $0.intensity) }, uniquingKeysWith: max)
    }

    func muscle(_ id: String) -> Components.Schemas.BodyMapMuscle? {
        muscles.first { $0.id == id }
    }
}
