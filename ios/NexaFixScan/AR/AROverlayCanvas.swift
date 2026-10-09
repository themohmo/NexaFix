import SwiftUI
import ARKit
import UIKit
import NexaFixCore

/// Draws an `OverlayScene` over the live camera image: thin wireframe and dimension lines, angle arcs, and
/// labels on dark chips. Every frame it reads the camera pose from `session.currentFrame`, projects the
/// scene's world points to the screen and lets `LabelLayout` decide which labels fit.
///
/// Rules this view keeps:
/// - Nothing animates position. Lines and labels are glued to the world every frame; only a label's
///   opacity changes (distance and screen-edge fade).
/// - The scene is turned into drawing data once per scene change (in `init`), not per frame. Per frame the
///   only work is projecting points, laying out labels and stroking a handful of paths.
/// - Hysteresis keeps a label that the declutter just dropped on screen for a few frames so it does not
///   flicker.
///
/// Draw this only when it is honest to: see `ARStatusSummary.overlayAllowed`. This view does not check
/// whether the scene lines up with the room.
struct AROverlayCanvas: View {
    let session: ARSession
    let style: OverlayStyle
    /// Called when a label is tapped. When nil the canvas ignores touches so they reach the views below.
    var onSelectLabel: ((OverlayLabel) -> Void)?
    /// What VoiceOver calls this layer, for screens that stack more than one canvas.
    var accessibilityName: String

    private let prepared: ARPreparedOverlay

