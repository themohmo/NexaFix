import Foundation
import NexaFixCore
#if canImport(ARKit)
import ARKit
import UIKit
import simd
#endif

// Putting world points on the screen. The ARKit call is `ARCamera.projectPoint`; around it sits plain
// maths (in front of the camera? how far? clip a line at the near plane) so a segment that runs behind
// the camera is cut instead of flipping across the screen.

/// Where the camera is and which way it looks, in world space (metres). Plain values, no ARKit.
struct ARCameraRay: Equatable, Sendable {
    /// Points closer than this in front of the camera are treated as behind it, metres.
    static let nearDistance = 0.05

    var position: Point3
    /// Unit vector the camera looks along.
    var forward: Point3

    /// Distance of `p` in front of the camera plane; negative behind it.
    func depth(of p: Point3) -> Double {
        (p - position).dot(forward)
    }

    func isInFront(_ p: Point3, near: Double = ARCameraRay.nearDistance) -> Bool {
        depth(of: p) > near
    }

    /// Straight-line distance from the camera to `p`, metres.
    func distance(to p: Point3) -> Double {
        (p - position).length
    }

    /// Cuts the segment `a`-`b` at the near plane. Returns nil when the whole segment is behind it.
    func clip(_ a: Point3, _ b: Point3, near: Double = ARCameraRay.nearDistance) -> (Point3, Point3)? {
        let da = depth(of: a) - near
        let db = depth(of: b) - near
        if da >= 0 && db >= 0 { return (a, b) }
        if da < 0 && db < 0 { return nil }
        let t = da / (da - db)
        let cut = a + (b - a) * t
        return da < 0 ? (cut, b) : (a, cut)
    }
}

#if canImport(ARKit)

/// Projects world points for one frame. Make one per frame (it is cheap), then call `project` many times.
struct ARProjector {
    let camera: ARCamera
    let orientation: UIInterfaceOrientation
    let viewport: CGSize
    let ray: ARCameraRay

    init(camera: ARCamera, orientation: UIInterfaceOrientation, viewport: CGSize) {
        self.camera = camera
        self.orientation = orientation
        self.viewport = viewport
        let t = camera.transform
        let position = Point3(Double(t.columns.3.x), Double(t.columns.3.y), Double(t.columns.3.z))
        // ARKit's camera looks down its own -Z axis.
        let back = Point3(Double(t.columns.2.x), Double(t.columns.2.y), Double(t.columns.2.z))
        let length = back.length
        let forward = length > 1e-9 ? back * (-1 / length) : Point3(0, 0, -1)
        self.ray = ARCameraRay(position: position, forward: forward)
    }

    /// The screen point for a world point, or nil if it is behind (or right at) the camera.
    func project(_ p: Point3) -> CGPoint? {
        guard ray.isInFront(p) else { return nil }
        return unchecked(p)
    }

    /// The screen end points of a world segment after cutting it at the near plane, or nil if it is
    /// entirely behind the camera.
    func project(from a: Point3, to b: Point3) -> (CGPoint, CGPoint)? {
        guard let (ca, cb) = ray.clip(a, b) else { return nil }
        return (unchecked(ca), unchecked(cb))
    }

    func distance(to p: Point3) -> Double { ray.distance(to: p) }

    private func unchecked(_ p: Point3) -> CGPoint {
        camera.projectPoint(simd_float3(Float(p.x), Float(p.y), Float(p.z)),
                            orientation: orientation, viewportSize: viewport)
    }
}

enum ARProjection {
    /// The orientation of the foreground window scene. ARKit needs it to map the camera image to the screen.
    /// Falls back to portrait when no scene is active (previews, tests).
    ///
    /// Cheap enough to call every frame, which is how the overlay uses it: a rotation (even a landscape-left
    /// to landscape-right flip, where the canvas size does not change) is picked up on the next frame.
    ///
    /// Both this property and `ARCamera.projectPoint(_:orientation:viewportSize:)` are marked deprecated in
    /// the newest SDKs (`UIWindowScene.effectiveGeometry.interfaceOrientation` from iOS 26 and
    /// `projectPoint(_:viewRotationAngle:viewportSize:)` from iOS 27). The replacements do not exist in the
    /// older SDKs this project also builds with (Xcode 15 to 26), so the long-standing forms stay; at worst
    /// they give a deprecation warning on the newest SDK.
    static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        var fallback: UIInterfaceOrientation?
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if windowScene.activationState == .foregroundActive { return windowScene.interfaceOrientation }
            if fallback == nil { fallback = windowScene.interfaceOrientation }
        }
        return fallback ?? .portrait
    }

    /// Converts a world transform's translation to a Core point.
    static func position(of transform: simd_float4x4) -> Point3 {
        Point3(Double(transform.columns.3.x), Double(transform.columns.3.y), Double(transform.columns.3.z))
    }
}

#endif
