import SwiftUI
import ARKit
import RealityKit
import UIKit

/// Hosts the RealityKit `ARView` that shows the camera image and owns the `ARSession`.
///
/// The view is created with `automaticallyConfigureSession: false`: `ARReviewController` runs the session
/// itself, because it has to start from the room's saved world map and watch relocalisation. Nothing is
/// added to the RealityKit scene; the numbers are drawn by `AROverlayCanvas` on top.
struct ARViewContainer: UIViewRepresentable {
    let controller: ARReviewController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.backgroundColor = .black
        // The camera image carries no information VoiceOver can read; the overlay and controls do.
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.session.pause()
        uiView.session.delegate = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
