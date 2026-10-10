import SwiftUI
import UIKit

/// The system share sheet for a set of files (Files, AirDrop, Mail, Messages).
///
/// Attach it as the background of the button that starts the share, and set `items` to the file URLs when
/// they are ready:
///
///     Button("Share") { items = urls }
///         .background { ShareSheet(items: $items).allowsHitTesting(false) }
///
/// It presents a `UIActivityViewController` from a view that fills the button. On iPhone the sheet rises
/// from the bottom; on iPad Apple requires a popover, and the popover points at that same view. `items`
/// goes back to nil when the sheet closes, whether or not anything was sent.
struct ShareSheet: UIViewControllerRepresentable {
    /// The files to share. Nil keeps the sheet closed; setting it opens the sheet.
    @Binding var items: [URL]?
    /// Called when the sheet closes, with whether the person finished an activity (sent, saved, copied).
    var onFinish: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> ShareAnchorViewController {
        ShareAnchorViewController()
    }

    func updateUIViewController(_ anchor: ShareAnchorViewController, context: Context) {
        context.coordinator.parent = self
        guard let urls = items, !urls.isEmpty, !context.coordinator.isPresenting else { return }
        context.coordinator.isPresenting = true
        // After this update, never during it: presenting changes UIKit state SwiftUI is in the middle of reading.
        Task { @MainActor [weak anchor, coordinator = context.coordinator] in
            guard let anchor else {
                coordinator.finish(completed: false)
                return
            }
            coordinator.present(urls, from: anchor)
        }
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator {
        var parent: ShareSheet?
        var isPresenting = false

        func present(_ urls: [URL], from anchor: ShareAnchorViewController) {
            // The button has to be on screen to point at; if it is not, there is nothing to present from.
            guard anchor.viewIfLoaded?.window != nil else {
                finish(completed: false)
                return
            }
            let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = anchor.view
                popover.sourceRect = anchor.view.bounds
                popover.permittedArrowDirections = [.up, .down]
            }
            activity.completionWithItemsHandler = { [weak self] _, completed, _, _ in
                Task { @MainActor in self?.finish(completed: completed) }
            }
            anchor.present(activity, animated: true)
        }

        func finish(completed: Bool) {
            isPresenting = false
            let owner = parent
            owner?.items = nil
            owner?.onFinish(completed)
        }
    }
}

/// An empty view controller that takes the place of the button the share sheet points at.
final class ShareAnchorViewController: UIViewController {
    override func loadView() {
        let anchor = UIView()
        anchor.backgroundColor = .clear
        anchor.isUserInteractionEnabled = false
        view = anchor
    }
}
