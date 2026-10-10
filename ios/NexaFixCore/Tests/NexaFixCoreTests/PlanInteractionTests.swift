import XCTest
@testable import NexaFixCore

final class PlanInteractionTests: XCTestCase {

    // MARK: Helpers

    private struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 11) & 0xFFFFFFFF) / Double(0x100000000)
        }
        mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
    }

    private let phone = ScreenSize(width: 390, height: 700)

    private func content(_ bounds: Bounds2 = Bounds2(min: Point2(0, 0), max: Point2(12, 8)),
                         size: ScreenSize? = nil, padding: Double = 24) -> PlanContent {
        PlanContent(bounds: bounds, size: size ?? phone, padding: padding)
    }

    private func assertEqual(_ a: Point2, _ b: Point2, accuracy: Double = 1e-9, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
    }

    // MARK: Rubber band and momentum (exact formulas)

    func testRubberbandMatchesTheFormula() {
        // (overshoot x dimension x constant) / (dimension + constant x |overshoot|)
        let expected100: Double = (100.0 * 400.0 * 0.55) / (400.0 + 0.55 * 100.0)
        XCTAssertEqual(GestureMath.rubberband(100, dimension: 400), expected100, accuracy: 1e-12)
        XCTAssertEqual(GestureMath.rubberband(100, dimension: 400), 48.35164835, accuracy: 1e-6)
        XCTAssertEqual(GestureMath.rubberband(-100, dimension: 400), -48.35164835, accuracy: 1e-6)
        XCTAssertEqual(GestureMath.rubberband(0, dimension: 400), 0)
        let expected30: Double = (30.0 * 200.0 * 0.3) / (200.0 + 0.3 * 30.0)
        XCTAssertEqual(GestureMath.rubberband(30, dimension: 200, constant: 0.3), expected30, accuracy: 1e-12)
        XCTAssertEqual(PlanViewport.rubberband(80, dimension: 300), GestureMath.rubberband(80, dimension: 300))
    }

    func testRubberbandResistsMoreTheFurtherYouPull() {
        var previous = 0.0
        var previousStep = Double.infinity
        for overshoot in stride(from: 10.0, through: 1000, by: 10) {
            let value = GestureMath.rubberband(overshoot, dimension: 400)
            XCTAssertGreaterThan(value, previous)                      // keeps moving
            let step = value - previous
            XCTAssertLessThan(step, previousStep + 1e-12)              // but each step moves less
            XCTAssertLessThan(value, 400)                              // never as far as the view is wide
            XCTAssertLessThan(value, overshoot)
            previous = value
            previousStep = step
        }
        // Right at the start it follows at the constant's rate.
        XCTAssertEqual(GestureMath.rubberband(0.001, dimension: 400) / 0.001, 0.55, accuracy: 1e-3)
    }

    func testProjectMatchesTheFormula() {
        // (velocity / 1000) x rate / (1 - rate)
        XCTAssertEqual(GestureMath.project(1000), 499, accuracy: 1e-9)
        XCTAssertEqual(GestureMath.project(-500), -249.5, accuracy: 1e-9)
        XCTAssertEqual(GestureMath.project(0), 0)
        XCTAssertEqual(GestureMath.project(800, decelerationRate: 0.99), 0.8 * 0.99 / 0.01, accuracy: 1e-9)
        XCTAssertEqual(PlanViewport.project(1234), GestureMath.project(1234))
        XCTAssertEqual(GestureMath.project(2000), 2 * GestureMath.project(1000), accuracy: 1e-9)   // linear in speed
    }

    func testDecayAgreesWithTheProjection() {
        // Coasting for ever travels exactly the projected distance: integrate decayed() in small steps.
        var v = 1500.0
        var travelled = 0.0
        let dt = 0.001
        for _ in 0..<20000 {
            travelled += v * dt
            v = GestureMath.decayed(v, over: dt)
        }
        XCTAssertEqual(travelled, GestureMath.project(1500), accuracy: GestureMath.project(1500) * 0.01)
        XCTAssertEqual(GestureMath.decayed(100, over: 0), 100)
        XCTAssertEqual(GestureMath.decayed(.nan, over: 1), 0)
    }

    // MARK: Spring

    func testCriticalSpringNeverOvershoots() {
        var spring = Spring1D(value: 0, target: 100)
        var last = 0.0
        for _ in 0..<200 {
            spring.advance(by: 1.0 / 60, response: 0.35, dampingFraction: 1)
            XCTAssertGreaterThanOrEqual(spring.value, last - 1e-12)
            XCTAssertLessThanOrEqual(spring.value, 100 + 1e-9)
            last = spring.value
        }
        XCTAssertEqual(spring.value, 100, accuracy: 1e-6)
        XCTAssertTrue(spring.isSettled(tolerance: 0.01))
    }

    func testResponseIsAboutHowLongItTakes() {
        // For a critically damped spring, (1 + wt) e^(-wt) with w = 2 pi / response: after `response` seconds
        // about 1.4 % of the distance is left.
        var spring = Spring1D(value: 0, target: 1)
        spring.advance(by: 0.35, response: 0.35, dampingFraction: 1)
        XCTAssertEqual(1 - spring.value, 7.2832 * exp(-6.2832), accuracy: 1e-3)
        XCTAssertLessThan(1 - spring.value, 0.02)
    }

    func testBouncySpringOvershootsThenSettles() {
        var spring = Spring1D(value: 0, target: 100)
        var peak = 0.0
        for _ in 0..<600 {
            spring.advance(by: 1.0 / 60, response: 0.30, dampingFraction: 0.8)
            peak = max(peak, spring.value)
        }
        XCTAssertGreaterThan(peak, 100.5)            // the momentum spring has a little life
        XCTAssertLessThan(peak, 110)                 // but not much
        XCTAssertEqual(spring.value, 100, accuracy: 1e-6)
    }

    func testSpringStepsComposeExactly() {
        // The solution is exact, so one long step equals many short ones.
        for damping in [1.0, 0.8, 0.5] {
            var whole = Spring1D(value: 3, velocity: 40, target: -7)
            var parts = whole
            whole.advance(by: 0.3, response: 0.4, dampingFraction: damping)
            for _ in 0..<30 { parts.advance(by: 0.01, response: 0.4, dampingFraction: damping) }
            XCTAssertEqual(whole.value, parts.value, accuracy: 1e-9, "damping \(damping)")
            XCTAssertEqual(whole.velocity, parts.velocity, accuracy: 1e-9, "damping \(damping)")
        }
    }

    func testSpringKeepsItsVelocityWhenRetargeted() {
        var spring = Spring1D(value: 0, target: 100)
        for _ in 0..<5 { spring.advance(by: 1.0 / 60, response: 0.35, dampingFraction: 1) }
        let v = spring.velocity
        XCTAssertGreaterThan(v, 0)
        spring.target = -50
        let before = spring.value
        spring.advance(by: 0.001, response: 0.35, dampingFraction: 1)
        XCTAssertGreaterThan(spring.value, before)         // still travelling the old way for an instant
        XCTAssertEqual(spring.velocity, v, accuracy: v * 0.5 )
    }

    func testSpringIgnoresNonsense() {
        var spring = Spring1D(value: 1, target: 5)
        spring.advance(by: .nan, response: 0.35, dampingFraction: 1)
        spring.advance(by: -1, response: 0.35, dampingFraction: 1)
        XCTAssertEqual(spring.value, 1)
        spring.advance(by: 0.1, response: 0, dampingFraction: 1)
        XCTAssertEqual(spring.value, 5)
        XCTAssertEqual(spring.velocity, 0)
    }

    // MARK: Velocity

    func testVelocityTrackerMeasuresTheLastFewSamples() {
        var tracker = PanVelocityTracker()
        for i in 0...10 {
            tracker.add(time: 5 + Double(i) * 0.01, x: 100 * Double(i) * 0.01, y: -50 * Double(i) * 0.01)
        }
        let v = tracker.velocity(at: 5.10)
        XCTAssertEqual(v.x, 100, accuracy: 1e-6)
        XCTAssertEqual(v.y, -50, accuracy: 1e-6)
        // Still while the finger rested before lifting: no flick.
        assertEqual(tracker.velocity(at: 5.10 + 0.2), .zero)
        tracker.reset()
        assertEqual(tracker.velocity(at: 5.1), .zero)
    }

    func testVelocityTrackerFollowsSpeedChangesAndIgnoresJunk() {
        var tracker = PanVelocityTracker()
        // Slow for a long time, then a fast flick in the last 50 ms.
        for i in 0..<30 { tracker.add(time: Double(i) * 0.01, x: Double(i) * 0.1, y: 0) }
        for i in 1...5 { tracker.add(time: 0.29 + Double(i) * 0.01, x: 2.9 + Double(i) * 5, y: 0) }
        XCTAssertGreaterThan(tracker.velocity(at: 0.34).x, 250)   // dominated by the recent samples
        tracker.add(time: .nan, x: 1, y: 1)
        tracker.add(time: 1, x: .infinity, y: 1)
        XCTAssertTrue(tracker.velocity(at: 0.34).x.isFinite)
        // A single sample says nothing.
        var one = PanVelocityTracker()
        one.add(time: 1, x: 10, y: 10)
        assertEqual(one.velocity(at: 1), .zero)
        // A clock that jumps back starts over.
        one.add(time: 0.5, x: 0, y: 0)
        assertEqual(one.velocity(at: 0.5), .zero)
    }

    // MARK: Fitting and transforms

    func testFitCentresTheDrawingWithPadding() {
        let bounds = Bounds2(min: Point2(2, 3), max: Point2(14, 11))        // 12 x 8
        let vp = PlanViewport.fit(bounds: bounds, in: phone, padding: 24)
        // Width limits: (390 - 48) / 12.
        XCTAssertEqual(vp.scale, 342.0 / 12, accuracy: 1e-9)
        // The drawing's centre sits at the view's centre.
        assertEqual(vp.screen(bounds.center), phone.center)
        // Edges: 24 pt from the sides.
        XCTAssertEqual(vp.screen(bounds.min).x, 24, accuracy: 1e-9)
        XCTAssertEqual(vp.screen(bounds.max).x, 390 - 24, accuracy: 1e-9)
        // y is up on the plan, down on the screen.
        XCTAssertGreaterThan(vp.screen(bounds.min).y, vp.screen(bounds.max).y)

        let wide = ScreenSize(width: 900, height: 300)
        let w = PlanViewport.fit(bounds: bounds, in: wide, padding: 20)
        XCTAssertEqual(w.scale, (300.0 - 40) / 8, accuracy: 1e-9)          // height limits
        assertEqual(w.screen(bounds.center), wide.center)
    }

    func testFitSurvivesDegenerateInput() {
        let point = Bounds2(min: Point2(5, 5), max: Point2(5, 5))
        let a = PlanViewport.fit(bounds: point, in: phone)
        XCTAssertEqual(a.scale, 1)
        assertEqual(a.screen(Point2(5, 5)), phone.center)
        let line = Bounds2(min: Point2(0, 2), max: Point2(10, 2))
        XCTAssertEqual(PlanViewport.fit(bounds: line, in: phone, padding: 20).scale, 350.0 / 10, accuracy: 1e-9)
        XCTAssertEqual(PlanViewport.fit(bounds: line, in: ScreenSize(width: 0, height: 0)), PlanViewport(scale: 1, offset: .zero))
        let huge = PlanViewport.fit(bounds: line, in: ScreenSize(width: 30, height: 30), padding: 100)
        XCTAssertGreaterThan(huge.scale, 0)
        XCTAssertTrue(huge.scale.isFinite && huge.offset.x.isFinite)
        let nan = PlanViewport.fit(bounds: Bounds2(min: Point2(.nan, 0), max: Point2(1, 1)), in: phone)
        XCTAssertTrue(nan.scale.isFinite)
    }

    func testTransformsRoundTrip() {
        var rng = LCG(state: 7)
        for _ in 0..<200 {
            let vp = PlanViewport(scale: rng.range(0.5, 400), offset: Point2(rng.range(-900, 900), rng.range(-900, 900)))
            let p = Point2(rng.range(-50, 50), rng.range(-50, 50))
            assertEqual(vp.plan(vp.screen(p)), p, accuracy: 1e-8)
            let s = Point2(rng.range(-500, 500), rng.range(-500, 500))
            assertEqual(vp.screen(vp.plan(s)), s, accuracy: 1e-8)
        }
        let vp = PlanViewport(scale: 40, offset: Point2(100, 600))
        assertEqual(vp.screen(.zero), Point2(100, 600))
        assertEqual(vp.screen(Point2(1, 1)), Point2(140, 560))      // right and UP the plan is right and up the screen
        XCTAssertEqual(vp.metres(forPoints: 22), 0.55, accuracy: 1e-12)
        XCTAssertEqual(vp.points(forMetres: 0.55), 22, accuracy: 1e-12)
        XCTAssertEqual(PlanViewport(scale: 0, offset: .zero).metres(forPoints: 22), 0)
        assertEqual(PlanViewport(scale: 0, offset: .zero).plan(Point2(5, 5)), .zero)
    }

    func testZoomKeepsThePointUnderTheFingersStill() {
        var rng = LCG(state: 11)
        for _ in 0..<200 {
            let vp = PlanViewport(scale: rng.range(5, 100), offset: Point2(rng.range(-200, 200), rng.range(-200, 200)))
            let anchor = Point2(rng.range(0, 390), rng.range(0, 700))
            let factor = rng.range(0.2, 6)
            let under = vp.plan(anchor)
            let zoomed = vp.zoomed(by: factor, about: anchor)
            XCTAssertEqual(zoomed.scale, vp.scale * factor, accuracy: 1e-9)
            assertEqual(zoomed.screen(under), anchor, accuracy: 1e-8)
            assertEqual(zoomed.plan(anchor), under, accuracy: 1e-8)
        }
    }

    func testZoomsComposeAndInvalidFactorsAreIgnored() {
        let vp = PlanViewport(scale: 20, offset: Point2(30, 400))
        let anchor = Point2(200, 300)
        let a = vp.zoomed(by: 2, about: anchor).zoomed(by: 3, about: anchor)
        let b = vp.zoomed(by: 6, about: anchor)
        XCTAssertEqual(a.scale, b.scale, accuracy: 1e-9)
        assertEqual(a.offset, b.offset, accuracy: 1e-8)
        assertEqual(vp.zoomed(by: 2, about: anchor).zoomed(by: 0.5, about: anchor).offset, vp.offset, accuracy: 1e-8)
        for bad in [0.0, -1, .nan, .infinity] { XCTAssertEqual(vp.zoomed(by: bad, about: anchor), vp) }
        XCTAssertEqual(vp.zoomed(by: 2, about: Point2(.nan, 1)), vp)
        XCTAssertEqual(vp.zoomed(toScale: 60, about: anchor).scale, 60, accuracy: 1e-9)
        XCTAssertEqual(vp.zoomed(toScale: -3, about: anchor), vp)
    }

    func testTranslatingFollowsTheFingerOneToOne() {
        let vp = PlanViewport(scale: 30, offset: Point2(10, 20))
        let grab = Point2(150, 250)
        let under = vp.plan(grab)
        let moved = vp.translated(by: Point2(37, -12))
        assertEqual(moved.screen(under), Point2(187, 238))
    }

    func testVisibleBoundsCoverTheView() {
        let vp = PlanViewport(scale: 25, offset: Point2(-40, 500))
        let visible = vp.visiblePlanBounds(in: phone)
        assertEqual(vp.screen(Point2(visible.min.x, visible.max.y)), Point2(0, 0), accuracy: 1e-9)
        assertEqual(vp.screen(Point2(visible.max.x, visible.min.y)), Point2(390, 700), accuracy: 1e-9)
        let grown = vp.visiblePlanBounds(in: phone, margin: 50)
        XCTAssertEqual(grown.width, visible.width + 100 / 25, accuracy: 1e-9)
        XCTAssertEqual(grown.height, visible.height + 100 / 25, accuracy: 1e-9)
    }

    // MARK: Zoom limits

    func testZoomRangeIsHalfFitToFortyTimesFit() {
        let limits = PlanZoomLimits(fitScale: 30)
        XCTAssertEqual(limits.minScale, 15)
        XCTAssertEqual(limits.maxScale, 1200)
        XCTAssertEqual(limits.clamp(1), 15)
        XCTAssertEqual(limits.clamp(5000), 1200)
        XCTAssertEqual(limits.clamp(100), 100)
        XCTAssertEqual(limits.clamp(.nan), 30)
        XCTAssertEqual(PlanZoomLimits(fitScale: -1).fitScale, 1)
        XCTAssertEqual(PlanViewport.zoomLimits(for: content()).fitScale, PlanViewport.fit(content()).scale, accuracy: 1e-12)
    }

    func testRubberBandedZoomYieldsPastTheLimits() {
        let limits = PlanZoomLimits(fitScale: 30)
        XCTAssertEqual(limits.rubberBanded(100), 100)
        XCTAssertEqual(limits.rubberBanded(15), 15, accuracy: 1e-9)
        XCTAssertEqual(limits.rubberBanded(1200), 1200, accuracy: 1e-9)
        var previous = 1200.0
        for factor in [1.1, 1.3, 1.6, 2, 4, 16, 1000] {
            let banded = limits.rubberBanded(1200 * factor)
            XCTAssertGreaterThan(banded, previous - 1e-9)      // keeps going up
            XCTAssertLessThan(banded, 1200 * factor)           // but slower than the pinch
            XCTAssertLessThan(banded, 1200 * 2)                // and never more than an octave past the limit
            previous = banded
        }
        var low = 15.0
        for factor in [1.1, 1.3, 2, 8, 1000] {
            let banded = limits.rubberBanded(15 / factor)
            XCTAssertLessThan(banded, low + 1e-9)
            XCTAssertGreaterThan(banded, 15 / factor)
            XCTAssertGreaterThan(banded, 15 / 2 - 1e-9)
            low = banded
        }
        XCTAssertEqual(limits.rubberBanded(.nan), 30)
        XCTAssertEqual(limits.rubberBanded(-4), 30)
    }

    // MARK: Pan limits

    func testPanRangeKeepsALargeDrawingUnderTheView() {
        let c = content()
        let big = PlanViewport.fit(c).zoomed(by: 4, about: c.size.center)
        let r = big.offsetRanges(for: c)
        // Larger than the view on both axes (12 m x 8 m at 4x fit): the range has width.
        XCTAssertGreaterThan(r.x.upperBound - r.x.lowerBound, 0)
        XCTAssertGreaterThan(r.y.upperBound - r.y.lowerBound, 0)
        // At the range's ends the drawing's edge (plus padding) is exactly at the view's edge.
        let atLeft = PlanViewport(scale: big.scale, offset: Point2(r.x.upperBound, r.y.upperBound))
        XCTAssertEqual(atLeft.screen(c.bounds.min).x, c.padding, accuracy: 1e-9)
        XCTAssertEqual(atLeft.screen(c.bounds.max).y, c.padding, accuracy: 1e-9)
        let atRight = PlanViewport(scale: big.scale, offset: Point2(r.x.lowerBound, r.y.lowerBound))
        XCTAssertEqual(atRight.screen(c.bounds.max).x, phone.width - c.padding, accuracy: 1e-9)
        XCTAssertEqual(atRight.screen(c.bounds.min).y, phone.height - c.padding, accuracy: 1e-9)
    }

    func testASmallDrawingStaysCentred() {
        let c = content()
        let small = PlanViewport.fit(c).zoomed(by: 0.5, about: c.size.center)
        let r = small.offsetRanges(for: c)
        XCTAssertEqual(r.x.lowerBound, r.x.upperBound)
        XCTAssertEqual(r.y.lowerBound, r.y.upperBound)
        assertEqual(small.screen(c.bounds.center), c.size.center, accuracy: 1e-9)
        assertEqual(Point2(r.x.lowerBound, r.y.lowerBound), small.offset, accuracy: 1e-9)
    }

    func testFitIsAFixedPointOfTheConstraints() {
        for bounds in [Bounds2(min: Point2(0, 0), max: Point2(12, 8)), Bounds2(min: Point2(-3, 2), max: Point2(5, 30)),
                       Bounds2(min: Point2(100, 100), max: Point2(100.5, 100.2))] {
            let c = content(bounds)
            let fit = PlanViewport.fit(c)
            let hard = fit.constrained(to: c, rubberBand: false)
            let soft = fit.constrained(to: c, rubberBand: true)
            XCTAssertEqual(hard.scale, fit.scale, accuracy: 1e-9)
            assertEqual(hard.offset, fit.offset, accuracy: 1e-6)
            assertEqual(soft.offset, fit.offset, accuracy: 1e-6)
        }
    }

    func testPastTheEdgeAHardClampStopsAndARubberBandYields() {
        let c = content()
        let big = PlanViewport.fit(c).zoomed(by: 4, about: c.size.center)
        let limits = big.offsetRanges(for: c)
        // Drag 300 points past the left limit.
        let dragged = PlanViewport(scale: big.scale, offset: Point2(limits.x.upperBound + 300, big.offset.y))
        let hard = dragged.constrained(to: c, rubberBand: false)
        XCTAssertEqual(hard.offset.x, limits.x.upperBound, accuracy: 1e-9)
        let soft = dragged.constrained(to: c, rubberBand: true)
        let expectedGive = GestureMath.rubberband(300, dimension: phone.width)
        XCTAssertEqual(soft.offset.x, limits.x.upperBound + expectedGive, accuracy: 1e-9)
        XCTAssertGreaterThan(soft.offset.x, limits.x.upperBound)
        XCTAssertLessThan(soft.offset.x, dragged.offset.x)
        // The other axis, inside its range, is untouched.
        XCTAssertEqual(soft.offset.y, big.offset.y, accuracy: 1e-9)
        // Past the other end.
        let low = PlanViewport(scale: big.scale, offset: Point2(big.offset.x, limits.y.lowerBound - 200))
        XCTAssertEqual(low.constrained(to: c, rubberBand: false).offset.y, limits.y.lowerBound, accuracy: 1e-9)
        XCTAssertEqual(low.constrained(to: c, rubberBand: true).offset.y,
                       limits.y.lowerBound - GestureMath.rubberband(200, dimension: phone.height), accuracy: 1e-9)
    }

    func testOvershootingTheZoomIsCorrectedAboutThePinchPoint() {
        let c = content()
        let fit = PlanViewport.fit(c)
        let anchor = Point2(300, 200)
        let tooFar = fit.zoomed(by: 100, about: anchor)
        let hard = tooFar.constrained(to: c, rubberBand: false, anchor: anchor)
        XCTAssertEqual(hard.scale, fit.scale * 40, accuracy: 1e-9)
        let soft = tooFar.constrained(to: c, rubberBand: true, anchor: anchor)
        XCTAssertGreaterThan(soft.scale, fit.scale * 40)
        XCTAssertLessThan(soft.scale, fit.scale * 100)
        let tooSmall = fit.zoomed(by: 0.05, about: anchor)
        XCTAssertEqual(tooSmall.constrained(to: c, rubberBand: false).scale, fit.scale * 0.5, accuracy: 1e-9)
    }

    func testConstrainingNonsenseFallsBackToTheFit() {
        let c = content()
        XCTAssertEqual(PlanViewport(scale: .nan, offset: .zero).constrained(to: c, rubberBand: true), PlanViewport.fit(c))
        XCTAssertEqual(PlanViewport(scale: 10, offset: Point2(.nan, 0)).constrained(to: c, rubberBand: false), PlanViewport.fit(c))
        XCTAssertEqual(PlanViewport(scale: -4, offset: .zero).constrained(to: c, rubberBand: false), PlanViewport.fit(c))
        let nobody = PlanContent(bounds: c.bounds, size: ScreenSize(width: 0, height: 100))
        XCTAssertEqual(PlanViewport(scale: 10, offset: .zero).settleTarget(velocity: Point2(900, 0), content: nobody),
                       PlanViewport(scale: 10, offset: .zero))
        let nanBounds = PlanContent(bounds: Bounds2(min: Point2(.nan, 0), max: Point2(1, 1)), size: phone)
        let r = PlanViewport(scale: 10, offset: .zero).offsetRanges(for: nanBounds)
        XCTAssertEqual(r.x, 0...0)
    }

    // MARK: Settling

    func testSettleProjectsTheFlickAndClampsIt() {
        let c = content()
        let big = PlanViewport.fit(c).zoomed(by: 4, about: c.size.center)
        let ranges = big.offsetRanges(for: c)
        let mid = PlanViewport(scale: big.scale,
                               offset: Point2((ranges.x.lowerBound + ranges.x.upperBound) / 2,
                                              (ranges.y.lowerBound + ranges.y.upperBound) / 2))

        // A gentle flick that stays inside: exactly the projection, added to the offset.
        let v = Point2(120, -80)
        let target = mid.settleTarget(velocity: v, content: c)
        assertEqual(target.offset, mid.offset + Point2(GestureMath.project(120), GestureMath.project(-80)), accuracy: 1e-9)
        XCTAssertEqual(target.scale, mid.scale, accuracy: 1e-12)

        // A hard flick is stopped at the edge.
        let far = mid.settleTarget(velocity: Point2(20000, -20000), content: c)
        XCTAssertEqual(far.offset.x, ranges.x.upperBound, accuracy: 1e-9)
        XCTAssertEqual(far.offset.y, ranges.y.lowerBound, accuracy: 1e-9)

        // Without momentum (Reduce Motion) nothing is projected.
        assertEqual(mid.settleTarget(velocity: v, content: c, momentum: false).offset, mid.offset, accuracy: 1e-9)

        // Let go while stretched past an edge: it comes back to the edge, whatever the finger was doing.
        let stretched = PlanViewport(scale: big.scale, offset: Point2(ranges.x.upperBound + 120, mid.offset.y))
        XCTAssertEqual(stretched.settleTarget(velocity: .zero, content: c).offset.x, ranges.x.upperBound, accuracy: 1e-9)
        XCTAssertEqual(stretched.settleTarget(velocity: Point2(-300, 0), content: c, momentum: false).offset.x,
                       ranges.x.upperBound, accuracy: 1e-9)
    }

    func testSettleTargetsAreAlwaysInsideTheLimits() {
        var rng = LCG(state: 99)
        let c = content()
        let fit = PlanViewport.fit(c)
        for _ in 0..<300 {
            let vp = fit.zoomed(by: rng.range(0.1, 90), about: Point2(rng.range(0, 390), rng.range(0, 700)))
                .translated(by: Point2(rng.range(-3000, 3000), rng.range(-3000, 3000)))
            let anchor = Point2(rng.range(0, 390), rng.range(0, 700))
            let target = vp.settleTarget(velocity: Point2(rng.range(-9000, 9000), rng.range(-9000, 9000)),
                                         content: c, anchor: anchor, momentum: rng.next() < 0.7)
            let limits = PlanViewport.zoomLimits(for: c)
            XCTAssertGreaterThanOrEqual(target.scale, limits.minScale - 1e-9)
            XCTAssertLessThanOrEqual(target.scale, limits.maxScale + 1e-9)
            let r = target.offsetRanges(for: c)
            XCTAssertTrue(r.x.contains(target.offset.x) || abs(target.offset.x - r.x.lowerBound) < 1e-6 || abs(target.offset.x - r.x.upperBound) < 1e-6)
            XCTAssertTrue(r.y.contains(target.offset.y) || abs(target.offset.y - r.y.lowerBound) < 1e-6 || abs(target.offset.y - r.y.upperBound) < 1e-6)
            // Settling twice changes nothing.
            let again = target.settleTarget(velocity: .zero, content: c, anchor: anchor)
            XCTAssertEqual(again.scale, target.scale, accuracy: 1e-9)
            assertEqual(again.offset, target.offset, accuracy: 1e-6)
        }
    }

    func testSettleCorrectsScaleAboutTheAnchor() {
        let c = content()
        let fit = PlanViewport.fit(c)
        let anchor = Point2(100, 100)
        let target = fit.zoomed(by: 300, about: anchor).settleTarget(velocity: .zero, content: c, anchor: anchor)
        XCTAssertEqual(target.scale, fit.scale * 40, accuracy: 1e-9)
    }

    // MARK: Render metrics

    func testStrokeWidthIsTheClampedWeight() {
        XCTAssertEqual(PlanRenderMetrics.strokeWidth(forPaperWeight: 0.13), 0.5)        // 0.286 -> floor
        XCTAssertEqual(PlanRenderMetrics.strokeWidth(forPaperWeight: 0.25), 0.55, accuracy: 1e-12)
        XCTAssertEqual(PlanRenderMetrics.strokeWidth(forPaperWeight: 0.5), 1.1, accuracy: 1e-12)
        XCTAssertEqual(PlanRenderMetrics.strokeWidth(forPaperWeight: 2), 3)             // 4.4 -> ceiling
        XCTAssertEqual(PlanRenderMetrics.strokeWidth(forPaperWeight: .nan), 0.5)
        XCTAssertEqual(PlanRenderMetrics.strokeWidth(forPaperWeight: -1), 0.5)
    }

    func testTextFadesInBetweenSevenAndNinePoints() {
        // 2.5 mm at 1:50 is a 0.125 m cap height; at 80 pt/m that is 10 pt of cap, 13.9 pt of font.
        XCTAssertEqual(PlanRenderMetrics.fontSize(capHeightMetres: 0.125, scale: 80), 10 / 0.718, accuracy: 1e-9)
        XCTAssertEqual(PlanRenderMetrics.fontSize(capHeightMetres: 0, scale: 80), 0)
        XCTAssertEqual(PlanRenderMetrics.fontSize(capHeightMetres: 0.1, scale: .nan), 0)
        XCTAssertEqual(PlanRenderMetrics.textOpacity(forFontSize: 6.9), 0)
        XCTAssertEqual(PlanRenderMetrics.textOpacity(forFontSize: 7), 0)
        XCTAssertEqual(PlanRenderMetrics.textOpacity(forFontSize: 8), 0.5, accuracy: 1e-12)
        XCTAssertEqual(PlanRenderMetrics.textOpacity(forFontSize: 9), 1)
        XCTAssertEqual(PlanRenderMetrics.textOpacity(forFontSize: 30), 1)
        XCTAssertEqual(PlanRenderMetrics.textOpacity(forFontSize: .nan), 0)
        var last = 0.0
        for size in stride(from: 5.0, through: 12, by: 0.25) {
            let o = PlanRenderMetrics.textOpacity(forFontSize: size)
            XCTAssertGreaterThanOrEqual(o, last)
            last = o
        }
    }

    func testRoomLabelsGrowToReadableSizeOnlyWhereTheyFit() {
        // A 6.5 pt label that is 40 pt wide would be 67.7 pt wide at 11 pt.
        XCTAssertEqual(PlanRenderMetrics.roomLabelFontSize(natural: 6.5, textWidthAtNatural: 40, roomWidthPoints: 200), 11)
        XCTAssertEqual(PlanRenderMetrics.roomLabelFontSize(natural: 6.5, textWidthAtNatural: 40, roomWidthPoints: 70), 6.5)
        XCTAssertEqual(PlanRenderMetrics.roomLabelFontSize(natural: 14, textWidthAtNatural: 80, roomWidthPoints: 50), 14)
        XCTAssertEqual(PlanRenderMetrics.roomLabelFontSize(natural: .nan, textWidthAtNatural: 40, roomWidthPoints: 70).isNaN, true)
    }

    func testDashesAndArcSegments() {
        XCTAssertEqual(PlanRenderMetrics.dashPattern(forStrokeWidth: 1), [6, 4])
        XCTAssertEqual(PlanRenderMetrics.dashPattern(forStrokeWidth: 0), [3, 2])
        XCTAssertEqual(PlanRenderMetrics.arcSegments(radiusPoints: 2, sweepDegrees: 90), 6)
        XCTAssertEqual(PlanRenderMetrics.arcSegments(radiusPoints: 100, sweepDegrees: 90), 53)
        XCTAssertEqual(PlanRenderMetrics.arcSegments(radiusPoints: 100000, sweepDegrees: 360), 120)
        XCTAssertEqual(PlanRenderMetrics.arcSegments(radiusPoints: .nan, sweepDegrees: 90), 6)
    }

    func testPrintColoursMapToRoles() {
        let p = PlanDrawingBuilder.Palette.self
        XCTAssertEqual(PlanColorRole.role(of: p.ink), .ink)
        XCTAssertEqual(PlanColorRole.role(of: p.paper), .paper)
        XCTAssertEqual(PlanColorRole.role(of: p.hairline), .hairline)
        XCTAssertEqual(PlanColorRole.role(of: p.muted), .muted)
        XCTAssertEqual(PlanColorRole.role(of: p.bronze), .bronze)
        XCTAssertEqual(PlanColorRole.role(of: p.verified), .verified)
        XCTAssertEqual(PlanColorRole.role(of: p.warning), .warning)
        XCTAssertEqual(PlanColorRole.role(of: p.furnitureFill), .furnitureFill)
        XCTAssertEqual(PlanColorRole.role(of: .black), .ink)
        XCTAssertEqual(PlanColorRole.role(of: .white), .paper)
        let odd = DrawColor(0.2, 0.4, 0.9)
        XCTAssertEqual(PlanColorRole.role(of: odd), .custom(odd))
        // Every colour the drawing builder actually uses has a role (none falls through to custom).
        let drawing = PlanDrawingBuilder.build(rooms: DemoProperty.make().allRooms, title: "t", subtitle: "s", options: PlanOptions())
        var used = Set<String>()
        for item in drawing.primitives {
            switch item.primitive {
            case .line(_, _, let s), .arc(_, _, _, _, let s), .circle(_, _, let s):
                used.insert("\(s.color)")
                if case .custom = PlanColorRole.role(of: s.color) { XCTFail("unmapped stroke colour \(s.color)") }
            case .polyline(_, _, let stroke, let fill):
                for c in [stroke?.color, fill].compactMap({ $0 }) {
                    if case .custom = PlanColorRole.role(of: c) { XCTFail("unmapped colour \(c)") }
                }
            case .text(_, _, _, _, _, let color, _):
                if case .custom = PlanColorRole.role(of: color) { XCTFail("unmapped text colour \(color)") }
            }
        }
        XCTAssertFalse(used.isEmpty)
    }

    // MARK: Hit testing: fixtures

    private func tester(_ rooms: [Room]) -> PlanHitTester { PlanHitTester(rooms: rooms) }

    private func rect(_ name: String = "Living", origin: Point2 = .zero, w: Double = 6, d: Double = 4,
                      openings: [OpeningSpec] = []) -> Room {
        Room.rectangle(name: name, kind: .livingRoom, origin: origin, width: w, depth: d, openings: openings)
    }

    private func lShape() -> Room {
        Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
    }

    // MARK: Hit testing

    func testTapInsideARoomSelectsTheRoom() {
        let room = rect()
        let t = tester([room])
        XCTAssertEqual(t.hit(at: Point2(3, 2), toleranceMetres: 0.2), .room(room.id))
        XCTAssertNil(t.hit(at: Point2(8, 2), toleranceMetres: 0.2))
        XCTAssertNil(t.hit(at: Point2(3, -1), toleranceMetres: 0.2))
    }

    func testWallsCornersAndTheirPriority() {
        let room = rect()
        let t = tester([room])
        // Near the middle of the south wall (plan y = 0).
        XCTAssertEqual(t.hit(at: Point2(3, 0.1), toleranceMetres: 0.25), .wall(room: room.id, wall: room.walls[0].id))
        XCTAssertEqual(t.hit(at: Point2(3, -0.1), toleranceMetres: 0.25), .wall(room: room.id, wall: room.walls[0].id))
        // Near the north-east corner: the corner beats both walls that meet there.
        XCTAssertEqual(t.hit(at: Point2(5.9, 3.9), toleranceMetres: 0.25), .corner(room: room.id, index: 2))
        XCTAssertEqual(t.hit(at: Point2(0.05, 0.05), toleranceMetres: 0.25), .corner(room: room.id, index: 0))
        // Further along the wall than the tolerance from the corner: the wall again.
        XCTAssertEqual(t.hit(at: Point2(5.5, 0.05), toleranceMetres: 0.25), .wall(room: room.id, wall: room.walls[0].id))
        // Outside the tolerance: the room, or nothing.
        XCTAssertEqual(t.hit(at: Point2(3, 0.5), toleranceMetres: 0.25), .room(room.id))
        XCTAssertNil(t.hit(at: Point2(3, -0.5), toleranceMetres: 0.25))
    }

    func testToleranceDecidesHowCloseIsClose() {
        let room = rect()
        let t = tester([room])
        let p = Point2(3, 0.3)
        XCTAssertEqual(t.hit(at: p, toleranceMetres: 0.2), .room(room.id))
        XCTAssertEqual(t.hit(at: p, toleranceMetres: 0.35), .wall(room: room.id, wall: room.walls[0].id))
        // Exactly on the wall with no tolerance at all.
        XCTAssertEqual(t.hit(at: Point2(3, 0), toleranceMetres: 0), .wall(room: room.id, wall: room.walls[0].id))
        // A tolerance that is not a number counts as none; a negative one too.
        XCTAssertEqual(t.hit(at: p, toleranceMetres: .nan), .room(room.id))
        XCTAssertEqual(t.hit(at: p, toleranceMetres: -5), .room(room.id))
        // Scaling with zoom: 22 points at 40 pt per metre is 0.55 m.
        let vp = PlanViewport(scale: 40, offset: .zero)
        XCTAssertEqual(t.hit(at: Point2(3, 0.5), toleranceMetres: vp.metres(forPoints: 22)), .wall(room: room.id, wall: room.walls[0].id))
    }

    func testOpeningsBeatTheWallTheyAreIn() {
        let room = rect(openings: [.door(wall: 0, offset: 1.0, width: 1.0), .window(wall: 2, offset: 1.0, width: 1.5)])
        let t = tester([room])
        let door = room.openings[0], window = room.openings[1]
        // The door is at x 1...2 on the south wall.
        XCTAssertEqual(t.hit(at: Point2(1.5, 0.05), toleranceMetres: 0.25), .opening(room: room.id, opening: door.id))
        // Beside the door the wall is hit.
        XCTAssertEqual(t.hit(at: Point2(4.0, 0.05), toleranceMetres: 0.25), .wall(room: room.id, wall: room.walls[0].id))
        // The window is on the north wall (y = 4), which runs from x = 6 to 0: offset 1 is x 5...3.5.
        XCTAssertEqual(t.hit(at: Point2(4.25, 3.95), toleranceMetres: 0.25), .opening(room: room.id, opening: window.id))
        // A corner still beats an opening when both are in reach.
        let tight = rect(openings: [.door(wall: 0, offset: 0.1, width: 0.9)])
        XCTAssertEqual(tester([tight]).hit(at: Point2(0.05, 0.02), toleranceMetres: 0.25), .corner(room: tight.id, index: 0))
        // An opening without a wall cannot be hit.
        var orphan = rect()
        orphan.openings = [Opening(kind: .door, wallID: nil, offsetFromWallStart: 1, width: Measured(scanned: 1), height: Measured(scanned: 2))]
        XCTAssertEqual(tester([orphan]).hit(at: Point2(3, 2), toleranceMetres: 0.3), .room(orphan.id))
    }

    func testFurnitureBeatsTheRoomButNotTheWalls() {
        var room = rect()
        let sofa = RoomObject(kind: .sofa, center: Point2(3, 2), yaw: 0, width: 2, depth: 1, height: 0.8)
        let cabinet = RoomObject(kind: .storage, center: Point2(3, 3.7), yaw: 0, width: 2, depth: 0.5, height: 2)
        room.objects = [sofa, cabinet]
        let t = tester([room])
        XCTAssertEqual(t.hit(at: Point2(3, 2), toleranceMetres: 0.2), .object(room: room.id, object: sofa.id))
        XCTAssertEqual(t.hit(at: Point2(3, 2.65), toleranceMetres: 0.2), .object(room: room.id, object: sofa.id))   // just off its edge
        XCTAssertEqual(t.hit(at: Point2(1, 1), toleranceMetres: 0.2), .room(room.id))
        // The cabinet stands against the north wall: a tap in reach of the wall selects the wall.
        XCTAssertEqual(t.hit(at: Point2(3, 3.9), toleranceMetres: 0.2), .wall(room: room.id, wall: room.walls[2].id))
        XCTAssertEqual(t.hit(at: Point2(3, 3.6), toleranceMetres: 0.2), .object(room: room.id, object: cabinet.id))
        // Of two overlapping objects, the nearer edge wins when the tap is outside both; inside both, the first.
        var stacked = rect()
        let a = RoomObject(kind: .table, center: Point2(3, 2), yaw: 0, width: 1, depth: 1, height: 0.7)
        let b = RoomObject(kind: .chair, center: Point2(3, 2), yaw: 0, width: 0.5, depth: 0.5, height: 0.9)
        stacked.objects = [a, b]
        XCTAssertEqual(tester([stacked]).hit(at: Point2(3, 2), toleranceMetres: 0.1), .object(room: stacked.id, object: a.id))
    }

    func testStraightContinuationsAreNotCorners() {
        // A rectangle with an extra vertex halfway along the south wall.
        let room = Room.polygon(name: "Split", corners: [Point2(0, 0), Point2(3, 0), Point2(6, 0), Point2(6, 4), Point2(0, 4)])
        let t = tester([room])
        // Directly above the extra vertex both walls are equally near; the earlier wall wins. It is not a corner.
        XCTAssertEqual(t.hit(at: Point2(3, 0.05), toleranceMetres: 0.2), .wall(room: room.id, wall: room.walls[0].id))
        XCTAssertEqual(t.hit(at: Point2(6, 0.05), toleranceMetres: 0.2), .corner(room: room.id, index: 2))
    }

    func testLShapedRoom() {
        let room = lShape()
        let t = tester([room])
        // Inside both arms.
        XCTAssertEqual(t.hit(at: Point2(5, 1), toleranceMetres: 0.2), .room(room.id))
        XCTAssertEqual(t.hit(at: Point2(2, 3), toleranceMetres: 0.2), .room(room.id))
        // The notch is outside the room.
        XCTAssertNil(t.hit(at: Point2(5, 3), toleranceMetres: 0.2))
        // The reflex corner is a corner (index 3 is the start of wall 3, at (4, 2)).
        XCTAssertEqual(t.hit(at: Point2(4.05, 1.95), toleranceMetres: 0.25), .corner(room: room.id, index: 3))
        XCTAssertEqual(t.hit(at: Point2(4.1, 2.1), toleranceMetres: 0.25), .corner(room: room.id, index: 3))
        // Walls of the notch.
        XCTAssertEqual(t.hit(at: Point2(5, 2.1), toleranceMetres: 0.2), .wall(room: room.id, wall: room.walls[2].id))
        XCTAssertEqual(t.hit(at: Point2(4.1, 3), toleranceMetres: 0.2), .wall(room: room.id, wall: room.walls[3].id))
        // The centroid of an L is not always inside it; the interior test still is right.
        XCTAssertTrue(Polygon.contains(room.outline, Point2(1, 1)))
    }

    func testSharedWallsOfNeighbouringRoomsPickTheNearerRoom() {
        let a = rect("A", w: 4, d: 4)
        let b = rect("B", origin: Point2(4.15, 0), w: 4, d: 4)
        let t = tester([a, b])
        let wallA = PlanSelection.wall(room: a.id, wall: a.walls[1].id)        // A's east wall at x = 4
        let wallB = PlanSelection.wall(room: b.id, wall: b.walls[3].id)        // B's west wall at x = 4.15
        XCTAssertEqual(t.hit(at: Point2(4.04, 2), toleranceMetres: 0.5), wallA)
        XCTAssertEqual(t.hit(at: Point2(4.11, 2), toleranceMetres: 0.5), wallB)
        // Dead in the middle: a tie, decided by the order of the rooms.
        XCTAssertEqual(t.hit(at: Point2(4.075, 2), toleranceMetres: 0.5), wallA)
        XCTAssertEqual(tester([b, a]).hit(at: Point2(4.075, 2), toleranceMetres: 0.5), wallB)
        // A tap in the gap with a small tolerance still finds the closer wall.
        XCTAssertEqual(t.hit(at: Point2(4.13, 2), toleranceMetres: 0.05), wallB)
        XCTAssertNil(t.hit(at: Point2(4.075, 2), toleranceMetres: 0.05))
    }

    func testRoomsOnTopOfEachOtherPickTheSmallerOne() {
        let big = rect("Big", w: 10, d: 10)
        let small = rect("Small", origin: Point2(2, 2), w: 3, d: 3)
        XCTAssertEqual(tester([big, small]).hit(at: Point2(3, 3), toleranceMetres: 0.1), .room(small.id))
        XCTAssertEqual(tester([small, big]).hit(at: Point2(3, 3), toleranceMetres: 0.1), .room(small.id))
        XCTAssertEqual(tester([big, small]).hit(at: Point2(8, 8), toleranceMetres: 0.1), .room(big.id))
    }

    func testHitTestingIgnoresBrokenInput() {
        var nan = rect()
        nan.walls[2].start = Point2(.nan, 1)
        let flat = Room(name: "Flat", walls: [], ceilingHeight: Measured(scanned: 2.4))
        let good = rect("Good", origin: Point2(20, 0))
        let t = tester([nan, flat, good])
        XCTAssertEqual(t.hit(at: Point2(23, 2), toleranceMetres: 0.2), .room(good.id))
        XCTAssertNil(t.hit(at: Point2(3, 2), toleranceMetres: 0.2))
        XCTAssertNil(t.hit(at: Point2(.nan, 2), toleranceMetres: 0.2))
        XCTAssertNil(t.hit(at: Point2(2, .infinity), toleranceMetres: 0.2))
        XCTAssertNil(tester([]).hit(at: .zero, toleranceMetres: 1))
    }

    func testRandomTapsAlwaysGiveSomethingThatExists() {
        var rng = LCG(state: 5)
        let rooms = DemoProperty.make().allRooms
        let t = tester(rooms)
        var hits = 0
        for _ in 0..<2000 {
            let p = Point2(rng.range(-2, 24), rng.range(-2, 16))
            if let selection = t.hit(at: p, toleranceMetres: rng.range(0, 0.8)) {
                hits += 1
                XCTAssertTrue(t.contains(selection))
                XCTAssertNotNil(t.selectionTitle(for: selection))
                XCTAssertFalse(t.highlightGeometry(for: selection).isEmpty)
                XCTAssertNotNil(t.summary(for: selection, units: .default))
            }
        }
        XCTAssertGreaterThan(hits, 200)
    }

    // MARK: Titles, summaries, highlights

    func testSelectionTitlesNameWhatTheyAre() {
        var room = rect("Master Bedroom", openings: [.door(wall: 0, offset: 1), .door(wall: 1, offset: 1),
                                                        .window(wall: 2, offset: 1, width: 1.5)])
        let sofa1 = RoomObject(kind: .sofa, center: Point2(2, 2), yaw: 0, width: 2, depth: 1, height: 0.8)
        let sofa2 = RoomObject(kind: .sofa, center: Point2(4, 2), yaw: 0, width: 2, depth: 1, height: 0.8)
        room.objects = [sofa1, sofa2]
        let t = tester([room])
        XCTAssertEqual(t.selectionTitle(for: .room(room.id)), "Master Bedroom")
        XCTAssertEqual(t.selectionTitle(for: .wall(room: room.id, wall: room.walls[1].id)), "Wall B")
        XCTAssertEqual(t.selectionTitle(for: .corner(room: room.id, index: 2)), "Corner C")
        XCTAssertEqual(t.selectionTitle(for: .opening(room: room.id, opening: room.openings[0].id)), "Door 1")
        XCTAssertEqual(t.selectionTitle(for: .opening(room: room.id, opening: room.openings[1].id)), "Door 2")
        XCTAssertEqual(t.selectionTitle(for: .opening(room: room.id, opening: room.openings[2].id)), "Window 1")
        XCTAssertEqual(t.selectionTitle(for: .object(room: room.id, object: sofa2.id)), "Sofa 2")
        // The 3D viewer and the snap points use the same names.
        let scene = RoomSceneBuilder.scene(for: [room])
        XCTAssertTrue(scene.meshes.contains { $0.label == "Sofa 2" })
        XCTAssertTrue(room.snapPoints().contains { $0.label == "Floor corner C" })

        // Things that no longer exist have no title.
        XCTAssertNil(t.selectionTitle(for: .room(UUID())))
        XCTAssertNil(t.selectionTitle(for: .wall(room: room.id, wall: UUID())))
        XCTAssertNil(t.selectionTitle(for: .corner(room: room.id, index: 9)))
        XCTAssertNil(t.selectionTitle(for: .corner(room: room.id, index: -1)))
        XCTAssertNil(t.selectionTitle(for: .opening(room: room.id, opening: UUID())))
        XCTAssertNil(t.selectionTitle(for: .object(room: room.id, object: UUID())))

        // An unnamed room takes its kind's name.
        var unnamed = rect()
        unnamed.name = "  "
        XCTAssertEqual(tester([unnamed]).selectionTitle(for: .room(unnamed.id)), "Living Room")
    }

    func testSummariesCarryNumbersAndProvenance() throws {
        let units = DisplayUnits(length: .millimetres, area: .squareMetres)
        var room = rect("Living", openings: [.door(wall: 0, offset: 1, width: 0.9)])

        let plain = try XCTUnwrap(tester([room]).summary(for: .room(room.id), units: units))
        XCTAssertEqual(plain.title, "Living")
        XCTAssertNil(plain.subtitle)
        XCTAssertEqual(plain.detail, "24.00 m\u{00B2}")
        XCTAssertTrue(plain.spoken.contains("24.00 square metres"), plain.spoken)
        XCTAssertTrue(plain.spoken.contains("6000 millimetres by 4000 millimetres"), plain.spoken)

        room.walls[1].length.verify(4.012, source: .laser)
        let t = tester([room])
        // A laser check flows into the room's area: 6.000 x 4.006.
        let checked = try XCTUnwrap(t.summary(for: .room(room.id), units: units))
        XCTAssertEqual(checked.detail, UnitFormatter.area(room.metrics.effectiveFloorArea, unit: .squareMetres))
        XCTAssertEqual(checked.detail, "24.04 m\u{00B2}")

        let scanned = try XCTUnwrap(t.summary(for: .wall(room: room.id, wall: room.walls[0].id), units: units))
        XCTAssertEqual(scanned.title, "Wall A")
        XCTAssertEqual(scanned.subtitle, "Living")
        XCTAssertEqual(scanned.detail, "6000 mm")
        XCTAssertTrue(scanned.spoken.contains("scanned, not checked"), scanned.spoken)
        XCTAssertTrue(scanned.spoken.contains("6000 millimetres"), scanned.spoken)

        let verified = try XCTUnwrap(t.summary(for: .wall(room: room.id, wall: room.walls[1].id), units: units))
        XCTAssertEqual(verified.detail, "4012 mm")                                  // the laser value, never the scan
        XCTAssertTrue(verified.spoken.contains("verified with laser"), verified.spoken)
        XCTAssertFalse(verified.spoken.contains("scanned"), verified.spoken)

        let corner = try XCTUnwrap(t.summary(for: .corner(room: room.id, index: 1), units: units))
        XCTAssertEqual(corner.title, "Corner B")
        XCTAssertEqual(corner.detail, "90.0\u{00B0}")
        XCTAssertTrue(corner.spoken.contains("90.0 degrees"), corner.spoken)
        XCTAssertFalse(corner.spoken.contains("out of square"), corner.spoken)

        let door = try XCTUnwrap(t.summary(for: .opening(room: room.id, opening: room.openings[0].id), units: units))
        XCTAssertEqual(door.title, "Door 1")
        XCTAssertEqual(door.detail, "900 mm \u{00D7} 2100 mm")
        XCTAssertTrue(door.spoken.contains("width 900 millimetres, height 2100 millimetres"), door.spoken)
        XCTAssertTrue(door.spoken.hasSuffix("scanned, not checked"), door.spoken)

        let imperial = try XCTUnwrap(t.summary(for: .wall(room: room.id, wall: room.walls[0].id),
                                               units: DisplayUnits(length: .feetAndInches, area: .squareFeet)))
        XCTAssertTrue(imperial.spoken.contains("feet"), imperial.spoken)
        XCTAssertNil(t.summary(for: .room(UUID()), units: units))
    }

    func testOutOfSquareCornersAreSpokenAs() throws {
        // Bedroom 2 in the demo has one corner at 91.5 degrees.
        let rooms = DemoProperty.make().allRooms
        let t = tester(rooms)
        var found = false
        for room in rooms {
            for corner in room.metrics.outOfSquareCorners {
                let summary = try XCTUnwrap(t.summary(for: .corner(room: room.id, index: corner.index), units: .default))
                XCTAssertTrue(summary.spoken.contains("out of square"), summary.spoken)
                found = true
            }
        }
        XCTAssertTrue(found)
    }

    func testHighlightGeometry() throws {
        var room = rect(openings: [.door(wall: 0, offset: 1, width: 1)])
        let table = RoomObject(kind: .table, center: Point2(3, 2), yaw: 0, width: 2, depth: 1, height: 0.7)
        room.objects = [table]
        let t = tester([room])

        let r = try XCTUnwrap(t.highlight(for: .room(room.id)))
        XCTAssertEqual(r.kind, .polygon)
        XCTAssertEqual(r.points, room.outline)
        let w = try XCTUnwrap(t.highlight(for: .wall(room: room.id, wall: room.walls[2].id)))
        XCTAssertEqual(w.kind, .polyline)
        XCTAssertEqual(w.points, [room.walls[2].start, room.walls[2].end])
        let c = try XCTUnwrap(t.highlight(for: .corner(room: room.id, index: 3)))
        XCTAssertEqual(c.kind, .point)
        XCTAssertEqual(c.points, [Point2(0, 4)])
        let o = try XCTUnwrap(t.highlight(for: .opening(room: room.id, opening: room.openings[0].id)))
        XCTAssertEqual(o.kind, .polyline)
        assertEqual(o.points[0], Point2(1, 0))
        assertEqual(o.points[1], Point2(2, 0))
        let obj = try XCTUnwrap(t.highlight(for: .object(room: room.id, object: table.id)))
        XCTAssertEqual(obj.kind, .polygon)
        XCTAssertEqual(obj.points.count, 4)
        XCTAssertEqual(Polygon.area(obj.points), 2, accuracy: 1e-9)

        XCTAssertEqual(t.highlightGeometry(for: .room(room.id)), room.outline)
        XCTAssertEqual(t.highlightGeometry(for: .room(UUID())), [])
        XCTAssertNil(t.highlight(for: .corner(room: room.id, index: 40)))
        XCTAssertFalse(t.contains(.object(room: room.id, object: UUID())))
        XCTAssertEqual(PlanSelection.corner(room: room.id, index: 1).roomID, room.id)
    }
}
