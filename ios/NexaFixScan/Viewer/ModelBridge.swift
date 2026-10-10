import SwiftUI
import RealityKit
import UIKit
import NexaFixCore

// The 3D viewer's renderer.
//
// It uses RealityKit, not SceneKit: every SceneKit type (SCNView, SCNGeometry, SCNScene ...) is deprecated as of
// iOS 26 ("SceneKit is deprecated, use RealityKit"), and RealityKit's `ARView` has a camera mode that needs no AR
// session and works from iOS 13, so the non-deprecated API is available on the deployment target. The viewer
// uses `ARView` in `.nonAR` mode with `MeshDescriptor` / `MeshResource` geometry, `UnlitMaterial` colours and a
// `PerspectiveCamera`.
//
// Lighting is baked into the colours (`RoomScene.shadedBatches()` in NexaFixCore): faces are grouped by
// material and shade, and each group is drawn with one unlit material whose colour is the material's colour
// times the shade. There are no lights to configure. What the renderer would otherwise do to those colours is
// switched off, so the 24 shades of a wall stay the 24 shades that were baked: the view's post effects
// (`ARView.renderOptions`) and, from iOS 18, the material's tone mapping (`applyPostProcessToneMap`).

// MARK: - Palette for the model

/// The colours of the model, built from the app's palette tokens. The model is always drawn in the light
/// palette, whatever the appearance of the interface: a wall is warm paper white in dark mode too, and only the
/// background around it follows the appearance.
private enum ModelPalette {
    private static let light = UITraitCollection(userInterfaceStyle: .light)

    private static func token(_ color: Color) -> UIColor { UIColor(color).resolvedColor(with: light) }

    static func color(for kind: SceneMaterialKind) -> UIColor {
        let paper = token(Palette.background)
        let surface = token(Palette.surface)
        let line = token(Palette.line)
        let accent = token(Palette.accent)
        let muted = token(Palette.muted)
        switch kind {
        case .wall: return paper
        case .wallReveal: return paper.mixed(with: line, 0.55)
        case .floor: return line.mixed(with: accent, 0.22)
        case .ceiling: return surface.mixed(with: paper, 0.5)
        case .doorFrame: return accent
        case .windowGlass: return UIColor.systemBlue.resolvedColor(with: light).mixed(with: surface, 0.35)
        case .object: return muted.mixed(with: paper, 0.55)
        case .measureLine: return accent
        }
    }

    /// How see-through a kind is: 1 is solid.
    static func opacity(for kind: SceneMaterialKind, seeThroughWalls: Bool) -> Float {
        switch kind {
        case .windowGlass: return 0.30
        case .wall, .wallReveal: return seeThroughWalls ? 0.22 : 1
        default: return 1
        }
    }

    /// The page behind the model.
    static func background(dark: Bool) -> UIColor {
        UIColor(Palette.background).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
    }
}

private extension UIColor {
    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// `self` blended towards `other` by `t` (0 is all `self`).
    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        let a = rgb, b = other.rgb
        return UIColor(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t, alpha: 1)
    }

    /// Each channel times `k`, held to 0...1.
    func scaled(by k: CGFloat) -> UIColor {
        let c = rgb
        return UIColor(red: min(c.r * k, 1), green: min(c.g * k, 1), blue: min(c.b * k, 1), alpha: 1)
    }
}

// MARK: - Renderer

/// Owns the RealityKit scene of the viewer: the model's entities, the camera and the view's background.
@MainActor
final class ModelRenderer {
    private struct Piece {
        let entity: ModelEntity
        let kind: SceneMaterialKind
        let brightness: Double
    }

    let view: ARView
    private let anchor = AnchorEntity(world: .zero)
    private let cameraEntity = PerspectiveCamera()
    private var pieces: [Piece] = []
    private var seeThroughWalls = false
    private var showsCeiling = false

