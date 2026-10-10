import SwiftUI
import NexaFixCore

/// The wordmark, the version, what the numbers mean, and where the data lives. Pushed from Settings.
@MainActor
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.m) {
                    AppMark(size: 72)
                    Wordmark()
                    Text(verbatim: AboutView.versionText)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.l)
                .accessibilityElement(children: .combine)

                SectionCard("Joinery and LiDAR") {
                    Text(verbatim: ScanAccuracy.joineryDisclaimer)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.m)
                }

                SectionCard("Your data") {
                    Text(verbatim: "All data stays on this device unless you export it.")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.m)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Version 1.0.0 (1)", read from the app's Info.plist.
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        return SettingsChoices.versionText(short: info?["CFBundleShortVersionString"] as? String,
                                           build: info?["CFBundleVersion"] as? String)
    }
}

#if DEBUG
#Preview("About") {
    NavigationStack { AboutView() }
}
#endif
