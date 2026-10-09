import NorthAPI
import NorthKit
import RealityKit
import SwiftUI

/// The body figure: the skin of a body cut into one region per muscle key,
/// coloured by how much recent training heated each one. The same figure and
/// the same payload (`GET /body/map`) as the web; this view only paints it.
///
/// `BodyMap.usdz` is written by the web repo's `scripts/bodymap` with one mesh
/// per region, named by its key (`quads`, `delts`…) plus `base` for skin with
/// no muscle under it. Recolouring sets one material per region, and a tap
/// resolves to a key by the entity's name.
struct BodyMapView: View {
    /// Region key → 0…1. Missing means untrained.
    let heat: [String: Double]
    /// Show the back instead of the front; nil lets the heat decide.
    var side: BodySide?
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
                BodyFigure.addCameraAndLights(to: &content)
            } update: { content in
                guard let figure = content.entities.first(where: { $0.name == BodyFigure.rootName }) else { return }
                figure.orientation = simd_quatf(angle: yaw(at: context.date), axis: [0, 1, 0])
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
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    let key = value.entity.name
                    if key != BodyFigure.baseRegion { onSelect?(key) }
                }
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
    static let baseRegion = "base"
    static let frontYaw: Float = 0.45
    static let sway: Float = 0.35
    static let swayPeriod = 8.0
    /// The figure's height in metres, soles at y = 0 (see scripts/bodymap).
    static let height: Float = 1.44

    /// The figure, or nil if the bundle has no BodyMap.usdz, which leaves
    /// the card without a figure rather than crashing it.
    static func load() async -> Entity? {
        guard let loaded = try? await Entity(named: "BodyMap") else { return nil }
        let root = Entity()
        root.name = rootName
        root.addChild(loaded)
        for region in regions(in: root) {
            region.components.set(InputTargetComponent())
            if let mesh = region.model?.mesh, let shape = try? await ShapeResource.generateStaticMesh(from: mesh) {
                region.components.set(CollisionComponent(shapes: [shape]))
            }
        }
        return root
    }

    static func addCameraAndLights(to content: inout RealityViewCameraContent) {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 30
        let distance = height * 1.04 / 2 / tan(Float.pi / 12)
        camera.look(at: [0, height * 0.5, 0], from: [0, height * 0.52, distance], relativeTo: nil)
        content.add(camera)

        // A warm key, a cool fill and a back rim: soft studio light, so the
        // figure has form without the colours washing out.
        for (color, intensity, from) in [
            (UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1), Float(2600), SIMD3<Float>(2, 3, 3)),
            (UIColor(red: 0.86, green: 0.91, blue: 1, alpha: 1), Float(900), SIMD3<Float>(-3, 1.5, 2)),
            (UIColor(red: 0.56, green: 0.78, blue: 1, alpha: 1), Float(1400), SIMD3<Float>(-1, 2, -3)),
        ] {
            let light = DirectionalLight()
            light.light.color = color
            light.light.intensity = intensity
            light.look(at: [0, height * 0.5, 0], from: from, relativeTo: nil)
            content.add(light)
        }
    }

    static func regions(in root: Entity) -> [ModelEntity] {
        var out: [ModelEntity] = []
        var stack = [root]
        while let entity = stack.popLast() {
            if let model = entity as? ModelEntity, !model.name.isEmpty { out.append(model) }
            stack.append(contentsOf: entity.children)
        }
        return out
    }

    /// What the figure was last painted with, so the per-frame update (the
    /// sway runs it 30 times a second) does not rebuild every material.
    struct Painted: Component, Equatable {
        var heat: [String: Double]
        var dark: Bool
    }

    struct Palette {
        let idle: UIColor
        let base: UIColor
        let heatLow: UIColor
        let ember: UIColor
        let dark: Bool

        init(_ scheme: ColorScheme) {
            let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
            idle = UIColor(NorthColor.Body.idle).resolvedColor(with: traits)
            base = UIColor(NorthColor.Body.base).resolvedColor(with: traits)
            heatLow = UIColor(NorthColor.Body.heatLow).resolvedColor(with: traits)
            ember = UIColor(NorthColor.ember).resolvedColor(with: traits)
            dark = scheme == .dark
        }

        /// Untrained is idle; any heat starts a quarter of the way up the
        /// ramp, so a light touch still reads as warm. Same ramp as the web.
        func color(region: String, heat: Double) -> UIColor {
            if region == BodyFigure.baseRegion { return base }
            guard heat > 0 else { return idle }
            return mix(heatLow, ember, CGFloat(0.25 + 0.75 * min(heat, 1)))
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
        if root.components[Painted.self] == painted { return }
        root.components.set(painted)
        for region in regions(in: root) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: palette.color(region: region.name, heat: heat[region.name] ?? 0))
            material.roughness = 0.62
            material.metallic = 0.0
            region.model?.materials = [material]
        }
    }
}

/// The figure's words: region names, dates and the summary VoiceOver reads.
enum BodyMapText {
    static let names: [String: String.LocalizationValue] = [
        "abs": "Abs", "adductors": "Adductors", "biceps": "Biceps", "calves": "Calves", "chest": "Chest",
        "delts": "Shoulders", "erectors": "Lower back", "forearms": "Forearms", "glutes": "Glutes",
        "hamstrings": "Hamstrings", "lats": "Lats", "neck": "Neck", "quads": "Quads", "traps": "Upper back",
        "triceps": "Triceps",
    ]

    /// A region's name; an id this build does not know shows as itself.
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
    /// Region key → intensity, the shape `BodyMapView` paints.
    var heat: [String: Double] {
        Dictionary(muscles.map { ($0.id, $0.intensity) }, uniquingKeysWith: max)
    }

    func muscle(_ id: String) -> Components.Schemas.BodyMapMuscle? {
        muscles.first { $0.id == id }
    }
}
