#if DEBUG
import SwiftUI
import NexaFixCore

// Canvas previews for every design-system component, each in light, dark and accessibility-5 text.
// Reduce Transparency and Increased Contrast cannot be forced from code: switch them on in the preview's
// Environment Overrides (the slider icon at the bottom of the canvas) and the glass should turn opaque
// and gain a border.

// MARK: - Variants

private extension View {
    func lightVariant() -> some View {
        preferredColorScheme(.light)
    }

    func darkVariant() -> some View {
        preferredColorScheme(.dark)
    }

    func accessibilityVariant() -> some View {
        preferredColorScheme(.light)
            .environment(\.dynamicTypeSize, .accessibility5)
    }
}

private enum Sample {
    static let units = DisplayUnits.default
    static let feet = DisplayUnits(length: .feetAndInches, area: .squareFeet)
    static let scanned = Measured(scanned: 3.245)
    static let laser = Measured(scanned: 3.233, verification: Verification(value: 3.245, source: .laser))
    static let tape = Measured(scanned: 2.40, verification: Verification(value: 2.412, source: .tape))
}

/// A stand-in for the camera feed: a dark half and a bright half, so glass is judged on both.
private struct FakeCameraFeed: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Color(white: 0.06), location: 0),
            .init(color: Color(white: 0.30), location: 0.45),
            .init(color: Color(white: 0.92), location: 0.55),
            .init(color: Color(white: 0.78), location: 1)
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
    }
}

// MARK: - Galleries

private struct PaletteGallery: View {
    private let swatches: [(String, Color)] = [
        ("background", Palette.background), ("surface", Palette.surface), ("ink", Palette.ink),
        ("muted", Palette.muted), ("line", Palette.line), ("accent", Palette.accent),
        ("verified", Palette.verified), ("caution", Palette.caution), ("critical", Palette.critical)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.s) {
                ForEach(swatches, id: \.0) { name, color in
                    HStack(spacing: Spacing.m) {
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .fill(color)
                            .frame(width: 56, height: 40)
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                    .strokeBorder(Palette.line, lineWidth: Hairline.width)
                            }
                        Text(verbatim: name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                    }
                }
                HStack(spacing: Spacing.m) {
                    Text(verbatim: "Primary text")
                        .font(.headline)
                        .foregroundStyle(Palette.accentContrast)
                        .padding(Spacing.m)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    Text(verbatim: "accentContrast on accent")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                }
            }
            .padding(Spacing.l)
        }
        .screenBackground()
    }
}

private struct ButtonsGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Button("Scan a property") {}
                    .buttonStyle(.primaryFullWidth)
                HStack(spacing: Spacing.m) {
                    Button("Scan room") {}
                        .buttonStyle(.primary)
                    Button("Export") {}
                        .buttonStyle(.secondary)
                }
                Button("Disabled primary") {}
                    .buttonStyle(.primary)
                    .disabled(true)
                Button("Disabled secondary") {}
                    .buttonStyle(.secondary)
                    .disabled(true)
                Button("Try the demo apartment") {}
                    .buttonStyle(.secondaryFullWidth)
                Button {
                } label: {
                    Label("Pressable row", systemImage: "chevron.right")
                        .foregroundStyle(Palette.ink)
                        .padding(Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                }
                .buttonStyle(.pressable)

                HStack(spacing: Spacing.m) {
                    GlassIconButton(systemImage: "xmark", label: "Close") {}
                    GlassIconButton(systemImage: "square.and.arrow.up", label: "Share") {}
                    GlassIconButton(systemImage: "plus", label: "Add") {}
                }
            }
            .padding(Spacing.l)
        }
        .screenBackground()
    }
}

private struct GlassGallery: View {
    var body: some View {
        ZStack {
            FakeCameraFeed()
            VStack(spacing: Spacing.l) {
                Pill("Move slowly along the wall", systemImage: "camera.viewfinder")
                Pill("Tracking limited", systemImage: "exclamationmark.triangle.fill", tint: Palette.caution)
                Pill("Laser verified", systemImage: "checkmark.circle.fill", tint: Palette.verified)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(verbatim: "Regular glass")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    MeasurementText(length: 3.245, units: Sample.units, style: .title)
                    // Glass inside glass draws a flat tint instead of a second blur.
                    Text(verbatim: "Nested")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(Spacing.s)
                        .glass(cornerRadius: Radius.chip, prominence: .thin)
                }
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(cornerRadius: Radius.card, prominence: .regular)

                HStack(spacing: Spacing.m) {
                    Text(verbatim: "Thin")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(Spacing.m)
                        .glass(cornerRadius: Radius.row, prominence: .thin)
                    Text(verbatim: "Thick")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(Spacing.m)
                        .glass(cornerRadius: Radius.row, prominence: .thick)
                    Spacer(minLength: 0)
                    GlassIconButton(systemImage: "xmark", label: "Close") {}
                }
            }
            .padding(Spacing.l)
        }
    }
}

