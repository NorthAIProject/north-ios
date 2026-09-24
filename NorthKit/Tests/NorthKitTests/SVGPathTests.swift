import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import NorthKit

/// The parser is judged against an independent renderer: each fixture is a real
/// exercise frame, with a reference PNG rendered by librsvg (`rsvg-convert`).
/// The parsed path is filled with Core Graphics at the same size, and the two
/// coverage masks must agree. Chosen to stress the grammar: the frames with the
/// most arcs, one with smooth quadratics, one opening with a relative move.
///
/// Rendered at the art's native 512 points. Agreement measures 0.986–0.990
/// on every fixture, including push-up with a single arc, and a diff image
/// shows the remainder as a one-pixel fringe along every outline: two
/// antialiasers disagreeing about edge pixels, not a shape parsed wrong. A
/// half-pixel offset drops agreement to 0.63, so the fixtures are aligned.
struct SVGPathTests {
    static let fixtures = ["push-up_frame-1", "arm-circles_frame-1", "belt-squat_frame-3",
                           "rowing_frame-2", "walking_frame-2", "hip-abduction-machine_frame-2"]

    @Test(arguments: fixtures)
    func matchesAnIndependentRenderer(_ name: String) throws {
        let directory = try #require(Bundle.module.resourceURL).appending(path: "ArtFixtures")
        let data = try String(contentsOf: directory.appending(path: "\(name).path"), encoding: .utf8)
        let reference = try alphaMask(ofPNGAt: directory.appending(path: "\(name).png"))

        let path = try SVGPath.parse(data)
        let rendered = alphaMask(filling: path, viewBox: 512, size: reference.size)

        let agreement = overlap(rendered, reference.pixels)
        #expect(agreement > 0.98, "\(name): only \(agreement) of covered pixels agree with librsvg")
    }

    @Test func readsSVGsCompactNumberForms() throws {
        // "1.5.5" is two numbers, "-2-3" is two, flags run into the next number.
        let path = try SVGPath.parse("M0 0l1.5.5-2-3a5 5 0 011 1z")
        #expect(!path.isEmpty)
        #expect(path.boundingBoxOfPath.minY < 0)
    }

    @Test func aFirstRelativeMoveCountsFromTheOrigin() throws {
        let path = try SVGPath.parse("m10 20h5v5z")
        #expect(path.boundingBoxOfPath == CGRect(x: 10, y: 20, width: 5, height: 5))
    }

    @Test func rejectsDataThatDoesNotStartWithAMove() {
        #expect(throws: SVGPath.ParseError.noInitialMove) { try SVGPath.parse("L10 10") }
    }

    // MARK: - Masks

    struct Mask {
        let size: Int
        let pixels: [UInt8]
    }

    private func alphaMask(ofPNGAt url: URL) throws -> Mask {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return Mask(size: image.width, pixels: draw(size: image.width) { $0.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.width)) })
    }

    private func alphaMask(filling path: CGPath, viewBox: CGFloat, size: Int) -> [UInt8] {
        draw(size: size) { context in
            // SVG's y axis points down; Core Graphics' points up.
            context.translateBy(x: 0, y: CGFloat(size))
            context.scaleBy(x: CGFloat(size) / viewBox, y: -CGFloat(size) / viewBox)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        }
    }

    private func draw(size: Int, _ body: (CGContext) -> Void) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: size * size)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                    bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            body(context)
        }
        return pixels
    }

    /// Intersection over union of the two coverage masks, counting a pixel as
    /// covered above half opacity, so antialiasing differences at the edges
    /// between two renderers do not count as disagreement.
    private func overlap(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var both = 0, either = 0
        for i in a.indices {
            let x = a[i] > 127, y = b[i] > 127
            if x && y { both += 1 }
            if x || y { either += 1 }
        }
        return either == 0 ? 1 : Double(both) / Double(either)
    }
}
