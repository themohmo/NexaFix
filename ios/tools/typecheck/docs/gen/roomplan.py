from mk import *
H = '''// SHIM of Apple's RoomPlan (everything NexaFix Scan touches). Declarations are copied from Apple's documentation
// (RoomPlan pages, iOS column); each carries a `// doc:` tag that docs/verify_shims.py re-checks. Bodies are
// `fatalError()`: this is for type checking only and is never run.
//
// CapturedRoom and its parts are Swift structs with get-only properties and no public memberwise initialiser,
// exactly as documented, so nothing in the app can build one by hand (the Simulator path uses Core's fixtures).
@_exported import Foundation
@_exported import simd
import UIKit
import ARKit

'''
B = []
def add(s): B.append(s)
def cases(paths, indent='        '):
    lines = [l.strip() for l in emit_members(paths, indent='').split('\n') if l.strip()]
    add('\n'.join(indent + l for l in lines))

# ---- session
add('''// doc: RoomPlan/RoomCaptureSession
public class RoomCaptureSession {''')
add(emit_members(['roomplan/roomcapturesession/init(arsession:)','roomplan/roomcapturesession/init()','roomplan/roomcapturesession/issupported','roomplan/roomcapturesession/run(configuration:)','roomplan/roomcapturesession/stop()','roomplan/roomcapturesession/stop(pausearsession:)','roomplan/roomcapturesession/delegate','roomplan/roomcapturesession/arsession']))
add('}')
add('''extension RoomCaptureSession {
    // doc: RoomPlan/RoomCaptureSession/Configuration
    public struct Configuration {''')
add(emit_members(['roomplan/roomcapturesession/configuration/init()'], indent='        ').replace('{ fatalError() }','{ isCoachingEnabled = true }'))
add(emit_members(['roomplan/roomcapturesession/configuration/iscoachingenabled'], indent='        ').replace(' { get { fatalError() } set { } }',' = true'))

add('''    }
    // doc: RoomPlan/RoomCaptureSession/CaptureError
    public enum CaptureError: Error, Hashable, LocalizedError, Sendable {''')
cases([f'roomplan/roomcapturesession/captureerror/{n}' for n in ['devicenotsupported','devicetoohot','exceedscenesizelimit','invalidarconfiguration','worldtrackingfailure','internalerror']])
add(emit_members(['roomplan/roomcapturesession/captureerror/errordescription'], indent='        '))
add('''    }
    // doc: RoomPlan/RoomCaptureSession/Instruction
    public enum Instruction: Hashable {''')
cases([f'roomplan/roomcapturesession/instruction/{n}' for n in ['normal','movecloseto wall'.replace(' ',''),'moveawayfromwall','turnonlight','slowdown','lowtexture']])
add('    }\n}')
add('''
// doc: RoomPlan/RoomCaptureSessionDelegate
public protocol RoomCaptureSessionDelegate: AnyObject {''')
add(emit_members(['roomplan/roomcapturesessiondelegate/capturesession(_:didstartwith:)','roomplan/roomcapturesessiondelegate/capturesession(_:didadd:)','roomplan/roomcapturesessiondelegate/capturesession(_:didremove:)','roomplan/roomcapturesessiondelegate/capturesession(_:didchange:)','roomplan/roomcapturesessiondelegate/capturesession(_:didupdate:)','roomplan/roomcapturesessiondelegate/capturesession(_:didprovide:)','roomplan/roomcapturesessiondelegate/capturesession(_:didendwith:error:)'], 'protocol'))
add('}\nextension RoomCaptureSessionDelegate {')
add(emit_members(['roomplan/roomcapturesessiondelegate/capturesession(_:didstartwith:)-3c74n','roomplan/roomcapturesessiondelegate/capturesession(_:didupdate:)-77zyg','roomplan/roomcapturesessiondelegate/capturesession(_:didremove:)-9gs76','roomplan/roomcapturesessiondelegate/capturesession(_:didchange:)-gv3t','roomplan/roomcapturesessiondelegate/capturesession(_:didprovide:)-5hvhl','roomplan/roomcapturesessiondelegate/capturesession(_:didendwith:error:)-5f0mc']).replace('{ fatalError() }','{ }'))
add('}')

