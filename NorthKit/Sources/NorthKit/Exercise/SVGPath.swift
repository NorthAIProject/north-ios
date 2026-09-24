import CoreGraphics
import Foundation

/// Parses SVG path data (the `d` attribute) into a `CGPath`.
///
/// The exercise artwork arrives from the server as path data rather than as
/// images, so it can be drawn as a native shape. This covers the whole path
/// grammar: move, line, horizontal, vertical, cubic, smooth cubic, quadratic,
/// smooth quadratic, arc and close, absolute and relative, with repeated
/// arguments and the compact number forms SVG allows (`1.5.5` is two numbers,
/// `1-2` is two numbers, arc flags may run together).
///
/// Arcs have no `CGPath` equivalent, so they are converted to cubic Béziers
/// using the endpoint-to-centre method in the SVG specification (F.6.5).
public enum SVGPath {
    public enum ParseError: Error, Equatable {
        case unexpectedCharacter(Character, offset: Int)
        case missingNumber(command: Character, offset: Int)
        case noInitialMove
    }

    public static func parse(_ data: String) throws -> CGPath {
        var scanner = Scanner(Array(data.utf8))
        let path = CGMutablePath()

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        // The last control point, for the smooth variants that reflect it.
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: UInt8?
        var sawMove = false

        while true {
            scanner.skipSeparators()
            guard let next = scanner.peek() else { break }

            if Scanner.isCommand(next) {
                command = next
                scanner.advance()
            } else if command == nil {
                throw ParseError.unexpectedCharacter(Character(UnicodeScalar(next)), offset: scanner.offset)
            }
            // A number with no command repeats the previous one.
            guard let op = command else { break }

            let relative = op >= 0x61 // lowercase
            let base = relative ? current : .zero
            func point() throws -> CGPoint {
                let x = try scanner.number(for: op)
                let y = try scanner.number(for: op)
                return CGPoint(x: base.x + x, y: base.y + y)
            }

            if !sawMove, op != 0x4D, op != 0x6D { throw ParseError.noInitialMove }

            switch op {
            case 0x4D, 0x6D: // M m
                current = try point()
                subpathStart = current
                path.move(to: current)
                sawMove = true
                // Extra pairs after a move are implicit line-tos.
                command = relative ? 0x6C : 0x4C
                lastCubicControl = nil; lastQuadControl = nil

            case 0x4C, 0x6C: // L l
                current = try point()
                path.addLine(to: current)
                lastCubicControl = nil; lastQuadControl = nil

            case 0x48, 0x68: // H h
                let x = try scanner.number(for: op)
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubicControl = nil; lastQuadControl = nil

            case 0x56, 0x76: // V v
                let y = try scanner.number(for: op)
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastCubicControl = nil; lastQuadControl = nil

            case 0x43, 0x63: // C c
                let c1 = try point(), c2 = try point(), end = try point()
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCubicControl = c2; lastQuadControl = nil
                current = end

            case 0x53, 0x73: // S s
                let c1 = lastCubicControl.map { reflect($0, around: current) } ?? current
                let c2 = try point(), end = try point()
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCubicControl = c2; lastQuadControl = nil
                current = end

            case 0x51, 0x71: // Q q
                let c = try point(), end = try point()
                path.addQuadCurve(to: end, control: c)
                lastQuadControl = c; lastCubicControl = nil
                current = end

            case 0x54, 0x74: // T t
                let c = lastQuadControl.map { reflect($0, around: current) } ?? current
                let end = try point()
                path.addQuadCurve(to: end, control: c)
                lastQuadControl = c; lastCubicControl = nil
                current = end

            case 0x41, 0x61: // A a
                let rx = try scanner.number(for: op)
                let ry = try scanner.number(for: op)
                let rotation = try scanner.number(for: op)
                let largeArc = try scanner.flag(for: op)
                let sweep = try scanner.flag(for: op)
                let end = try point()
                addArc(to: path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep)
                current = end
                lastCubicControl = nil; lastQuadControl = nil

            case 0x5A, 0x7A: // Z z
                path.closeSubpath()
                current = subpathStart
                lastCubicControl = nil; lastQuadControl = nil
                // Z takes no arguments; a number after it needs a new command.
                command = nil

            default:
                throw ParseError.unexpectedCharacter(Character(UnicodeScalar(op)), offset: scanner.offset)
            }
        }
        return path
    }

