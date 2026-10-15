import RealityKit
import SwiftUI
import Testing
@testable import khepri

struct BodyMapTests {
    /// Only meshes named by a muscle key are muscles; the skin and its inside
    /// are not, so a tap can never land on them and heat never paints them.
    @MainActor @Test func musclesAreTheNamedMeshes() {
        let root = Entity()
        for name in ["shell", "shell-core", "quads", "delts", ""] {
            let model = ModelEntity(mesh: .generateBox(size: 0.1))
            model.name = name
            root.addChild(model)
        }
        #expect(BodyFigure.models(in: root).map(\.name).sorted() == ["delts", "quads", "shell", "shell-core"])
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
}