# ---- view
add('''
// doc: RoomPlan/RoomCaptureView
@MainActor @objc @preconcurrency public class RoomCaptureView: UIView {''')
add(emit_members(['roomplan/roomcaptureview/init(frame:arsession:)','roomplan/roomcaptureview/init(frame:)','roomplan/roomcaptureview/init(coder:)','roomplan/roomcaptureview/capturesession','roomplan/roomcaptureview/delegate','roomplan/roomcaptureview/ismodelenabled']))
add('''}
// doc: RoomPlan/RoomCaptureViewDelegate
public protocol RoomCaptureViewDelegate: NSCoding {''')
add(emit_members(['roomplan/roomcaptureviewdelegate/captureview(shouldpresent:error:)','roomplan/roomcaptureviewdelegate/captureview(didpresent:error:)'],'protocol'))
add('}\nextension RoomCaptureViewDelegate {')
add(emit_members(['roomplan/roomcaptureviewdelegate/captureview(shouldpresent:error:)-5l74q','roomplan/roomcaptureviewdelegate/captureview(didpresent:error:)-6em1r']).replace('-> Bool { fatalError() }','-> Bool { true }').replace('{ fatalError() }','{ }'))
add('}')

# ---- builders
add('''
// doc: RoomPlan/RoomBuilder
public class RoomBuilder {''')
add(emit_members(['roomplan/roombuilder/init(options:)','roomplan/roombuilder/capturedroom(from:)']))
add('''}
extension RoomBuilder {
    // doc: RoomPlan/RoomBuilder/ConfigurationOptions
    public struct ConfigurationOptions: OptionSet {
        // shim: OptionSet storage''')
add('        public let rawValue: Int')
add(emit_members(['roomplan/roombuilder/configurationoptions/init(rawvalue:)'], indent='        ').replace('{ fatalError() }','{ self.rawValue = rawValue }'))
add(emit_members(['roomplan/roombuilder/configurationoptions/beautifyobjects'], indent='        ').replace('{ fatalError() }','{ ConfigurationOptions(rawValue: 1) }'))
add('''    }
    // doc: RoomPlan/RoomBuilder/BuildError
    public enum BuildError: Error, Hashable, LocalizedError, Sendable {''')
cases([f'roomplan/roombuilder/builderror/{n}' for n in ['insufficientinput','invalidinput','exceedscenesizelimit','internalerror','devicenotsupported']])
add(emit_members(['roomplan/roombuilder/builderror/errordescription'], indent='        '))
add('    }\n}')
add('''
// doc: RoomPlan/StructureBuilder
public class StructureBuilder {''')
add(emit_members(['roomplan/structurebuilder/init(options:)','roomplan/structurebuilder/configurationoptions','roomplan/structurebuilder/capturedstructure(from:)']))
add('''}
extension StructureBuilder {
    // doc: RoomPlan/StructureBuilder/BuildError
    public enum BuildError: Error, Hashable, LocalizedError, Sendable {''')
cases([f'roomplan/structurebuilder/builderror/{n}' for n in ['devicenotsupported','exceedscenesizelimit','insufficientinput','internalerror','invalidinput','invalidroomlocation']])
add(emit_members(['roomplan/structurebuilder/builderror/errordescription'], indent='        '))
add('    }\n}')

# ---- captured data
add('''
// doc: RoomPlan/CapturedRoomData
public struct CapturedRoomData: Codable, Sendable {''')
add(emit_members(['roomplan/capturedroomdata/init(from:)','roomplan/capturedroomdata/encode(to:)']))
add('}')
add('''
// doc: RoomPlan/CapturedRoom
public struct CapturedRoom: Codable, Sendable {''')
add(emit_members(['roomplan/capturedroom/init(from:)','roomplan/capturedroom/identifier','roomplan/capturedroom/story','roomplan/capturedroom/floors','roomplan/capturedroom/doors','roomplan/capturedroom/objects','roomplan/capturedroom/openings','roomplan/capturedroom/walls','roomplan/capturedroom/windows','roomplan/capturedroom/version','roomplan/capturedroom/encode(to:)','roomplan/capturedroom/export(to:exportoptions:)','roomplan/capturedroom/export(to:metadataurl:modelprovider:exportoptions:)']))
add('''}
extension CapturedRoom {
    // doc: RoomPlan/CapturedRoom/Confidence
    public enum Confidence: Hashable, Sendable {''')
cases([f'roomplan/capturedroom/confidence/{n}' for n in ['high','medium','low']])
add('''    }
    // doc: RoomPlan/CapturedRoom/Surface
    public struct Surface: Codable, Sendable {''')
