// SHIM of the part of Apple's QuartzCore the app touches (CADisplayLink). Declarations copied from the docs.
@_exported import Foundation

// shim: CFTimeInterval is a CoreFoundation typealias that Foundation re-exports on Apple platforms
public typealias CFTimeInterval = Double

// doc: QuartzCore/CADisplayLink
@objc public class CADisplayLink: NSObject {
    // doc: QuartzCore/CADisplayLink/init(target:selector:)
    public init(target: Any, selector sel: Selector) { fatalError() }
    // doc: QuartzCore/CADisplayLink/add(to:forMode:)
    public func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) { fatalError() }
    // doc: QuartzCore/CADisplayLink/invalidate()
    public func invalidate() { fatalError() }
    // doc: QuartzCore/CADisplayLink/timestamp
    public var timestamp: CFTimeInterval { fatalError() }
    // doc: QuartzCore/CADisplayLink/targetTimestamp
    public var targetTimestamp: CFTimeInterval { fatalError() }
    // doc: QuartzCore/CADisplayLink/isPaused
    public var isPaused: Bool { get { fatalError() } set { } }
    // doc: QuartzCore/CADisplayLink/duration
    public var duration: CFTimeInterval { fatalError() }
}
