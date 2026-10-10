import Foundation
public struct AVMediaType: Hashable { public var rawValue: String; public static let video = AVMediaType(rawValue: "vide") }
public enum AVAuthorizationStatus: Int { case notDetermined, restricted, denied, authorized }
open class AVCaptureDevice {
    public class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus { .notDetermined }
    public class func requestAccess(for mediaType: AVMediaType) async -> Bool { true }
}