    init(view: ARView) {
        self.view = view
        cameraEntity.camera = PerspectiveCameraComponent(near: 0.05, far: 2000,
                                                         fieldOfViewInDegrees: Float(SceneCamera.fieldOfViewDegrees))
        if #available(iOS 18.0, *) {
            // Make the vertical field of view explicit: framing and the pan speed assume it.
            cameraEntity.camera.fieldOfViewOrientation = .vertical
        }
        anchor.addChild(cameraEntity)
        view.scene.addAnchor(anchor)
    }

    /// Whether the renderer applies the field of view vertically for certain (iOS 18 and later).
    static var fieldOfViewIsVertical: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    // MARK: Model

    /// What building the model gave: how many pieces there were to draw and how many could not be built.
    struct BuildReport: Equatable {
        var batches = 0
        var failed = 0
    }

    /// Replaces the model. Faces are drawn in one entity per material and shade. A piece that cannot be built is
    /// counted in the report, which the caller shows to the person; it is never dropped silently.
    @discardableResult
    func rebuild(scene: RoomScene) -> BuildReport {
        for piece in pieces { piece.entity.removeFromParent() }
        pieces = []
        var report = BuildReport()
        for batch in scene.shadedBatches() {
            report.batches += 1
            guard let mesh = ModelRenderer.mesh(from: batch.buffer) else {
                report.failed += 1
                continue
            }
            let entity = ModelEntity(mesh: mesh,
                                     materials: [material(for: batch.material, brightness: batch.brightness)])
            entity.name = "model.\(batch.material.rawValue).\(batch.level)"
            entity.isEnabled = isVisible(batch.material)
            anchor.addChild(entity)
            pieces.append(Piece(entity: entity, kind: batch.material, brightness: batch.brightness))
        }
        // Far enough to see the whole model whatever its size.
        let far = Float(max(200, scene.diagonal * 20))
        cameraEntity.camera.far = far
        return report
    }

    /// The RealityKit mesh for one batch, or nil when the buffer is unusable or RealityKit refuses it.
    private static func mesh(from buffer: SceneMeshBuffer) -> MeshResource? {
        let count = buffer.vertexCount
        guard count > 0, buffer.normals.count == buffer.positions.count else { return nil }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(count)
        normals.reserveCapacity(count)
        for i in 0..<count {
            positions.append(SIMD3<Float>(buffer.positions[3 * i], buffer.positions[3 * i + 1], buffer.positions[3 * i + 2]))
            normals.append(SIMD3<Float>(buffer.normals[3 * i], buffer.normals[3 * i + 1], buffer.normals[3 * i + 2]))
        }
        var descriptor = MeshDescriptor(name: "batch")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(buffer.indices)
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            return nil
        }
    }

    private func material(for kind: SceneMaterialKind, brightness: Double) -> UnlitMaterial {
        let colour = ModelPalette.color(for: kind).scaled(by: CGFloat(brightness))
        var material: UnlitMaterial
        if #available(iOS 18.0, *) {
            // Show the baked colour as it is, with no tone curve laid over it.
            material = UnlitMaterial(color: colour, applyPostProcessToneMap: false)
        } else {
            material = UnlitMaterial(color: colour)
        }
        let opacity = ModelPalette.opacity(for: kind, seeThroughWalls: seeThroughWalls)
        if opacity < 1 {
            material.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: opacity))
        }
        return material
    }

    private func isVisible(_ kind: SceneMaterialKind) -> Bool {
        kind != .ceiling || showsCeiling
    }

    /// Switches the walls between solid and faint.
    func setSeeThroughWalls(_ on: Bool) {
        guard on != seeThroughWalls else { return }
        seeThroughWalls = on
        for piece in pieces where piece.kind == .wall || piece.kind == .wallReveal {
            piece.entity.model?.materials = [material(for: piece.kind, brightness: piece.brightness)]
        }
    }

    func setCeilingVisible(_ visible: Bool) {
        showsCeiling = visible
        for piece in pieces where piece.kind == .ceiling { piece.entity.isEnabled = visible }
    }

    func setBackground(dark: Bool) {
        view.environment.background = .color(ModelPalette.background(dark: dark))
    }

    // MARK: Camera and projection

    func apply(camera: SceneCamera) {
        let p = camera.position, t = camera.target
        cameraEntity.look(at: SIMD3<Float>(Float(t.x), Float(t.y), Float(t.z)),
                          from: SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)),
                          relativeTo: nil)
    }

    /// Where a world point is in the view, nil when it cannot be projected (behind the camera).
    func project(_ point: Point3) -> CGPoint? {
        view.project(SIMD3<Float>(Float(point.x), Float(point.y), Float(point.z)))
    }

    /// The ray through a point in the view, in world space.
    func ray(through point: CGPoint) -> Ray3? {
        guard let r = view.ray(through: point) else { return nil }
        return Ray3(origin: Point3(Double(r.origin.x), Double(r.origin.y), Double(r.origin.z)),
                    direction: Point3(Double(r.direction.x), Double(r.direction.y), Double(r.direction.z)))
    }

    func tearDown() {
        for piece in pieces { piece.entity.removeFromParent() }
        pieces = []
        view.scene.removeAnchor(anchor)
    }
}

// MARK: - SwiftUI host

/// What the renderer has to show, for `updateUIView` to compare.
struct ModelRenderState: Equatable {
    var sceneVersion: Int
    var seeThroughWalls: Bool
    var showsCeiling: Bool
    var isMeasuring: Bool
    var isDark: Bool
}

/// Hosts the RealityKit view, the gestures that move the camera and the ticker that animates it.
struct ModelView: UIViewRepresentable {
    let controller: Viewer3DController
    let state: ModelRenderState

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        // The colours are baked flat, so every post effect that could change them is off.
        view.renderOptions.formUnion([.disableGroundingShadows, .disableMotionBlur, .disableDepthOfField,
                                      .disableCameraGrain, .disableHDR])
        // The picture carries no information VoiceOver can read; the SwiftUI wrapper describes it and
        // offers the actions.
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.apply(state)
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.detach()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let controller: Viewer3DController
        private var renderer: ModelRenderer?
        private var appliedState: ModelRenderState?
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0

