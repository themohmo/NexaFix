// SHIM of the part of Apple's AVFoundation the app touches (camera permission). Declarations copied from the docs.
@_exported import Foundation

// doc: AVFoundation/AVMediaType
public struct AVMediaType: Hashable, RawRepresentable, Sendable {
    // shim: RawRepresentable storage
    public let rawValue: String
    // doc: AVFoundation/AVMediaType/init(rawValue:)
    public init(rawValue: String) { self.rawValue = rawValue }
    // doc: AVFoundation/AVMediaType/video
    public static var video: AVMediaType { AVMediaType(rawValue: "") }
    // doc: AVFoundation/AVMediaType/audio
    public static var audio: AVMediaType { AVMediaType(rawValue: "") }
}

// doc: AVFoundation/AVAuthorizationStatus
public enum AVAuthorizationStatus: Int, Sendable {
    // doc: AVFoundation/AVAuthorizationStatus/notDetermined
    case notDetermined
    // doc: AVFoundation/AVAuthorizationStatus/restricted
    case restricted
    // doc: AVFoundation/AVAuthorizationStatus/denied
    case denied
    // doc: AVFoundation/AVAuthorizationStatus/authorized
    case authorized
}

// doc: AVFoundation/AVCaptureDevice
@objc public class AVCaptureDevice: NSObject {
    // doc: AVFoundation/AVCaptureDevice/authorizationStatus(for:)
    public class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus { fatalError() }
    // doc: AVFoundation/AVCaptureDevice/requestAccess(for:completionHandler:)#0
    public class func requestAccess(for mediaType: AVMediaType, completionHandler handler: @escaping @Sendable (Bool) -> Void) { fatalError() }
    // doc: AVFoundation/AVCaptureDevice/requestAccess(for:completionHandler:)#1
    public class func requestAccess(for mediaType: AVMediaType) async -> Bool { fatalError() }
}
