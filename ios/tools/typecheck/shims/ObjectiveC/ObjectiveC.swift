// SHIM of the part of Apple's ObjectiveC module that Swift code needs for selectors. NSObject comes from the Linux
// Foundation, which provides it. On Apple platforms Foundation re-exports ObjectiveC, so run.sh imports this module into
// every file implicitly (-import-module). The reverse is NOT true (ObjectiveC does not re-export Foundation), so this module
// imports Foundation without re-exporting it: a file that forgets `import Foundation` must not get it through here.
import Foundation

// doc: ObjectiveC/NSObjectProtocol
@objc public protocol NSObjectProtocol {}
// shim: Foundation on Linux defines its own, non-@objc NSObjectProtocol; every ObjC protocol in the shims refines THIS one
// (written ObjectiveC.NSObjectProtocol) so that `@objc protocol` refinement and `optional` requirements type-check
extension NSObject: ObjectiveC.NSObjectProtocol {}

// doc: ObjectiveC/Selector
public struct Selector: ExpressibleByStringLiteral, Hashable, Sendable {
    // shim: storage
    public let name: String
    // doc: ObjectiveC/Selector/init(_:)
    public init(_ str: String) { name = str }
    // shim: lets `#selector(...)` and string literals build a Selector
    public init(stringLiteral value: String) { name = value }
}
