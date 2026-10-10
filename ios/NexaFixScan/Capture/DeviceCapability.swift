import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(RoomPlan)
import RoomPlan
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Whether this device can scan right now, and if not, why.
///
/// Scanning needs two things: a LiDAR sensor (`RoomCaptureSession.isSupported`) and permission to use
/// the camera. The first half of this file is plain Swift on Foundation, so the decision and the words
/// are checked on Linux; the second half reads the real system state.
enum DeviceCapability: Equatable {
    /// LiDAR is present and the camera is allowed.
    case supported
    /// No LiDAR sensor: scanning is not possible on this device.
    case noLiDAR
    /// The person said no to the camera.
    case cameraDenied
    /// Screen Time or a device profile blocks the camera.
    case cameraRestricted
    /// The system camera prompt has not been shown yet.
    case notDetermined

    /// Camera permission without the AVFoundation type.
    enum CameraAccess: Equatable {
        case authorized, notDetermined, denied, restricted
    }

    /// The decision: no LiDAR beats everything, because no permission can fix it.
    static func resolve(lidarSupported: Bool, camera: CameraAccess) -> DeviceCapability {
        guard lidarSupported else { return .noLiDAR }
        switch camera {
        case .authorized: return .supported
        case .notDetermined: return .notDetermined
        case .denied: return .cameraDenied
        case .restricted: return .cameraRestricted
        }
    }

    var canScan: Bool { self == .supported }

    /// Settings can fix it, so the screen offers a button that opens Settings.
    var canBeFixedInSettings: Bool { self == .cameraDenied }

    // MARK: Words

    var title: String {
        switch self {
        case .supported: return "Ready to scan"
        case .noLiDAR: return "This device can\u{2019}t scan rooms"
        case .cameraDenied: return "Camera access is off"
        case .cameraRestricted: return "The camera is restricted"
        case .notDetermined: return "Scanning uses the camera"
        }
    }

    var message: String {
        switch self {
        case .supported:
            return "Walk slowly along the walls of each room."
        case .noLiDAR:
            return "Scanning needs an iPhone Pro or iPad Pro with a LiDAR sensor. Everything else in NexaFix Scan still works: open saved properties, check dimensions and export."
        case .cameraDenied:
            return "NexaFix Scan needs the camera to measure rooms. Turn it on in Settings, then come back."
        case .cameraRestricted:
            return "Screen Time or a device profile is blocking the camera on this device. Ask whoever manages the device to allow it."
        case .notDetermined:
            return "The camera and the LiDAR sensor measure walls, doors and windows as you walk through each room."
        }
    }

    /// The reassurance shown with the camera request.
    static let privacyNote = "Scans stay on this device. Nothing leaves it unless you export."

    /// What RoomPlan needs to join the rooms of a floor into one 3D model: Apple recommends good lighting of 50 lux
    /// or more and a total area of at most about 186 m² (2,000 sq ft) (WWDC23 session 10192). A bigger floor
    /// can still be scanned: the plans are saved, the joined model may not be possible.
    static let sizeAndLightNote = "Switch the lights on and scan one floor at a time. RoomPlan can join about 186 m\u{00B2} (2,000 sq ft) into one 3D model; on a bigger floor the plans are still saved."
}

// MARK: - Reading the system

extension DeviceCapability {
    /// Whether this process is running in the iOS Simulator, which has no LiDAR and no real camera.
    static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()
}

#if canImport(AVFoundation) && canImport(RoomPlan)
extension DeviceCapability {
    /// The state right now. Cheap: it only reads two system flags.
    static var current: DeviceCapability {
        resolve(lidarSupported: RoomCaptureSession.isSupported, camera: cameraAccess)
    }

    static var cameraAccess: CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    /// Shows the system camera prompt (only the first time) and returns the state afterwards.
    /// Call it after `PermissionPrimer` has explained why.
    static func requestCameraAccess() async -> DeviceCapability {
        if RoomCaptureSession.isSupported, cameraAccess == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        return current
    }
}
#endif

#if canImport(UIKit)
extension DeviceCapability {
    /// Opens this app's page in the Settings app, where the camera switch is.
    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