private struct GlassOnPaperGallery: View {
    var body: some View {
        VStack(spacing: Spacing.l) {
            Pill("Relocalising: look at the room you scanned", systemImage: "camera.viewfinder")
            HStack(spacing: Spacing.m) {
                ForEach([GlassProminence.thin, .regular, .thick], id: \.self) { prominence in
                    Text(verbatim: "\(String(describing: prominence))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(Spacing.l)
                        .glass(cornerRadius: Radius.row, prominence: prominence)
                }
            }
            Button("Secondary on glass") {}
                .buttonStyle(.secondaryOnGlass)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

/// A dimension row the way the Room screen builds it: one VoiceOver sentence per row.
private struct SampleDimensionRow: View {
    let name: String
    let measured: Measured
    let units: DisplayUnits

    var body: some View {
        let value = MeasurementParts.length(measured.value, units: units).spoken
        let provenance = ProvenanceDescription(measured, units: units, compact: false).spoken
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                label
                Spacer(minLength: Spacing.m)
                MeasurementText(length: measured.value, units: units, style: .body)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                label
                MeasurementText(length: measured.value, units: units, style: .body)
            }
        }
        .padding(.vertical, Spacing.m)
        .frame(minHeight: 44)
        .accessibilityMeasurement(name, value: value, provenance: provenance)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: name)
                .font(.body)
                .foregroundStyle(Palette.ink)
            ProvenanceBadge(measured, units: units)
        }
    }
}

private struct MeasurementsGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    MeasurementText(area: 18.42, units: Sample.units, style: .hero)
                    Text(verbatim: "Living room")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                    MeasurementText(length: 3.245, units: Sample.units, style: .title)
                    MeasurementText(length: 5.678, units: DisplayUnits(length: .metres), style: .title)
                    MeasurementText(angle: 89.6, style: .title)
                }
                MeasurementText(length: 3.245, units: Sample.feet, style: .title)
                MeasurementText(area: 18.42, units: Sample.feet, style: .body)
                MeasurementText(length: 2.1, units: Sample.units, style: .caption)
                MeasurementText(length: 2.1, units: Sample.units, style: .body)
                    .numberColor(Palette.verified)

                HStack(spacing: Spacing.l) {
                    ProvenanceBadge(Sample.laser, units: Sample.units)
                    ProvenanceBadge(Sample.scanned, units: Sample.units)
                }
                HStack(spacing: Spacing.l) {
                    ProvenanceBadge(Sample.tape, units: Sample.units, compact: true)
                    ProvenanceBadge(Sample.scanned, units: Sample.units, compact: true)
                }
                VerificationProgress(verified: 9, total: 21)
                VerificationProgress(verified: 0, total: 0)
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground()
    }
}

private struct ComponentsGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Wordmark()
                    .frame(maxWidth: .infinity)

                SectionCard("Dimensions") {
                    SampleDimensionRow(name: "Wall A", measured: Sample.laser, units: Sample.units)
                    RowDivider()
                    SampleDimensionRow(name: "Wall B", measured: Sample.scanned, units: Sample.units)
                    RowDivider()
                    SampleDimensionRow(name: "Door 1 width", measured: Sample.tape, units: Sample.units)
                }

                SectionCard {
                    HStack(spacing: Spacing.l) {
                        ProgressRing(fraction: 0)
                            .frame(width: 32, height: 32)
                        ProgressRing(fraction: 0.43)
                            .frame(width: 32, height: 32)
                        ProgressRing(fraction: 1, lineWidth: 6)
                            .frame(width: 48, height: 48)
                        ProgressRing(fraction: 0.6, tint: Palette.accent)
                            .frame(width: 32, height: 32)
                    }
                    .padding(.vertical, Spacing.m)
                }

                HStack(spacing: Spacing.xl) {
                    AppMark(size: 32)
                    AppMark(size: 64)
                    AppMark(size: 128)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(Spacing.l)
        }
        .screenBackground()
    }
}

private struct EmptyStateGallery: View {
    var body: some View {
        EmptyStateView(
            title: "No properties yet",
            message: "Scan a room and its measurements show up here, ready to check and send.",
            primaryTitle: "Scan a property",
            primaryAction: {},
            secondaryTitle: "Try the demo apartment",
            secondaryAction: {})
            .screenBackground()
    }
}

// MARK: - Previews

#Preview("Palette · Light") { PaletteGallery().lightVariant() }
#Preview("Palette · Dark") { PaletteGallery().darkVariant() }
#Preview("Palette · AX5") { PaletteGallery().accessibilityVariant() }

#Preview("Buttons · Light") { ButtonsGallery().lightVariant() }
#Preview("Buttons · Dark") { ButtonsGallery().darkVariant() }
#Preview("Buttons · AX5") { ButtonsGallery().accessibilityVariant() }

#Preview("Glass over camera · Light") { GlassGallery().lightVariant() }
#Preview("Glass over camera · Dark") { GlassGallery().darkVariant() }
#Preview("Glass over camera · AX5") { GlassGallery().accessibilityVariant() }

#Preview("Glass on paper · Light") { GlassOnPaperGallery().lightVariant() }
#Preview("Glass on paper · Dark") { GlassOnPaperGallery().darkVariant() }
#Preview("Glass on paper · AX5") { GlassOnPaperGallery().accessibilityVariant() }

#Preview("Measurements · Light") { MeasurementsGallery().lightVariant() }
#Preview("Measurements · Dark") { MeasurementsGallery().darkVariant() }
#Preview("Measurements · AX5") { MeasurementsGallery().accessibilityVariant() }

#Preview("Components · Light") { ComponentsGallery().lightVariant() }
#Preview("Components · Dark") { ComponentsGallery().darkVariant() }
#Preview("Components · AX5") { ComponentsGallery().accessibilityVariant() }

#Preview("Empty state · Light") { EmptyStateGallery().lightVariant() }
#Preview("Empty state · Dark") { EmptyStateGallery().darkVariant() }
#Preview("Empty state · AX5") { EmptyStateGallery().accessibilityVariant() }
#endif
