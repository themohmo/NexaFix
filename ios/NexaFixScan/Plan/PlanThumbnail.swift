import SwiftUI
import NexaFixCore

/// A small, still picture of a floor plan for the property cards: the walls, doors and windows of the same
/// `PlanDrawing` the full plan uses, fitted to whatever size the card gives it.
///
/// Not interactive and not read by VoiceOver (the card around it has its own label). Furniture, dimensions and
/// text are left out: at this size they would be smudges, and text smaller than 7 points is never drawn.
struct PlanThumbnail: View {
    private let drawing: PlanDrawing

    @Environment(\.colorSchemeContrast) private var contrast

    init(drawing: PlanDrawing) {
        self.drawing = drawing
    }

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            // Built here, not in `init`: a list creates thumbnails far more often than it draws them.
            let renderer = PlanRenderer(drawing: drawing, options: .thumbnail)
            let viewport = PlanViewport.fit(bounds: drawing.bounds,
                                            in: ScreenSize(width: Double(size.width), height: Double(size.height)),
                                            padding: Double(Spacing.s))
            renderer.draw(&context, size: size, viewport: viewport, highlight: nil,
                          increasedContrast: contrast == .increased)
        }
        .accessibilityHidden(true)
    }
}
