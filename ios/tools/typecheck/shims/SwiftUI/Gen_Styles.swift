// SHIM of SwiftUI, generated section. GENERATED from Apple's documentation pages: every declaration below is the
// text of a documentation page (iOS declaration, attributes verbatim) tagged with `// doc: <page>`;
// docs/verify_shims.py re-checks all of them against docs/declarations.json. Bodies are `fatalError()` (or `self`
// for `some View` modifiers): this module exists to be type-checked against, never to run.
// Declarations that mention a type this shim does not define were left out (listed in ../../docs/gen/prune.txt).
@_exported import Foundation
@_exported import CoreGraphics
import UIKit
import Observation

// doc: SwiftUI/PlainListStyle
public struct PlainListStyle {
    // doc: SwiftUI/PlainListStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/PlainListStyle
extension PlainListStyle: ListStyle {}

// doc: SwiftUI/InsetGroupedListStyle
public struct InsetGroupedListStyle {
    // doc: SwiftUI/InsetGroupedListStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/InsetGroupedListStyle
extension InsetGroupedListStyle: ListStyle {}

// doc: SwiftUI/GroupedListStyle
public struct GroupedListStyle {
    // doc: SwiftUI/GroupedListStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/GroupedListStyle
extension GroupedListStyle: ListStyle {}

// doc: SwiftUI/InsetListStyle
public struct InsetListStyle {
    // doc: SwiftUI/InsetListStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/InsetListStyle
extension InsetListStyle: ListStyle {}

// doc: SwiftUI/SidebarListStyle
public struct SidebarListStyle {
    // doc: SwiftUI/SidebarListStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/SidebarListStyle
extension SidebarListStyle: ListStyle {}

extension ListStyle where Self == GroupedListStyle {
    // doc: SwiftUI/ListStyle/grouped
    public static var grouped: GroupedListStyle { fatalError() }
}
extension ListStyle where Self == InsetListStyle {
    // doc: SwiftUI/ListStyle/inset
    public static var inset: InsetListStyle { fatalError() }
}
extension ListStyle where Self == InsetGroupedListStyle {
    // doc: SwiftUI/ListStyle/insetGrouped
    public static var insetGrouped: InsetGroupedListStyle { fatalError() }
}
extension ListStyle where Self == PlainListStyle {
    // doc: SwiftUI/ListStyle/plain
    public static var plain: PlainListStyle { fatalError() }
}
extension ListStyle where Self == SidebarListStyle {
    // doc: SwiftUI/ListStyle/sidebar
    public static var sidebar: SidebarListStyle { fatalError() }
}

// doc: SwiftUI/DefaultPickerStyle
public struct DefaultPickerStyle {
    // doc: SwiftUI/DefaultPickerStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/DefaultPickerStyle
extension DefaultPickerStyle: PickerStyle {}

// doc: SwiftUI/InlinePickerStyle
public struct InlinePickerStyle {
    // doc: SwiftUI/InlinePickerStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/InlinePickerStyle
extension InlinePickerStyle: PickerStyle {}

// doc: SwiftUI/MenuPickerStyle
public struct MenuPickerStyle {
    // doc: SwiftUI/MenuPickerStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/MenuPickerStyle
extension MenuPickerStyle: PickerStyle {}

// doc: SwiftUI/NavigationLinkPickerStyle
public struct NavigationLinkPickerStyle {
    // doc: SwiftUI/NavigationLinkPickerStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/NavigationLinkPickerStyle
extension NavigationLinkPickerStyle: PickerStyle {}

// doc: SwiftUI/PalettePickerStyle
public struct PalettePickerStyle {
    // doc: SwiftUI/PalettePickerStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/PalettePickerStyle
extension PalettePickerStyle: PickerStyle {}

// doc: SwiftUI/SegmentedPickerStyle
public struct SegmentedPickerStyle {
    // doc: SwiftUI/SegmentedPickerStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/SegmentedPickerStyle
extension SegmentedPickerStyle: PickerStyle {}

// doc: SwiftUI/WheelPickerStyle
public struct WheelPickerStyle {
    // doc: SwiftUI/WheelPickerStyle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/WheelPickerStyle
extension WheelPickerStyle: PickerStyle {}

extension PickerStyle where Self == DefaultPickerStyle {
    // doc: SwiftUI/PickerStyle/automatic
    public static var automatic: DefaultPickerStyle { fatalError() }
}
extension PickerStyle where Self == InlinePickerStyle {
    // doc: SwiftUI/PickerStyle/inline
    public static var inline: InlinePickerStyle { fatalError() }
}
extension PickerStyle where Self == MenuPickerStyle {
    // doc: SwiftUI/PickerStyle/menu
    public static var menu: MenuPickerStyle { fatalError() }
}
extension PickerStyle where Self == NavigationLinkPickerStyle {
    // doc: SwiftUI/PickerStyle/navigationLink
    public static var navigationLink: NavigationLinkPickerStyle { fatalError() }
}
extension PickerStyle where Self == PalettePickerStyle {
    // doc: SwiftUI/PickerStyle/palette
    public static var palette: PalettePickerStyle { fatalError() }
}
extension PickerStyle where Self == SegmentedPickerStyle {
    // doc: SwiftUI/PickerStyle/segmented
    public static var segmented: SegmentedPickerStyle { fatalError() }
}
extension PickerStyle where Self == WheelPickerStyle {
    // doc: SwiftUI/PickerStyle/wheel
    public static var wheel: WheelPickerStyle { fatalError() }
}