add(emit_members([f'roomplan/capturedroom/surface/{n}' for n in ['init(from:)','identifier','parentidentifier','category-swift.property','confidence','transform','dimensions','story','completededges','curve-swift.property','polygoncorners','encode(to:)']], indent='        '))
add('''        // doc: RoomPlan/CapturedRoom/Surface/Category-swift.enum
        public enum Category: Codable, Equatable, Hashable, Sendable {''')
cases([f'roomplan/capturedroom/surface/category-swift.enum/{n}' for n in ['floor','door(isopen:)','opening','wall','window']], '            ')
add('''        }
        // doc: RoomPlan/CapturedRoom/Surface/Edge
        public enum Edge: CaseIterable, Codable, Hashable, Sendable {''')
cases([f'roomplan/capturedroom/surface/edge/{n}' for n in ['top','bottom','left','right']], '            ')
add('''        }
        // doc: RoomPlan/CapturedRoom/Surface/Curve-swift.struct
        public struct Curve: Codable, Sendable {''')
add(emit_members([f'roomplan/capturedroom/surface/curve-swift.struct/{n}' for n in ['startangle','endangle','radius','center']], indent='            '))
add('''        }
    }
    // doc: RoomPlan/CapturedRoom/Object
    public struct Object: Codable, Sendable {''')
add(emit_members([f'roomplan/capturedroom/object/{n}' for n in ['init(from:)','identifier','parentidentifier','category-swift.property','confidence','transform','dimensions','story','encode(to:)']], indent='        '))
add('''        // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum
        public enum Category: CaseIterable, Codable, Hashable, Sendable {''')
cases([f'roomplan/capturedroom/object/category-swift.enum/{n}' for n in ['bathtub','bed','chair','dishwasher','fireplace','oven','refrigerator','sink','sofa','stairs','storage','stove','table','television','toilet','washerdryer']], '            ')
add('''        }
    }
    // doc: RoomPlan/CapturedRoom/USDExportOptions
    public struct USDExportOptions: OptionSet {''')
add(emit_members(['roomplan/capturedroom/usdexportoptions/init(rawvalue:)'], indent='        ').replace('{ fatalError() }','{ self.rawValue = rawValue }'))
add(emit_members(['roomplan/capturedroom/usdexportoptions/rawvalue'], indent='        ').replace('public var rawValue: Int32 { fatalError() }','public let rawValue: Int32'))
add(emit_members([f'roomplan/capturedroom/usdexportoptions/{n}' for n in ['parametric','mesh','model']], indent='        ').replace('{ fatalError() }','{ USDExportOptions(rawValue: 0) }'))
add('''    }
    // doc: RoomPlan/CapturedRoom/ModelProvider
    public struct ModelProvider {''')
add(emit_members(['roomplan/capturedroom/modelprovider/init()'], indent='        ').replace('{ fatalError() }','{ }'))
add('''    }
    // doc: RoomPlan/CapturedRoom/Error
    public enum Error: Swift.Error, LocalizedError, Sendable {''')
cases([f'roomplan/capturedroom/error/{n}' for n in ['devicenotsupported','urlinvalidfileextension','urlinvalidfilepath','urlinvalidscheme','urlmissingfileextension']])
add(emit_members(['roomplan/capturedroom/error/errordescription'], indent='        '))
add('    }\n}')
add('''
// doc: RoomPlan/CapturedStructure
public struct CapturedStructure: Codable, Sendable {''')
add(emit_members([f'roomplan/capturedstructure/{n}' for n in ['init(from:)','identifier','rooms','floors','doors','objects','openings','walls','windows','sections','version','encode(to:)','export(to:metadataurl:modelprovider:exportoptions:)','usdexportoptions','modelprovider','error','surface','object','section']]))
add('}')
add('''extension CapturedRoom {
    // doc: RoomPlan/CapturedRoom/Section
    public struct Section: Codable, Sendable {''')
add(emit_members([f'roomplan/capturedroom/section/{n}' for n in ['init(from:)','label-swift.property','story','center','encode(to:)']], indent='        '))
add('''        // doc: RoomPlan/CapturedRoom/Section/Label-swift.enum
        public enum Label: String, Codable, Hashable, Sendable {''')
cases([f'roomplan/capturedroom/section/label-swift.enum/{n}' for n in ['livingroom','kitchen','diningroom','bedroom','bathroom','unidentified']], '            ')
add('        }\n    }\n}')
s = H + '\n'.join(B) + '\n'
s = finalize(s)
open(SHIMS + 'RoomPlan/RoomPlan.swift','w').write(s)
