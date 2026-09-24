import SwiftUI

/// One pose, drawn from SVG path data as a native shape.
///
/// The path is parsed once, when the shape is made, and scaled to whatever
/// rect SwiftUI offers, so the art stays sharp at any size and takes any fill.
public struct ExercisePose: Shape {
    // SwiftUI's Path rather than CGPath: it is Sendable, which Shape requires.
    private let path: Path
    private let size: CGFloat

    /// - Parameters:
    ///   - data: SVG path data for one frame.
    ///   - size: the side of the square the data is drawn in (512 for the
    ///     catalog art).
    public init(data: String, size: CGFloat) throws {
        self.path = Path(try SVGPath.parse(data))
        self.size = size
    }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / size
        let transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return path.applying(transform)
    }
}

/// An exercise's pose frames, played as a loop.
///
/// Frames cross-fade on a fixed beat (the web cycles the same three frames).
/// With Reduce Motion on, or when `isPlaying` is false, it shows the first
/// frame still: the movement is still readable, and nothing moves that the
/// person asked not to.
public struct ExerciseArtView: View {
    private let poses: [ExercisePose]
    private let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds each pose holds before the next fades in.
    static let beat: TimeInterval = 0.9

    /// Frames that fail to parse are dropped rather than failing the view: two
    /// good poses still show the movement.
    public init(frames: [String], size: Int, isPlaying: Bool = true) {
        self.poses = frames.compactMap { try? ExercisePose(data: $0, size: CGFloat(size)) }
        self.isPlaying = isPlaying
    }

    public var body: some View {
        if poses.isEmpty {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
        } else if reduceMotion || !isPlaying || poses.count == 1 {
            pose(0)
        } else {
            TimelineView(.periodic(from: .now, by: Self.beat)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / Self.beat) % poses.count
                ZStack {
                    ForEach(poses.indices, id: \.self) { i in
                        pose(i).opacity(i == index ? 1 : 0)
                    }
                }
                // A short fade reads as a step between poses, like the web's
                // loop; a long one leaves two ghosted poses on screen.
                .animation(.easeInOut(duration: 0.12), value: index)
            }
        }
    }

    private func pose(_ index: Int) -> some View {
        poses[index]
            .fill(.foreground, style: FillStyle(eoFill: true, antialiased: true))
            .aspectRatio(1, contentMode: .fit)
    }
}