    private static func reflect(_ point: CGPoint, around center: CGPoint) -> CGPoint {
        CGPoint(x: 2 * center.x - point.x, y: 2 * center.y - point.y)
    }

    /// Appends an elliptical arc as cubic Béziers, one per quarter turn or
    /// less (SVG 1.1 appendix F.6.5 and F.6.6).
    static func addArc(to path: CGMutablePath, from start: CGPoint, to end: CGPoint,
                       rx: CGFloat, ry: CGFloat, rotation degrees: CGFloat, largeArc: Bool, sweep: Bool) {
        if start == end { return }
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 {
            path.addLine(to: end)
            return
        }

        let phi = degrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        // Step 1: the midpoint, in the ellipse's own axes.
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Radii too small to reach are scaled up just enough (F.6.6).
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale; ry *= scale
        }

        // Step 2: the centre, in the ellipse's axes.
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coefficient = sqrt(max(0, numerator / denominator))
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx

        // Step 3: the centre, in path coordinates.
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        // Step 4: start angle and sweep.
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var value = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 { value = -value }
            return value
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        // Each segment spans at most 90°, where the cubic approximation of a
        // circular arc is accurate to a fraction of a point at this size.
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let handle = 4 / 3 * tan(step / 4)

        func pointOnEllipse(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }

        var t = theta1
        for index in 0..<segments {
            let t2 = t + step
            let p1 = pointOnEllipse(t), p2 = index == segments - 1 ? end : pointOnEllipse(t2)
            let d1 = derivative(t), d2 = derivative(t2)
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + handle * d1.x, y: p1.y + handle * d1.y),
                          control2: CGPoint(x: p2.x - handle * d2.x, y: p2.y - handle * d2.y))
            t = t2
        }
    }
}

/// Reads numbers and flags from path data, byte by byte.
private struct Scanner {
    let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func peek() -> UInt8? { offset < bytes.count ? bytes[offset] : nil }
    mutating func advance() { offset += 1 }

    static func isCommand(_ b: UInt8) -> Bool {
        switch b {
        case 0x4D, 0x6D, 0x4C, 0x6C, 0x48, 0x68, 0x56, 0x76, 0x43, 0x63,
             0x53, 0x73, 0x51, 0x71, 0x54, 0x74, 0x41, 0x61, 0x5A, 0x7A: true
        default: false
        }
    }

    mutating func skipSeparators() {
        while let b = peek(), b == 0x20 || b == 0x2C || b == 0x09 || b == 0x0A || b == 0x0D { advance() }
    }

    /// An arc flag: a single 0 or 1, which may run straight into the next
    /// number ("a1 1 0 011 1" has flags 0 and 1, then 1 1).
    mutating func flag(for command: UInt8) throws -> Bool {
        skipSeparators()
        guard let b = peek(), b == 0x30 || b == 0x31 else {
            throw SVGPath.ParseError.missingNumber(command: Character(UnicodeScalar(command)), offset: offset)
        }
        advance()
        return b == 0x31
    }

    /// One number in SVG's grammar: optional sign, digits, at most one dot,
    /// optional exponent. A second dot or a sign starts the next number.
    mutating func number(for command: UInt8) throws -> CGFloat {
        skipSeparators()
        let start = offset
        if let b = peek(), b == 0x2B || b == 0x2D { advance() }
        var sawDigit = false, sawDot = false
        while let b = peek() {
            if b >= 0x30 && b <= 0x39 { sawDigit = true; advance() }
            else if b == 0x2E && !sawDot { sawDot = true; advance() }
            else { break }
        }
        if sawDigit, let b = peek(), b == 0x65 || b == 0x45 {
            let beforeExponent = offset
            advance()
            if let s = peek(), s == 0x2B || s == 0x2D { advance() }
            var exponentDigits = false
            while let d = peek(), d >= 0x30 && d <= 0x39 { exponentDigits = true; advance() }
            if !exponentDigits { offset = beforeExponent }
        }
        guard sawDigit, let value = Double(String(decoding: bytes[start..<offset], as: UTF8.self)) else {
            offset = start
            throw SVGPath.ParseError.missingNumber(command: Character(UnicodeScalar(command)), offset: start)
        }
        return CGFloat(value)
    }
}