        private var orbitRecognizer: UIPanGestureRecognizer?
        private var slideRecognizer: UIPanGestureRecognizer?
        private var pinchRecognizer: UIPinchGestureRecognizer?
        private var tapRecognizer: UITapGestureRecognizer?
        private var doubleTapRecognizer: UITapGestureRecognizer?

        init(controller: Viewer3DController) {
            self.controller = controller
        }

        func attach(to view: ARView) {
            let renderer = ModelRenderer(view: view)
            self.renderer = renderer

            controller.verticalFieldOfViewKnown = ModelRenderer.fieldOfViewIsVertical
            controller.cameraSink = { [weak renderer] camera in renderer?.apply(camera: camera) }
            controller.projector = { [weak renderer] point in renderer?.project(point) }
            controller.rayFactory = { [weak renderer] point in renderer?.ray(through: point) }
            controller.motionStarted = { [weak self] in self?.startDisplayLink() }

            let orbitGesture = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
            orbitGesture.minimumNumberOfTouches = 1
            orbitGesture.maximumNumberOfTouches = 1
            let slideGesture = UIPanGestureRecognizer(target: self, action: #selector(handleSlide(_:)))
            slideGesture.minimumNumberOfTouches = 2
            slideGesture.maximumNumberOfTouches = 2
            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTapGesture.numberOfTapsRequired = 2
            let all: [UIGestureRecognizer] = [orbitGesture, slideGesture, pinchGesture, tapGesture, doubleTapGesture]
            for recognizer in all {
                recognizer.delegate = self
                view.addGestureRecognizer(recognizer)
            }
            orbitRecognizer = orbitGesture
            slideRecognizer = slideGesture
            pinchRecognizer = pinchGesture
            tapRecognizer = tapGesture
            doubleTapRecognizer = doubleTapGesture

            controller.rendererAttached()
        }

        func detach() {
            stopDisplayLink()
            controller.cameraSink = nil
            controller.projector = nil
            controller.rayFactory = nil
            controller.motionStarted = nil
            renderer?.tearDown()
            renderer = nil
        }

        /// Brings the renderer up to date with what the controller and the interface ask for.
        func apply(_ state: ModelRenderState) {
            guard let renderer, state != appliedState else { return }
            let previous = appliedState
            appliedState = state
            if previous == nil || previous?.sceneVersion != state.sceneVersion {
                let report = renderer.rebuild(scene: controller.fullScene)
                // Told after this update pass: the controller's state is read by views that are still updating.
                let host = controller
                Task { host.rendererBuilt(batches: report.batches, failed: report.failed) }
            }
            if previous == nil || previous?.seeThroughWalls != state.seeThroughWalls {
                renderer.setSeeThroughWalls(state.seeThroughWalls)
            }
            if previous == nil || previous?.showsCeiling != state.showsCeiling {
                renderer.setCeilingVisible(state.showsCeiling)
            }
            if previous == nil || previous?.isDark != state.isDark {
                renderer.setBackground(dark: state.isDark)
            }
            // Taps place tape points while measuring; a double tap shows the whole floor otherwise.
            tapRecognizer?.isEnabled = state.isMeasuring
            doubleTapRecognizer?.isEnabled = !state.isMeasuring
            controller.rendererAttached()
        }

        // MARK: Gestures

        @objc private func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            switch g.state {
            case .began:
                controller.beginCameraInteraction()
            case .changed:
                let t = g.translation(in: view)
                g.setTranslation(.zero, in: view)
                controller.orbit(dx: Double(t.x), dy: Double(t.y))
            case .ended:
                let v = g.velocity(in: view)
                controller.endOrbit(velocityX: Double(v.x), velocityY: Double(v.y))
            default:
                break
            }
        }

        @objc private func handleSlide(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            switch g.state {
            case .began:
                controller.beginCameraInteraction()
            case .changed:
                let t = g.translation(in: view)
                g.setTranslation(.zero, in: view)
                controller.panCamera(dx: Double(t.x), dy: Double(t.y))
            default:
                break
            }
        }

        @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                controller.beginCameraInteraction()
            case .changed:
                controller.zoomCamera(by: Double(g.scale))
                g.scale = 1
            default:
                break
            }
        }

        @objc private func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let view = g.view else { return }
            controller.handleTap(at: g.location(in: view))
        }

        @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            controller.showWholeFloor()
        }

        /// Two fingers may slide and pinch at the same time. Nothing else runs together.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (gestureRecognizer === slideRecognizer && other === pinchRecognizer)
                || (gestureRecognizer === pinchRecognizer && other === slideRecognizer)
        }

        // MARK: Ticker

        func startDisplayLink() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = 0
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            let now = link.timestamp
            let dt = lastTimestamp == 0 ? 1.0 / 60 : now - lastTimestamp
            lastTimestamp = now
            if !controller.advance(by: dt) { stopDisplayLink() }
        }
    }
}
