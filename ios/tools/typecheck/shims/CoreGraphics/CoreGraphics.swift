// SHIM of the CoreGraphics types that Linux Foundation does not provide. CGFloat, CGPoint, CGSize and CGRect come from
// Foundation on Linux (and on Apple platforms Foundation re-exports CoreGraphics), so they are not redeclared here.
// Declarations are copied from Apple's documentation; each carries a `// doc:` tag that docs/verify_shims.py re-checks.
@_exported import Foundation

// doc: CoreGraphics/CGLineCap
public enum CGLineCap: Int32, Equatable, Hashable, Sendable {
    // doc: CoreGraphics/CGLineCap/butt
    case butt
    // doc: CoreGraphics/CGLineCap/round
    case round
    // doc: CoreGraphics/CGLineCap/square
    case square
}

// doc: CoreGraphics/CGLineJoin
public enum CGLineJoin: Int32, Equatable, Hashable, Sendable {
    // doc: CoreGraphics/CGLineJoin/miter
    case miter
    // doc: CoreGraphics/CGLineJoin/round
    case round
    // doc: CoreGraphics/CGLineJoin/bevel
    case bevel
}

// doc: CoreFoundation/CGAffineTransform
public struct CGAffineTransform: Equatable, Sendable {
    // doc-unconfirmed: the struct's members are not listed on its docs page (only the CGAffineTransform* C functions are)
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat
    // doc-unconfirmed: see above
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) { self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty }
    // doc-unconfirmed: see above
    public static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
}
