import SwiftUI
import UIKit
import RoomPlan

/// Puts the controller's `RoomCaptureView` on screen. The view belongs to the controller, which keeps it
/// (and the AR session behind it) alive across every room, so this wrapper never builds a new one: it hands
/// the same instance to a host view and `updateUIView` does nothing.
///
/// The scan starts only once the capture view is in a window. SwiftUI's `onAppear` can run before that, and
/// Apple's samples start the session from `viewDidAppear`, when the view is on screen. The host view reports
/// that moment from `didMoveToWindow`.
struct RoomCaptureViewContainer: UIViewRepresentable {
    let controller: ScanSessionController

    func makeUIView(context: Context) -> CaptureHostView {
        let controller = self.controller
        let host = CaptureHostView()
        host.backgroundColor = .black
        guard let view = controller.captureView else { return host }
        host.embed(view)
        host.onAttach = { [weak controller] in
            // `didMoveToWindow` runs on the main thread.
            MainActor.assumeIsolated {
                if let controller { controller.start() }
            }
        }
        return host
    }

    func updateUIView(_ uiView: CaptureHostView, context: Context) {}
}

/// Holds the capture view full-bleed and says when it has a window.
final class CaptureHostView: UIView {
    /// Called every time the host gains a window. The controller ignores all but the first.
    var onAttach: (() -> Void)?

    /// Fills the host with `view` and keeps it filling as the host changes size.
    func embed(_ view: UIView) {
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onAttach?() }
    }
}