    @State private var model = ARCanvasModel()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(session: ARSession, scene: OverlayScene, style: OverlayStyle = .standard,
         onSelectLabel: ((OverlayLabel) -> Void)? = nil, accessibilityName: String = "Measurement overlay") {
        self.session = session
        self.style = style
        self.onSelectLabel = onSelectLabel
        self.accessibilityName = accessibilityName
        self.prepared = ARPreparedOverlay(scene: scene, style: style)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: false)) { _ in
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
                render(&context, size)
            } symbols: {
                ForEach(prepared.labels) { item in
                    AROverlayLabelChip(item: item, style: style, reduceTransparency: reduceTransparency,
                                     increasedContrast: contrast == .increased)
                        .tag(item.id)
                }
            }
        }
        .allowsHitTesting(onSelectLabel != nil)
        .gesture(tap)
        .accessibilityLabel(accessibilityName)
        .accessibilityChildren {
            VStack {
                ForEach(prepared.accessibleLabels) { item in
                    if onSelectLabel != nil {
                        Text(verbatim: item.label.title)
                            .accessibilityLabel(item.spoken)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { onSelectLabel?(item.label) }
                    } else {
                        Text(verbatim: item.label.title)
                            .accessibilityLabel(item.spoken)
                    }
                }
            }
        }
    }

    private var tap: some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let id = model.labelID(at: value.location),
                  let item = prepared.labels.first(where: { $0.id == id }) else { return }
            onSelectLabel?(item.label)
        }
    }

    // MARK: Rendering

    private func render(_ context: inout GraphicsContext, _ size: CGSize) {
        guard size.width > 0, size.height > 0, let frame = session.currentFrame else { return }
        // Read every frame: a rotation changes how the camera image maps to the screen at once.
        let projector = ARProjector(camera: frame.camera, orientation: ARProjection.currentInterfaceOrientation(),
                                    viewport: size)
        let boost: CGFloat = contrast == .increased ? 0.5 : 0
        let outline = contrast == .increased ? Color.black.opacity(0.6) : style.outlineColor

        drawLines(&context, projector, outline: outline, boost: boost)
        drawLabels(&context, projector, size: size)
    }

    private func drawLines(_ context: inout GraphicsContext, _ projector: ARProjector, outline: Color, boost: CGFloat) {
        model.strokes.removeAll(keepingCapacity: true)

        for bucket in prepared.buckets {
            var path = Path()
            for (a, b) in bucket.segments {
                if let (p, q) = projector.project(from: a, to: b) {
                    path.move(to: p)
                    path.addLine(to: q)
                }
            }
            if !path.isEmpty { model.strokes.append(ARCanvasStroke(path: path, color: bucket.color, width: bucket.width + boost)) }
        }
        for arc in prepared.arcs {
            var path = Path()
            var started = false
            var complete = true
            for point in arc.points {
                guard let p = projector.project(point) else { complete = false; break }
                if started { path.addLine(to: p) } else { path.move(to: p); started = true }
            }
            // An arc that runs behind the camera is skipped rather than drawn half-way.
            if complete, started { model.strokes.append(ARCanvasStroke(path: path, color: arc.color, width: style.arcLineWidth + boost)) }
        }

        // Outlines first, so a neighbouring line's outline never covers another line's colour.
        for stroke in model.strokes {
            context.stroke(stroke.path, with: .color(outline),
                           style: SwiftUI.StrokeStyle(lineWidth: stroke.width + style.outlineExtraWidth,
                                                      lineCap: .round, lineJoin: .round))
        }
        for stroke in model.strokes {
            context.stroke(stroke.path, with: .color(stroke.color),
                           style: SwiftUI.StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
        }

        // Dots at the ends of a measurement.
        let r = style.endpointRadius
        for end in prepared.endpoints {
            guard let p = projector.project(end) else { continue }
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            context.stroke(dot, with: .color(outline), lineWidth: 2 + style.outlineExtraWidth)
            context.fill(dot, with: .color(.white))
            context.stroke(dot, with: .color(style.measurementColor), lineWidth: 1.5)
        }
    }

    private func drawLabels(_ context: inout GraphicsContext, _ projector: ARProjector, size: CGSize) {
        model.candidates.removeAll(keepingCapacity: true)
        for item in prepared.labels {
            let anchor = item.label.position
            guard let screen = projector.project(anchor),
                  screen.x > -200, screen.x < size.width + 200, screen.y > -120, screen.y < size.height + 120,
                  let symbol = context.resolveSymbol(id: item.id) else { continue }
            model.candidates.append(LabelCandidate(
                id: item.id, x: Double(screen.x), y: Double(screen.y),
                width: Double(symbol.size.width), height: Double(symbol.size.height),
                priority: item.label.priority, distance: projector.distance(to: anchor)))
        }

        let placed = LabelLayout.place(model.candidates, viewport: LabelViewport(width: Double(size.width), height: Double(size.height)))
        let stable = model.hysteresis.stabilise(placed, candidates: model.candidates)

        model.hitRects.removeAll(keepingCapacity: true)
        // Best label last, so it is drawn on top.
        for p in stable.reversed() {
            guard let symbol = context.resolveSymbol(id: p.id) else { continue }
            let s = symbol.size
            let rect = CGRect(x: CGFloat(p.x) - s.width / 2, y: CGFloat(p.y) - s.height / 2, width: s.width, height: s.height)
            context.opacity = p.opacity
            context.draw(symbol, in: rect)
            model.hitRects.append(ARCanvasHitRect(id: p.id, rect: rect))
        }
        context.opacity = 1
    }
}

// MARK: - Per-frame scratch state

private struct ARCanvasStroke {
    let path: Path
    let color: Color
    let width: CGFloat
}

private struct ARCanvasHitRect {
    let id: String
    let rect: CGRect
}

/// Reference-typed scratch space for the canvas: reused arrays (so a frame allocates little), the
/// hysteresis state and the label rectangles for hit testing. Not observable on purpose: changing it must
/// never trigger a SwiftUI update.
private final class ARCanvasModel {
    var hysteresis = LabelHysteresis(requiredFrames: 3)
    var candidates: [LabelCandidate] = []
    var strokes: [ARCanvasStroke] = []
    var hitRects: [ARCanvasHitRect] = []

    /// The top-most label under `point`, with at least a 44 pt touch target.
    func labelID(at point: CGPoint) -> String? {
        for hit in hitRects.reversed() {
            var r = hit.rect
            if r.width < 44 { r = r.insetBy(dx: (r.width - 44) / 2, dy: 0) }
            if r.height < 44 { r = r.insetBy(dx: 0, dy: (r.height - 44) / 2) }
            if r.contains(point) { return hit.id }
        }
        return nil
    }
}

// MARK: - Scene prepared once

/// An `OverlayScene` turned into what drawing needs: segments grouped by colour and width, arcs sampled to
/// world-space polylines, and label presentation. Built once per scene change.
struct ARPreparedOverlay {
    struct Bucket {
        let color: Color
        let width: CGFloat
        var segments: [(Point3, Point3)]
    }

    struct ArcLine {
        let points: [Point3]
        let color: Color
    }

    struct LabelItem: Identifiable {
        let id: String
        let label: OverlayLabel
        let spoken: String
        let titleColor: Color
        let glyph: String?
        let glyphColor: Color
    }

    var buckets: [Bucket] = []
    var arcs: [ArcLine] = []
    var endpoints: [Point3] = []
    var labels: [LabelItem] = []
    /// Labels most important first, for VoiceOver.
    var accessibleLabels: [LabelItem] = []

    init(scene: OverlayScene, style: OverlayStyle) {
        for segment in scene.segments {
            let color = style.color(for: segment.kind, state: segment.state)
            let width = style.width(for: segment.kind)
            if let i = buckets.firstIndex(where: { $0.color == color && $0.width == width }) {
                buckets[i].segments.append((segment.a, segment.b))
            } else {
                buckets.append(Bucket(color: color, width: width, segments: [(segment.a, segment.b)]))
            }
            if segment.kind == .measurement {
                endpoints.append(segment.a)
                if segment.a != segment.b { endpoints.append(segment.b) }
            }
        }

        for arc in scene.arcs {
            guard arc.radius.isFinite, arc.radius > 0, arc.sweep.isFinite, arc.startAngle.isFinite else { continue }
            let steps = max(6, Int((abs(arc.sweep) / 90 * Double(style.arcSamplesPerQuarter)).rounded(.up)))
            var points: [Point3] = []
            points.reserveCapacity(steps + 1)
            let centre = arc.center.plan
            for k in 0...steps {
                let degrees = arc.startAngle + arc.sweep * Double(k) / Double(steps)
                let radians = degrees * Double.pi / 180
                let p = centre + Point2(cos(radians), sin(radians)) * arc.radius
                points.append(p.world(elevation: arc.center.y))
            }
            arcs.append(ArcLine(points: points, color: style.tint(for: arc.state)))
        }

        labels = scene.labels.map { label in
            LabelItem(id: label.id, label: label, spoken: label.spokenDescription,
                      titleColor: style.titleColor(for: label.state),
                      glyph: style.glyph(for: label.state), glyphColor: style.tint(for: label.state))
        }
        accessibleLabels = labels.sorted {
            if $0.label.priority != $1.label.priority { return $0.label.priority > $1.label.priority }
            return $0.id < $1.id
        }
    }
}

// MARK: - Label chip

/// One label: a dark chip with the number in monospaced digits, an optional line of small print and a
/// glyph for verified / caution / critical. Resolved once into a Canvas symbol and drawn many times.
///
/// A Canvas symbol is rasterised, so a Material cannot blur the camera behind it. The chip is the `background`
/// token at about 74 % with the 0.5 pt top-edge highlight DESIGN.md uses for glass; Reduce Transparency makes
/// it opaque `surface`, Increased Contrast adds a `line` border.
private struct AROverlayLabelChip: View {
    let item: ARPreparedOverlay.LabelItem
    let style: OverlayStyle
    let reduceTransparency: Bool
    let increasedContrast: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.labelCornerRadius, style: .continuous)
        HStack(spacing: Spacing.xs) {
            if let glyph = item.glyph {
                Image(systemName: glyph)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(item.glyphColor)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.label.title)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(item.titleColor)
                    .lineLimit(1)
                if let subtitle = item.label.subtitle {
                    // The line that tells scanned from verified ("±93 mm", "Laser"): ink at full strength and
                    // semibold, because grey on a chip over a bright wall is unreadable.
                    Text(verbatim: subtitle)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, style.labelHorizontalPadding)
        .padding(.vertical, style.labelVerticalPadding)
        .background {
            shape.fill(reduceTransparency ? Palette.surface : Palette.background.opacity(style.labelFillOpacity))
        }
        .overlay {
            if reduceTransparency || increasedContrast {
                shape.strokeBorder(Palette.line, lineWidth: increasedContrast ? Hairline.emphasized : Hairline.width)
            } else {
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: Hairline.width)
            }
        }
        .dynamicTypeSize(...style.labelMaxTypeSize)
    }
}
