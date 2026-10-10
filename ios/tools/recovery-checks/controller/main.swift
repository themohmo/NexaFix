import Foundation
import simd
import ARKit
import RoomPlan
import NexaFixCore

setvbuf(stdout, nil, _IONBF, 0)
// Regression checks for ScanSessionController (the scan screen's state machine) against stub Apple modules:
// what it writes to the safety copy and when (ScanRecoveryStore), how a scan ends, and the error and timeout paths.
// controller/run.sh builds it; see ../README.md.
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0
func check(_ ok: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !ok() { failures += 1; print("FAIL line \(line): \(message)") }
}

@MainActor func until(_ timeout: Double = 3, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if cond() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return cond()
}

@MainActor func expect(_ message: String, timeout: Double = 3, line: Int = #line, _ cond: () -> Bool) async {
    let ok = await until(timeout, cond)
    check(ok, message, line: line)
}

@MainActor func feed(_ c: ScanSessionController, _ room: CapturedRoom, walls: Int = 4) async {
    let session = c.captureView!.captureSession!
    session.delegate?.captureSession(session, didUpdate: room)
    await expect("live update lands") { c.stats.walls == walls }
}

let harnessPropertyID = UUID()
// MARK: Fixtures

func yaw(_ radians: Float, _ t: simd_float3) -> simd_float4x4 {
    let c = cos(radians), s = sin(radians)
    return simd_float4x4(simd_float4(c, 0, -s, 0), simd_float4(0, 1, 0, 0), simd_float4(s, 0, c, 0), simd_float4(t.x, t.y, t.z, 1))
}

func rectRoom(width w: Float, depth d: Float, doors: Int = 1, windows: Int = 1, story: Int = 0) -> CapturedRoom {
    func wall(_ cx: Float, _ cz: Float, _ len: Float, _ rot: Float) -> CapturedRoom.Surface {
        CapturedRoom.Surface(category: .wall, transform: yaw(rot, simd_float3(cx, 1.35, cz)), dimensions: simd_float3(len, 2.7, 0), story: story)
    }
    var room = CapturedRoom(story: story, floors: [
        CapturedRoom.Surface(category: .floor, transform: yaw(0, simd_float3(w / 2, 0, -d / 2)), dimensions: simd_float3(w, d, 0),
                             polygonCorners: [simd_float3(-w / 2, -d / 2, 0), simd_float3(w / 2, -d / 2, 0), simd_float3(w / 2, d / 2, 0), simd_float3(-w / 2, d / 2, 0)])
    ], walls: [
        wall(w / 2, 0, w, 0), wall(w, -d / 2, d, .pi / 2), wall(w / 2, -d, w, 0), wall(0, -d / 2, d, .pi / 2),
    ])
    room.doors = (0..<doors).map { _ in CapturedRoom.Surface(category: .door(isOpen: false), transform: yaw(0, .zero), dimensions: simd_float3(0.9, 2.1, 0)) }
    room.windows = (0..<windows).map { _ in CapturedRoom.Surface(category: .window, transform: yaw(0, .zero), dimensions: simd_float3(1.2, 1.2, 0)) }
    return room
}

@MainActor final class Probe {
    var finished: [ScanResult] = []
    var cancelled = 0
}

nonisolated(unsafe) var recoveryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("capfix-recovery-\(UUID().uuidString)")
@MainActor func makeController(simulated: Bool, existing: [String] = [], probe: Probe) -> ScanSessionController {
    ScanSessionController(configuration: ScanConfiguration(propertyName: "Marina 1204", propertyID: harnessPropertyID, existingRoomNames: existing, units: .default, hapticsEnabled: true, story: 1),
                          isSimulated: simulated,
                          recoveryRoot: recoveryRoot,
                          onFinish: { probe.finished.append($0) },
                          onCancel: { probe.cancelled += 1 })
}

// MARK: Tests

@MainActor func testMapper() {
    var c0 = simd_float4(1, 2, 3, 0)
    let m = simd_float4x4(c0, simd_float4(4, 5, 6, 0), simd_float4(7, 8, 9, 0), simd_float4(10, 11, 12, 1))
    c0.w = 0
    let mapped = CapturedRoomMapper.matrix(m)
    check(mapped.columnMajor == [1, 2, 3, 0, 4, 5, 6, 0, 7, 8, 9, 0, 10, 11, 12, 1], "matrix column order \(mapped.columnMajor)")
    check(mapped.translation == Point3(10, 11, 12) && mapped.xAxis == Point3(1, 2, 3) && mapped.yAxis == Point3(4, 5, 6) && mapped.zAxis == Point3(7, 8, 9), "matrix axes")
    check(mapped.transform(Point3(1, 0, 0)) == Point3(11, 13, 15), "transform of local x applies column 0 then translation")

    // every Apple object category lands on a Core ObjectKind with the same name
    for category in CapturedRoom.Object.Category.allCases {
        let name = CapturedRoomMapper.categoryName(category)
        check(ObjectKind(rawValue: name) != nil && ObjectKind(rawValue: name) != .other, "category \(category) -> \(name)")
    }
    check(Set(CapturedRoom.Object.Category.allCases.map(CapturedRoomMapper.categoryName)).count == 16, "16 distinct names")
    check(Set(CapturedRoom.Object.Category.allCases.map(CapturedRoomMapper.categoryName)) == Set(ObjectKind.allCases.map(\.rawValue)).subtracting(["other"]), "Core ObjectKind covers exactly Apple's categories")

    let wallID = UUID(), doorID = UUID()
    var room = rectRoom(width: 4, depth: 3, doors: 0, windows: 0, story: 0)
    room.walls[0].identifier = wallID
    room.walls[1].curve = CapturedRoom.Surface.Curve(startAngle: 0, endAngle: 1, radius: 2, center: simd_float2(0, 0))
    room.walls[2].confidence = .low
    room.walls[3].confidence = .medium
    room.doors = [CapturedRoom.Surface(identifier: doorID, parentIdentifier: wallID, category: .door(isOpen: true), transform: yaw(0, simd_float3(1, 1, 0)), dimensions: simd_float3(0.9, 2.1, 0.1))]
    room.objects = [CapturedRoom.Object(category: .washerDryer, transform: yaw(0, simd_float3(1, 0.4, -1)), dimensions: simd_float3(0.6, 0.85, 0.6))]
    let raw = CapturedRoomMapper.rawCapture(from: room, story: 2)
    check(raw.id == room.identifier && raw.story == 2, "id and story override")
    check(raw.walls.count == 4 && raw.doors.count == 1 && raw.floors.count == 1 && raw.objects.count == 1, "lists")
    check(raw.walls.allSatisfy { $0.kind == .wall && $0.story == 2 }, "wall kind and story")
    check(raw.walls[0].id == wallID && raw.doors[0].parentID == wallID && raw.doors[0].id == doorID, "ids and parent")
    check(raw.doors[0].kind == .door && raw.doors[0].dimensions == Point3(Double(Float(0.9)), Double(Float(2.1)), Double(Float(0.1))), "door kind and dims")
    check(raw.walls[1].isCurved && !raw.walls[0].isCurved, "curve -> isCurved")
    check(raw.walls[2].confidence == .low && raw.walls[3].confidence == .medium && raw.walls[0].confidence == .high, "confidence")
    check(raw.walls[0].polygonCorners == nil, "no polygon -> nil")
    check(raw.floors[0].polygonCorners?.count == 4 && raw.floors[0].kind == .floor, "floor polygon copied")
    check(raw.objects[0].category == "washerDryer", "object category")
    check(CapturedRoomMapper.rawCapture(from: room).story == 0, "story defaults to RoomPlan's")
    let stats = LiveScanStats(capture: raw)
    check(stats.walls == 4 && abs((stats.roughFloorAreaM2 ?? 0) - 12) < 1e-4, "stats from mapped floor polygon \(String(describing: stats.roughFloorAreaM2))")
    // kind(of:) is the category mapping
    check(CapturedRoomMapper.kind(of: .door(isOpen: false)) == .door && CapturedRoomMapper.kind(of: .door(isOpen: true)) == .door, "door kinds")
    check(CapturedRoomMapper.kind(of: .opening) == .opening && CapturedRoomMapper.kind(of: .window) == .window && CapturedRoomMapper.kind(of: .floor) == .floor, "other kinds")
    // the mapped capture goes through Core without trouble
    let built = RoomReconstructor.build(from: raw, name: "X", kind: .other)
    check(built.room.walls.count == 4, "stub core builds a 4-wall room from the mapped capture")
}

func testCapability() {
    for lidar in [true, false] {
        for access in [DeviceCapability.CameraAccess.authorized, .notDetermined, .denied, .restricted] {
            let r = DeviceCapability.resolve(lidarSupported: lidar, camera: access)
            if !lidar { check(r == .noLiDAR, "no lidar beats \(access)") }
            else {
                switch access {
                case .authorized: check(r == .supported, "supported")
                case .notDetermined: check(r == .notDetermined, "notDetermined")
                case .denied: check(r == .cameraDenied, "denied")
                case .restricted: check(r == .cameraRestricted, "restricted")
                }
            }
        }
    }
    check(DeviceCapability.supported.canScan && !DeviceCapability.noLiDAR.canScan, "canScan")
    check(DeviceCapability.cameraDenied.canBeFixedInSettings && !DeviceCapability.cameraRestricted.canBeFixedInSettings, "settings")
    for c in [DeviceCapability.supported, .noLiDAR, .cameraDenied, .cameraRestricted, .notDetermined] {
        check(!c.title.isEmpty && c.message.hasSuffix("."), "words for \(c)")
    }
    check(DeviceCapability.noLiDAR.message.contains("iPhone Pro") && DeviceCapability.noLiDAR.message.contains("Everything else"), "no-LiDAR explanation")
}

@MainActor func testSimulatedFlow() async {
    let probe = Probe()
    let c = makeController(simulated: true, existing: ["Hall"], probe: probe)
    check(c.captureView == nil, "no capture view in the Simulator")
    c.start()
    check(c.flow.state == .scanning(roomIndex: 0) && c.canFinishRoom, "scanning in the simulator")
    c.finishRoom()
    await expect("first simulated room is built") { c.flow.draftAwaitingName != nil }
    let draft = c.flow.draftAwaitingName
    check(draft?.wallCount == 4 && draft?.doorCount == 1 && draft?.windowCount == 2, "draft counts \(String(describing: draft))")
    check((draft?.floorAreaM2 ?? 0) > 20, "floor area from the fixture \(String(describing: draft?.floorAreaM2))")
    check(c.nameRoom("  ", kind: .other, then: .scanNextRoom) == .empty && c.flow.draftAwaitingName != nil, "empty name refused")
    check(!c.nameRoom("hall", kind: .other, then: .scanNextRoom).isValid, "existing property name refused")
    check(c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom).isValid, "named")
    check(c.flow.state == .scanning(roomIndex: 1), "next room scanning \(c.flow.state)")
    check(c.stats == .empty && c.liveScene.isEmpty, "live data cleared for the new room")

    // cancel the second room: first stays
    c.cancelCurrentRoom()
    check(c.flow.state == .betweenRooms && c.flow.rooms.count == 1, "cancel keeps the first room")
    c.scanNextRoom()
    c.finishRoom()
    await expect("second room built") { c.flow.draftAwaitingName != nil }
    check(c.flow.draftAwaitingName?.id != draft?.id, "new draft")
    check(c.nameRoom("Kitchen", kind: .kitchen, then: .finishProperty).isValid, "second room named, finishing")
    await expect("result delivered") { probe.finished.count == 1 }
    let r = probe.finished.first
    check(r?.rooms.map(\.name) == ["Living Room", "Kitchen"], "rooms in order \(String(describing: r?.rooms.map(\.name)))")
    check(r?.rooms.map(\.kind) == [.livingRoom, .kitchen], "kinds")
    check(r?.structureUSDZ == nil && r?.worldMapData == nil && r?.capturedRoomJSON.isEmpty == true, "no real assets in the simulator")
    check(r?.warnings.first?.contains("practice scan") == true, "practice warning \(String(describing: r?.warnings))")
    check(r?.story == 1, "story")
    check(c.flow.state == .finished, "flow finished")
    check(c.arSession.pauseCount >= 1, "AR session paused after delivery")
    c.leave()
    check(probe.cancelled == 1, "leave after finish still reports a cancel once")
    c.leave()
    check(probe.cancelled == 1, "leave twice cancels once")
}

@MainActor func realSession(_ c: ScanSessionController) -> RoomCaptureSession { c.captureView!.captureSession }

@MainActor func testRealFlow() async {
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 5, depth: 4)), .success(rectRoom(width: 3, depth: 3, doors: 2, windows: 0)), .success(rectRoom(width: 2, depth: 6))]
    RoomPlan.RoomBuilder.seenSerials = []
    StructureBuilder.failWith = nil
    let c = makeController(simulated: false, probe: probe)
    let session = realSession(c)
    check(c.captureView?.isModelEnabled == false, "framework live miniature turned off")
    check(session.delegate != nil && c.arSession.delegate != nil && c.captureView?.delegate != nil, "delegates wired")
    check(c.tracking == .initializing, "initial tracking")
    c.start()
    c.arSession.currentFrame = ARFrame()
    check(session.runConfigurations.count == 1 && session.runConfigurations[0].isCoachingEnabled, "run once with coaching")
    check(c.canFinishRoom == false, "cannot finish an empty scan")

    // live updates
    session.delegate?.captureSession(session, didProvide: .turnOnLight)
    await expect("instruction kept for VoiceOver") { c.instruction == .turnOnLight }
    check(c.coach.text != "Turn on a light" && c.coach.text.hasPrefix("Point at a wall"), "the pill does not repeat RoomPlan's own text: \(c.coach.text)")
    await feed(c, rectRoom(width: 5, depth: 4))
    check(c.canFinishRoom, "can finish after four walls")
    check(c.statsSummary.hasPrefix("4 walls") && c.statsSummary.contains("about 20.0"), "summary \(c.statsSummary)")
    await expect("live scene built off the main thread") { !c.liveScene.isEmpty }
    check(c.liveScene.labels.contains { $0.kind == .wallLength }, "wall labels in the live scene")
    session.delegate?.captureSession(session, didProvide: .normal)
    await expect("tracking normal once a frame exists", timeout: 2) { c.tracking == .none }
    await expect("progress hint once instruction is normal") { c.coach.text.contains("Go all the way round") }

    // finish room 1: stop keeps AR; both end callbacks arrive; only one build happens
    c.finishRoom()
    check(session.stopCalls == [false], "stop(pauseARSession: false) \(session.stopCalls)")
    await expect("room processed") { c.flow.draftAwaitingName != nil }
    check(RoomPlan.RoomBuilder.seenSerials == [1], "exactly one capturedRoom(from:) call \(RoomPlan.RoomBuilder.seenSerials)")
    check(c.flow.draftAwaitingName?.wallCount == 4, "draft stats")
    check(c.liveScene.isEmpty, "live scene cleared")
    check(Haptics.log.contains("impact"), "finish haptic")
    check(c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom).isValid, "named")
    check(session.runConfigurations.count == 2, "run again for room 2")
    check(c.arSession.pauseCount == 0, "AR session was not paused between rooms")

    // room 2: end delivered after the build effect starts waiting
    session.deliverEndAsynchronously = true
    await feed(c, rectRoom(width: 3, depth: 3, doors: 2, windows: 0))
    c.finishRoom()
    await expect("room 2 processed with late end callback") { c.flow.draftAwaitingName != nil }
    check(c.flow.draftAwaitingName?.doorCount == 2, "room 2 draft")
    check(c.nameRoom("Bedroom", kind: .bedroom, then: .scanNextRoom).isValid, "named")

    // room 3: the late second end callback of room 2 must not be used for it
    await feed(c, rectRoom(width: 2, depth: 6))
    c.finishRoom()
    await expect("room 3 processed") { c.flow.draftAwaitingName != nil }
    check(RoomPlan.RoomBuilder.seenSerials == [1, 2, 3], "every capture built exactly once, in order: \(RoomPlan.RoomBuilder.seenSerials)")
    check(c.nameRoom("Study", kind: .other, then: .finishProperty).isValid, "named and finishing")
    check(c.flow.state == .merging, "merging \(c.flow.state)")
    await expect("result delivered") { probe.finished.count == 1 }
    guard let r = probe.finished.first else { return }
    check(r.rooms.count == 3 && r.rooms.map(\.name) == ["Living Room", "Bedroom", "Study"], "rooms")
    check(r.capturedRoomJSON.count == 3 && r.rooms.allSatisfy { r.capturedRoomJSON[$0.id] != nil }, "JSON keyed by room id")
    if let first = r.rooms.first, let data = r.capturedRoomJSON[first.id], let decoded = try? JSONDecoder().decode(CapturedRoom.self, from: data) {
        check(decoded.walls.count == 4, "JSON decodes back to a CapturedRoom")
    } else { check(false, "JSON decodes") }
    check(String(data: r.structureUSDZ ?? Data(), encoding: .utf8) == "structure-usdz:3", "structure exported from all rooms")
    check((r.worldMapData?.count ?? 0) > 0, "world map archived")
    check(r.warnings.allSatisfy { $0.contains("overhung the end of its wall") }, "clean scan has no warnings (fixture door overhang aside): \(r.warnings)")
    check(!r.warnings.contains { $0.contains("AR") }, "no AR warning on a clean scan \(r.warnings)")
    check(c.arSession.pauseCount >= 1 && c.arSession.delegate == nil && session.delegate == nil, "released after delivery")
    check(Haptics.log.contains("success"), "success haptic")
}

@MainActor func testRealErrorsAndInterruptions() async {
    let probe = Probe()
    Haptics.log = []
    RoomPlan.RoomBuilder.nextResults = []
    let c = makeController(simulated: false, probe: probe)
    let session = realSession(c)
    c.start()
    await feed(c, rectRoom(width: 4, depth: 3))

    // not enough scanned: the builder refuses
    RoomPlan.RoomBuilder.nextResults = [.failure(RoomPlan.RoomBuilder.BuildError.insufficientInput)]
    c.finishRoom()
    await expect("alert for insufficient input") { c.alert != nil }
    check(c.alert?.title == "Not enough was scanned" && c.alert?.offersRescan == true, "alert wording \(String(describing: c.alert))")
    check(c.flow.state == .idle, "back to idle with no rooms \(c.flow.state)")
    check(c.arSession.pauseCount >= 1, "AR paused when the first room fails")
    check(Haptics.log.contains("warning"), "warning haptic")
    c.scanAgain()
    check(c.alert == nil && c.flow.state == .scanning(roomIndex: 0) && session.runConfigurations.count == 2, "scan again restarts")

    // partial room after overheating: kept, with a note
    session.endError = RoomCaptureSession.CaptureError.deviceTooHot
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3))]
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    await expect("overheated room still offered") { c.flow.draftAwaitingName != nil }
    check(c.flow.draftAwaitingName?.warnings.contains { $0.contains("too hot") } == true, "partial note \(String(describing: c.flow.draftAwaitingName?.warnings))")
    session.endError = nil
    check(c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom).isValid, "named")

    // a tracking failure ends only the current room
    session.endError = RoomCaptureSession.CaptureError.worldTrackingFailure
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    await expect("tracking failure alert") { c.alert != nil }
    check(c.flow.state == .betweenRooms && c.flow.rooms.count == 1, "earlier room kept \(c.flow.state)")
    check(c.alert?.offersRescan == false && c.alert?.message.contains("Your finished rooms are safe.") == true, "reassurance \(String(describing: c.alert?.message))")
    c.alert = nil
    session.endError = nil

    // a stale second end callback right after our own stop is not an unexpected end
    c.scanNextRoom()
    check(c.flow.isCapturing, "scanning room 2")
    c.cancelCurrentRoom()
    check(c.flow.state == .betweenRooms, "cancelled room 2")
    c.scanNextRoom()
    session.delegate?.captureSession(session, didEndWith: CapturedRoomData(), error: nil)
    check(c.flow.isCapturing, "stale end callback ignored right after stop")

    // interruption and relocalisation
    c.arSession.delegate?.sessionWasInterrupted(c.arSession)
    await expect("interrupted") { c.tracking == .interrupted && c.coach.level == .critical && c.canShowLiveLabels == false }
    c.arSession.delegate?.sessionInterruptionEnded(c.arSession)
    let frame = ARFrame()
    frame.camera.trackingState = .limited(.relocalizing)
    c.arSession.currentFrame = frame
    await expect("relocalising read from the frame", timeout: 2) { c.tracking == .relocalizing }
    check(c.coach.text.hasPrefix("Tracking was lost"), "coach \(c.coach.text)")
    check(c.arSession.delegate?.sessionShouldAttemptRelocalization(c.arSession) == true, "relocalisation allowed")
    frame.camera.trackingState = .normal
    await expect("back to normal", timeout: 2) { c.tracking == .none }
    check(c.needsRelocalizationHelp == false, "no help banner after recovery")

    // merge that cannot join the rooms still returns every room
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 3, depth: 3))]
    StructureBuilder.failWith = StructureBuilder.BuildError.invalidRoomLocation
    c.cancelCurrentRoom()
    c.scanNextRoom()
    await feed(c, rectRoom(width: 3, depth: 3))
    c.finishRoom()
    await expect("room 2 built") { c.flow.draftAwaitingName != nil }
    check(c.nameRoom("Bedroom", kind: .bedroom, then: .finishProperty).isValid, "finishing")
    await expect("result delivered despite merge failure") { probe.finished.count == 1 }
    guard let r = probe.finished.first else { return }
    check(r.rooms.count == 2 && r.structureUSDZ == nil, "rooms kept, no model")
    check(r.warnings.contains { $0.contains("Tracking restarted") }, "tracking restart warning \(r.warnings)")
    check(r.warnings.contains { $0.contains("AR review is off for this level") }, "AR review off warning \(r.warnings)")
    check(r.warnings.filter { $0.contains("Tracking restarted") }.count == 1, "the restart is explained once \(r.warnings)")
    check(r.worldMapData == nil && !r.supportsARReview, "no world map when a room is in another space")
    check(c.arSession.worldMapRequests == 0, "no map was archived for it")
    StructureBuilder.failWith = nil
}

@MainActor func testMergeFailureKeepsRooms() async {
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3)), .success(rectRoom(width: 3, depth: 3))]
    StructureBuilder.failWith = StructureBuilder.BuildError.invalidRoomLocation
    let c = makeController(simulated: false, probe: probe)
    c.start()
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    await expect("room 1") { c.flow.draftAwaitingName != nil }
    _ = c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom)
    await feed(c, rectRoom(width: 3, depth: 3))
    c.finishRoom()
    await expect("room 2") { c.flow.draftAwaitingName != nil }
    _ = c.nameRoom("Bedroom", kind: .bedroom, then: .finishProperty)
    await expect("result delivered") { probe.finished.count == 1 }
    guard let r = probe.finished.first else { return }
    check(r.rooms.count == 2 && r.structureUSDZ == nil, "both rooms kept without a model")
    check(r.warnings.contains { $0.contains("don\u{2019}t line up") }, "merge warning \(r.warnings)")
    check(r.worldMapData != nil && r.capturedRoomJSON.count == 2, "map and JSON kept")
    StructureBuilder.failWith = nil
}

@MainActor func testRealUnexpectedEndAndLeave() async {
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3))]
    let c = makeController(simulated: false, probe: probe)
    let session = realSession(c)
    c.start()
    await feed(c, rectRoom(width: 4, depth: 3))
    // RoomPlan ends the session itself (for example an overheating device)
    session.delegate?.captureSession(session, didEndWith: CapturedRoomData(), error: nil)
    await expect("unexpected end is treated as finishing the room") { c.flow.draftAwaitingName != nil }
    check(c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom).isValid, "named")
    c.leave()
    check(probe.cancelled == 1 && probe.finished.isEmpty, "leave discards")
    check(session.delegate == nil && c.arSession.delegate == nil && c.captureView?.delegate == nil, "delegates released")
    check(c.arSession.pauseCount >= 1, "AR paused")
    check(c.flow.state == .idle && c.flow.rooms.isEmpty, "flow reset")
    // callbacks after teardown are harmless
    c.teardown()
    check(c.roomsAtRisk == 0, "nothing at risk after leaving")
}

@MainActor func testCancelWhileProcessingAndWatchdog() async {
    let probe = Probe()
    RoomPlan.RoomBuilder.seenSerials = []
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3)), .success(rectRoom(width: 4, depth: 3))]
    let c = makeController(simulated: false, probe: probe)
    let session = realSession(c)
    c.start()
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    await expect("room 1") { c.flow.draftAwaitingName != nil }
    _ = c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom)
    check(RoomPlan.RoomBuilder.seenSerials == [1], "room 1 built once")

    // cancel while the room is still being processed: the data that arrives later is thrown away
    session.deliverEndAsynchronously = true
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    check(c.flow.isProcessingRoom, "processing")
    c.cancelCurrentRoom()
    check(c.flow.state == .betweenRooms && c.flow.rooms.count == 1, "cancelled, earlier room kept")
    try? await Task.sleep(nanoseconds: 300_000_000)
    check(RoomPlan.RoomBuilder.seenSerials == [1], "late data from the cancelled room was not built \(RoomPlan.RoomBuilder.seenSerials)")
    check(c.alert == nil, "no alert for a deliberate cancel")

    // RoomPlan never reports the end: the person is told instead of waiting for ever
    ScanSessionController.endTimeout = 0.3
    session.deliverEndAsynchronously = false
    session.suppressEnd = true
    c.scanNextRoom()
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    check(c.flow.isProcessingRoom, "waiting for data")
    await expect("watchdog alert", timeout: 2) { c.alert?.title == "The scanner hit a problem" }
    check(c.flow.state == .betweenRooms && c.flow.rooms.count == 1, "back between rooms, earlier room kept \(c.flow.state)")
    ScanSessionController.endTimeout = 15
    c.leave()
}

@MainActor func testWatchdogAndWorldMapTimeoutAreBounded() async {
    // Nothing to assert beyond not hanging: a leave during merge returns.
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3))]
    let c = makeController(simulated: false, probe: probe)
    c.start()
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    await expect("built") { c.flow.draftAwaitingName != nil }
    _ = c.nameRoom("Living Room", kind: .livingRoom, then: .finishProperty)
    c.leave()
    try? await Task.sleep(nanoseconds: 300_000_000)
    check(probe.finished.isEmpty && probe.cancelled == 1, "leaving during the merge delivers nothing")
}

// MARK: Fixer tests

@MainActor func testARSessionRunsBeforeTheViewAndDelegateIsChained() async {
    RoomCaptureView.arSessionWasRunningWorldTrackingAtInit = []
    let probe = Probe()
    let c = makeController(simulated: false, probe: probe)
    let session = realSession(c)
    check(RoomCaptureView.arSessionWasRunningWorldTrackingAtInit == [true], "the AR session was running with a world-tracking configuration BEFORE RoomCaptureView(frame:arSession:) \(RoomCaptureView.arSessionWasRunningWorldTrackingAtInit)")
    check(c.arSession.runCalls.count == 1 && c.arSession.runCalls[0].options.isEmpty, "run once, no reset options")
    let cfg = c.arSession.runCalls.first?.configuration as? ARWorldTrackingConfiguration
    check(cfg != nil, "a world-tracking configuration")
    check(cfg?.sceneReconstruction == [] && cfg?.frameSemantics == [], "plain ARWorldTrackingConfiguration: no scene reconstruction, no scene depth (finding 1)")
    check(!c.hasStarted, "not started before the capture view has a window")

    // the delegate chain: bridge in front, RoomPlan's own delegate behind it
    guard let bridge = c.arSession.delegate as? ScanCaptureBridge else { return check(false, "bridge is the AR session delegate") }
    let own = session.ownARDelegate
    check(bridge.previous === own, "RoomPlan's own AR delegate is kept behind the bridge")
    bridge.session(c.arSession, didUpdate: ARFrame())
    bridge.session(c.arSession, didAdd: [ARAnchor()])
    bridge.session(c.arSession, didUpdate: [ARAnchor()])
    bridge.session(c.arSession, didRemove: [ARAnchor()])
    check(own.frames == 1 && own.anchorAdds == 1 && own.anchorUpdates == 1 && own.anchorRemoves == 1, "frames and anchors reach RoomPlan's delegate")
    check(bridge.sessionShouldAttemptRelocalization(c.arSession), "relocalisation allowed")

    c.start()
    check(c.hasStarted && session.runConfigurations.count == 1, "started")
    c.arSession.currentFrame = ARFrame()

    // lifecycle callbacks reach both
    bridge.sessionWasInterrupted(c.arSession)
    await expect("controller sees the interruption") { c.tracking == .interrupted }
    check(own.interruptions == 1, "RoomPlan's delegate sees the interruption")
    bridge.sessionInterruptionEnded(c.arSession)
    check(own.interruptionEnds == 1, "RoomPlan's delegate sees the end of the interruption")
    let cam = ARCamera()
    cam.trackingState = .limited(.relocalizing)
    bridge.session(c.arSession, cameraDidChangeTrackingState: cam)
    await expect("controller sees the camera tracking change at once") { c.tracking == .relocalizing }
    check(own.trackingChanges == 1, "RoomPlan's delegate sees the tracking change")
    cam.trackingState = .normal
    bridge.session(c.arSession, cameraDidChangeTrackingState: cam)
    await expect("and back to normal") { c.tracking == .none }

    // RoomPlan takes the delegate again when a capture starts (room 2): the bridge gets back in front
    session.takesARDelegateOnRun = true
    await feed(c, rectRoom(width: 4, depth: 3))
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3))]
    c.finishRoom()
    await expect("room built") { c.flow.draftAwaitingName != nil }
    _ = c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom)
    check(session.runConfigurations.count == 2, "second run")
    check(c.arSession.delegate === bridge && bridge.previous === own, "bridge claimed the delegate back after RoomPlan took it on run")
    check(c.arSession.runCalls.count == 1, "the controller never re-runs the AR session itself")

    // and if RoomPlan takes it later, the poll puts the bridge back
    session.takesARDelegateOnRun = false
    c.arSession.delegate = own
    await expect("the tracking poll re-claims the delegate", timeout: 2) { c.arSession.delegate === bridge }
    check(bridge.previous === own, "still chained")

    // a failure reaches both
    bridge.session(c.arSession, didFailWithError: ARError(.worldTrackingFailed))
    check(own.failures == 1, "RoomPlan's delegate sees the failure")
    await expect("alert for the tracking failure") { c.alert?.title == "Tracking failed" }

    c.leave()
    check(c.arSession.delegate == nil && bridge.previous == nil, "released")

    // a device without the LiDAR extras still gets a plain world-tracking configuration
    ARConfiguration.deviceHasLiDAR = false
    let plain = makeController(simulated: false, probe: probe)
    let plainCfg = plain.arSession.runCalls.first?.configuration as? ARWorldTrackingConfiguration
    check(plainCfg != nil && plainCfg?.sceneReconstruction == [] && plainCfg?.frameSemantics == [], "no unsupported features requested")
    plain.leave()
    ARConfiguration.deviceHasLiDAR = true

    // the Simulator never touches ARKit
    let sim = makeController(simulated: true, probe: probe)
    check(sim.arSession.runCalls.isEmpty && sim.arSession.delegate == nil, "Simulator: AR session not run")
    sim.leave()
}

@MainActor func testNoCameraFramesIsReported() async {
    let probe = Probe()
    ScanSessionController.noCameraTimeout = 0.7
    let c = makeController(simulated: false, probe: probe)
    c.start()
    // never give the AR session a frame
    await expect("camera alert when the AR session never delivers a frame", timeout: 4) { c.alert != nil }
    check(c.alert?.title == "The camera isn\u{2019}t available" && c.alert?.offersRescan == true, "alert wording \(String(describing: c.alert))")
    check(c.flow.state == .idle, "back to idle \(c.flow.state)")
    ScanSessionController.noCameraTimeout = 15

    // a session that does deliver frames is left alone
    let ok = makeController(simulated: false, probe: probe)
    ScanSessionController.noCameraTimeout = 0.7
    ok.start()
    ok.arSession.currentFrame = ARFrame()
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    check(ok.alert == nil && ok.flow.isCapturing, "no alert when frames arrive")
    ScanSessionController.noCameraTimeout = 15
    ok.leave()
    c.leave()
}

@MainActor func testTrackingHelpCountsOnlyTimeLost() async {
    let probe = Probe()
    ScanSessionController.relocalizationHelpDelay = 0.6
    let c = makeController(simulated: false, probe: probe)
    c.start()
    let frame = ARFrame()
    c.arSession.currentFrame = frame
    let bridge = c.arSession.delegate as? ScanCaptureBridge

    // away from the app for much longer than the delay
    bridge?.sessionWasInterrupted(c.arSession)
    await expect("interrupted") { c.tracking == .interrupted }
    try? await Task.sleep(nanoseconds: 1_400_000_000)
    check(!c.needsRelocalizationHelp, "time away does not count as tracking that did not come back")

    // back: ARKit is looking for the place
    frame.camera.trackingState = .limited(.relocalizing)
    bridge?.sessionInterruptionEnded(c.arSession)
    await expect("relocalising once the interruption has ended") { c.tracking == .relocalizing }
    check(!c.needsRelocalizationHelp, "the help card does not appear the moment the app returns")
    await expect("help card after the delay has passed while relocalising", timeout: 3) { c.needsRelocalizationHelp }

    // coming back to the app starts the clock over
    c.sceneBecameActive()
    check(!c.needsRelocalizationHelp, "foreground clears the card")
    await expect("and it can come back if tracking stays lost", timeout: 3) { c.needsRelocalizationHelp }

    frame.camera.trackingState = .normal
    await expect("tracking back", timeout: 2) { c.tracking == .none }
    check(!c.needsRelocalizationHelp, "card gone when tracking is back")
    ScanSessionController.relocalizationHelpDelay = 20
    c.leave()
}

@MainActor func testWallDeltasKeepFinishFromDependingOnOneCallback() async {
    let probe = Probe()
    let c = makeController(simulated: false, probe: probe)
    let session = realSession(c)
    c.start()
    func walls(_ n: Int) -> CapturedRoom {
        var r = rectRoom(width: 4, depth: 3)
        r.walls = Array(r.walls.prefix(n))
        return r
    }
    let a = walls(2)
    session.delegate?.captureSession(session, didAdd: a)
    await expect("two walls announced") { c.stats.walls == 2 }
    check(!c.canFinishRoom, "two walls are not enough")
    var third = walls(1); third.walls[0].identifier = UUID()
    session.delegate?.captureSession(session, didChange: third)
    await expect("third wall announced") { c.stats.walls == 3 }
    check(c.canFinishRoom, "Finish room works from didAdd/didChange alone")
    session.delegate?.captureSession(session, didRemove: third)
    await expect("removed again") { c.stats.walls == 2 }
    check(!c.canFinishRoom, "removing a wall counts")

    // the first snapshot takes over; later deltas must not shrink or grow the numbers
    await feed(c, rectRoom(width: 5, depth: 4))
    var extra = walls(2); extra.walls[0].identifier = UUID(); extra.walls[1].identifier = UUID()
    session.delegate?.captureSession(session, didAdd: extra)
    session.delegate?.captureSession(session, didChange: walls(1))
    try? await Task.sleep(nanoseconds: 150_000_000)
    check(c.stats.walls == 4, "deltas are ignored once a snapshot exists: \(c.stats.walls)")

    // the next room starts clean
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 5, depth: 4))]
    c.finishRoom()
    await expect("room built") { c.flow.draftAwaitingName != nil }
    _ = c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom)
    session.delegate?.captureSession(session, didAdd: walls(2))
    await expect("deltas count again in the next room") { c.stats.walls == 2 }
    c.leave()
}

@MainActor func testPracticeRoomsDoNotShareIdsAcrossScans() async {
    func scan(_ names: [String]) async -> ScanResult? {
        let probe = Probe()
        let c = makeController(simulated: true, probe: probe)
        c.start()
        for (i, name) in names.enumerated() {
            c.finishRoom()
            await expect("practice room built") { c.flow.draftAwaitingName != nil }
            _ = c.nameRoom(name, kind: .other, then: i == names.count - 1 ? .finishProperty : .scanNextRoom)
        }
        await expect("result delivered") { probe.finished.count == 1 }
        return probe.finished.first
    }
    guard let first = await scan(["Living Room", "Kitchen"]), let second = await scan(["Living Room", "Kitchen"]) else {
        return check(false, "two practice scans delivered")
    }
    func ids(_ r: ScanResult) -> Set<UUID> { Set(r.rooms.flatMap { [$0.id] + $0.walls.map(\.id) + $0.openings.map(\.id) }) }
    check(ids(first).count > 8 && ids(second).count > 8, "rooms, walls and openings all have ids")
    check(ids(first).isDisjoint(with: ids(second)), "a second practice scan shares no room, wall or opening id with the first")
    check(Set(first.rooms.map(\.id)).count == 2 && Set(second.rooms.map(\.id)).count == 2, "rooms within a scan differ")
    // the same index of the same scan is stable, so a rescan of that room is the same room
    let t = "token"
    check(SimulatedRoom.capture(forIndex: 0, story: 0, token: t).id == SimulatedRoom.capture(forIndex: 0, story: 0, token: t).id, "stable within a scan")
    check(SimulatedRoom.capture(forIndex: 0, story: 0, token: t).id != SimulatedRoom.capture(forIndex: 0, story: 0, token: "other").id, "token changes the id")
}

@MainActor func testMergeFailuresUseMergeWords() async {
    func run(_ error: Swift.Error) async -> ScanResult? {
        let probe = Probe()
        RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3)), .success(rectRoom(width: 3, depth: 3))]
        StructureBuilder.failWith = error
        let c = makeController(simulated: false, probe: probe)
        c.start()
        await feed(c, rectRoom(width: 4, depth: 3))
        c.finishRoom()
        await expect("room 1") { c.flow.draftAwaitingName != nil }
        _ = c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom)
        await feed(c, rectRoom(width: 3, depth: 3))
        c.finishRoom()
        await expect("room 2") { c.flow.draftAwaitingName != nil }
        _ = c.nameRoom("Bedroom", kind: .bedroom, then: .finishProperty)
        await expect("result delivered") { probe.finished.count == 1 }
        StructureBuilder.failWith = nil
        return probe.finished.first
    }
    let scanTimeAdvice = ["Walk slowly", "Finish this room", "Finish room", "Try again", "scan the room again"]
    if let big = await run(StructureBuilder.BuildError.exceedSceneSizeLimit) {
        check(big.rooms.count == 2 && big.structureUSDZ == nil, "rooms kept")
        check(big.warnings.contains("The floor is too big to join. Your rooms and measurements are saved without a joined model."), "too-big wording \(big.warnings)")
        check(!big.warnings.contains { w in scanTimeAdvice.contains { w.contains($0) } }, "no scan-time advice on the result screen \(big.warnings)")
    } else { check(false, "too-big result") }
    if let thin = await run(StructureBuilder.BuildError.insufficientInput) {
        check(thin.warnings.contains("Couldn\u{2019}t write the 3D model. Your rooms and measurements are saved without it."), "generic merge wording \(thin.warnings)")
        check(!thin.warnings.contains { w in scanTimeAdvice.contains { w.contains($0) } }, "no scan-time advice \(thin.warnings)")
    } else { check(false, "insufficient result") }
    if let other = await run(StructureBuilder.BuildError.internalError) {
        check(other.warnings.contains { $0.hasPrefix("Couldn\u{2019}t write the 3D model.") }, "internal error wording \(other.warnings)")
    } else { check(false, "internal result") }
}

@MainActor func testARErrorsMapToWords() async {
    let probe = Probe()
    let cases: [(ARError.Code, String)] = [(.cameraUnauthorized, "Camera access is off"), (.sensorFailed, "The camera isn\u{2019}t available"),
                                           (.sensorUnavailable, "The camera isn\u{2019}t available"), (.worldTrackingFailed, "Tracking failed"),
                                           (.invalidWorldMap, "Scanning stopped")]
    for (code, title) in cases {
        let c = makeController(simulated: false, probe: probe)
        c.start()
        c.arSession.currentFrame = ARFrame()
        let bridge = c.arSession.delegate as? ScanCaptureBridge
        bridge?.session(c.arSession, didFailWithError: ARError(code))
        await expect("alert for \(code)") { c.alert != nil }
        check(c.alert?.title == title, "\(code) -> \(String(describing: c.alert?.title)), wanted \(title)")
        c.leave()
    }
    check(ScanSessionController.failure(for: CocoaError(.fileNoSuchFile)) == .unknown, "unrelated errors stay unknown")
}


// MARK: Capture-fixer tests

@MainActor func testARFailureOnFirstRoomCanScanAgain() async {
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3)), .success(rectRoom(width: 3, depth: 3))]
    let c = makeController(simulated: false, probe: probe)
    let session = realSession(c)
    c.start()
    c.arSession.currentFrame = ARFrame()
    await feed(c, rectRoom(width: 4, depth: 3))
    let runsBefore = c.arSession.runCalls.count

    // finding 2: ARKit fails while scanning room 1
    c.arSession.delegate?.session(c.arSession, didFailWithError: ARError(.sensorUnavailable))
    await expect("alert after sensor failure") { c.alert != nil }
    check(c.alert?.offersRescan == true, "first room: scan again is offered \(String(describing: c.alert))")
    check(c.canContinueScanning, "can continue after a failure on the first room (finding 2)")
    check(c.flow.state == .idle, "idle \(c.flow.state)")
    c.scanAgain()
    check(c.flow.state == .scanning(roomIndex: 0), "scanning again \(c.flow.state)")
    check(c.arSession.runCalls.count == runsBefore + 1, "the AR session was run again: \(c.arSession.runCalls.count) vs \(runsBefore)")
    if let last = c.arSession.runCalls.last {
        check(last.options.contains(.resetTracking) && last.options.contains(.removeExistingAnchors), "reset on restart with no finished room")
        check(last.configuration is ARWorldTrackingConfiguration, "restart uses a world-tracking configuration")
    }
    check(session.runConfigurations.count == 2, "RoomPlan run again too \(session.runConfigurations.count)")
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    await expect("room 1 built after the restart") { c.flow.draftAwaitingName != nil }
    check(c.canContinueScanning, "still true after a good room 1")
    check(c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom).isValid, "named")
    check(c.flow.isCapturing && c.flow.rooms.count == 1, "scan next works after the restart \(c.flow.state)")
    c.leave()
}

@MainActor func testARFailureWithFinishedRoomsOnlyOffersFinish() async {
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3)), .success(rectRoom(width: 3, depth: 3))]
    let c = makeController(simulated: false, probe: probe)
    c.start()
    c.arSession.currentFrame = ARFrame()
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    await expect("room 1") { c.flow.draftAwaitingName != nil }
    _ = c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom)
    await feed(c, rectRoom(width: 3, depth: 3))
    c.finishRoom()
    await expect("room 2 awaiting name") { c.flow.draftAwaitingName != nil }

    c.arSession.delegate?.session(c.arSession, didFailWithError: ARError(.sensorFailed))
    await expect("alert") { c.alert != nil }
    check(!c.canContinueScanning, "with finished rooms only finishing is offered")
    let runs = c.arSession.runCalls.count
    // the name sheet hides Scan next room; a stray call must not start a capture on the dead session
    check(c.nameRoom("Bedroom", kind: .bedroom, then: .scanNextRoom).isValid, "named")
    check(c.flow.state == .betweenRooms, "stays between rooms \(c.flow.state)")
    check(c.arSession.runCalls.count == runs, "no AR restart for a room that cannot be joined")
    c.finishProperty()
    await expect("result delivered") { probe.finished.count == 1 }
    check(probe.finished.first?.rooms.count == 2, "both rooms delivered")
    // the restart came after the last room: both rooms are in the old space, the map is of the new one
    if let r = probe.finished.first {
        check(r.worldMapData == nil && !r.supportsARReview, "restart after the last room: no world map")
        check(c.arSession.worldMapRequests == 0, "and none was asked for")
        check(r.warnings.contains("Tracking restarted partway through, so AR review is off for this level. Scan the level again in one go to use AR."), "AR warning, exact words \(r.warnings)")
        check(r.structureUSDZ != nil, "the 3D model of the one space is still made")
        check(r.capturedRoomJSON.count == 2, "detailed scan data kept")
    }

    // camera not allowed: never offered again, even on the first room
    let c2 = makeController(simulated: false, probe: Probe())
    c2.start()
    await feed(c2, rectRoom(width: 4, depth: 3))
    c2.arSession.delegate?.session(c2.arSession, didFailWithError: ARError(.cameraUnauthorized))
    await expect("alert for no camera") { c2.alert != nil }
    check(c2.alert?.offersRescan == false && !c2.canContinueScanning, "unrecoverable: no rescan \(String(describing: c2.alert))")
    c2.leave()
}

@MainActor func testPausedARSessionIsRunAgainForTheNextFirstRoom() async {
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3)), .success(rectRoom(width: 4, depth: 3))]
    let c = makeController(simulated: false, probe: probe)
    c.start()
    c.arSession.currentFrame = ARFrame()
    await feed(c, rectRoom(width: 4, depth: 3))
    c.finishRoom()
    await expect("room built") { c.flow.draftAwaitingName != nil }
    let runs = c.arSession.runCalls.count
    c.discardWaitingRoom()           // no finished room: AR session paused
    check(c.flow.state == .idle && c.arSession.pauseCount >= 1, "idle and paused \(c.flow.state)")
    c.scanAgain()
    check(c.arSession.runCalls.count == runs + 1, "paused session run again before the next capture")
    check(c.flow.isCapturing, "capturing")
    c.leave()
}

@MainActor func listRecoverable() -> [ScanRecoveryStore.RecoverableScan] { ScanRecoveryStore.recoverableScans(root: recoveryRoot) }

@MainActor func testRecoveryCopyFollowsTheScan() async {
    recoveryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("capfix-recovery-\(UUID().uuidString)")
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 5, depth: 4)), .success(rectRoom(width: 5, depth: 4)), .success(rectRoom(width: 3, depth: 3))]
    let c = makeController(simulated: false, probe: probe)
    c.start()
    c.arSession.currentFrame = ARFrame()
    check(listRecoverable().isEmpty, "nothing on disk before the first room")
    await feed(c, rectRoom(width: 5, depth: 4))
    c.finishRoom()
    await expect("room 1 built") { c.flow.draftAwaitingName != nil }
    await expect("room 1 written to disk before it is named", timeout: 4) { listRecoverable().first?.roomCount == 1 }
    check(listRecoverable().first?.propertyID == harnessPropertyID && listRecoverable().first?.story == 1, "property and level recorded")

    // rescan: the thrown-away room must not come back
    c.rescanRoom()
    await expect("rescan running") { c.flow.isCapturing }
    await expect("the thrown-away room left the disk copy", timeout: 4) { listRecoverable().isEmpty }
    await feed(c, rectRoom(width: 5, depth: 4))
    c.finishRoom()
    await expect("room 1 again") { c.flow.draftAwaitingName != nil }
    check(c.nameRoom("Living Room", kind: .livingRoom, then: .scanNextRoom).isValid, "named")
    await feed(c, rectRoom(width: 3, depth: 3))
    c.finishRoom()
    await expect("room 2") { c.flow.draftAwaitingName != nil }
    await expect("two rooms on disk", timeout: 4) { listRecoverable().first?.roomCount == 2 }
    check(c.nameRoom("Kitchen", kind: .kitchen, then: .finishProperty).isValid, "finish")
    await expect("delivered") { probe.finished.count == 1 }
    guard let result = probe.finished.first else { return }
    let id = result.recoveryID
    check(id != nil, "result carries the recovery id")
    await expect("copy marked delivered, and kept until the app confirms", timeout: 4) { listRecoverable().first?.delivered == true }

    // the copy rebuilds the same rooms
    do {
        let again = try ScanRecoveryStore.recoveredResult(scanID: id!, root: recoveryRoot)
        check(again.rooms.map(\.name) == ["Living Room", "Kitchen"], "names recovered \(again.rooms.map(\.name))")
        check(again.rooms.map(\.kind) == [.livingRoom, .kitchen], "kinds recovered")
        check(again.rooms.map(\.id) == result.rooms.map(\.id), "same room ids as the delivered result: saving either gives the same rooms")
        check(again.capturedRoomJSON.count == 2, "detailed scan data recovered")
        check(again.structureUSDZ == nil && again.worldMapData == nil, "no model, no map")
        check(again.warnings.first?.contains("recovered") == true, "says it was recovered")
    } catch { check(false, "recovery threw \(error)") }
    ScanRecoveryStore.discard(scanID: id!, root: recoveryRoot)
    check(listRecoverable().isEmpty, "discarded once saved")

    // leaving on purpose takes the copy with it
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3)), .success(rectRoom(width: 4, depth: 3))]
    let c2 = makeController(simulated: false, probe: Probe())
    c2.start()
    c2.arSession.currentFrame = ARFrame()
    await feed(c2, rectRoom(width: 4, depth: 3))
    c2.finishRoom()
    await expect("room built") { c2.flow.draftAwaitingName != nil }
    await expect("on disk", timeout: 4) { listRecoverable().count == 1 }
    c2.leave()
    await expect("copy removed when the person discards the scan", timeout: 4) { listRecoverable().isEmpty }
    // and a copy left behind by a controller that is only torn down (view gone) stays
    let c3 = makeController(simulated: false, probe: Probe())
    c3.start()
    c3.arSession.currentFrame = ARFrame()
    await feed(c3, rectRoom(width: 4, depth: 3))
    c3.finishRoom()
    await expect("room built") { c3.flow.draftAwaitingName != nil }
    await expect("on disk", timeout: 4) { listRecoverable().count == 1 }
    c3.teardown()
    try? await Task.sleep(nanoseconds: 300_000_000)
    check(listRecoverable().count == 1, "teardown alone keeps the copy for the next launch")
    try? FileManager.default.removeItem(at: recoveryRoot)
}

@MainActor func testForegroundClockDoesNotCountTimeAway() async {
    let clock = ForegroundClock()
    clock.setActive(false)
    var done = false
    let waiter = Task.detached { let ok = await clock.wait(seconds: 0.5, tick: 0.1); done = true; return ok }
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    check(!done, "no time passes while away")
    clock.setActive(true)
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    check(done, "finishes after the time in the foreground")
    let waiterResult = await waiter.value
    check(waiterResult, "reported as elapsed")
    let cancelled = Task.detached { await clock.wait(seconds: 30, tick: 0.1) }
    try? await Task.sleep(nanoseconds: 200_000_000)
    cancelled.cancel()
    let cancelledResult = await cancelled.value
    check(cancelledResult == false, "cancelled wait reports false")

    // the end-of-capture watchdog does not fire while the app is away
    let savedTimeout = ScanSessionController.endTimeout
    ScanSessionController.endTimeout = 0.5
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 4, depth: 3))]
    let c = makeController(simulated: false, probe: probe)
    let session = realSession(c)
    c.start()
    c.arSession.currentFrame = ARFrame()
    await feed(c, rectRoom(width: 4, depth: 3))
    session.suppressEnd = true
    c.sceneBecameInactive()
    c.finishRoom()
    try? await Task.sleep(nanoseconds: 1_600_000_000)
    check(c.alert == nil && c.flow.isProcessingRoom, "no timeout while the app is away \(String(describing: c.alert?.title)) \(c.flow.state)")
    c.sceneBecameActive()
    await expect("timeout once back and still waiting", timeout: 4) { c.alert != nil }
    ScanSessionController.endTimeout = savedTimeout
    c.leave()
}

@MainActor func testFloorSizeCaution() async {
    let probe = Probe()
    RoomPlan.RoomBuilder.nextResults = [.success(rectRoom(width: 12, depth: 9)), .success(rectRoom(width: 8, depth: 7)), .success(rectRoom(width: 6, depth: 5))]
    let c = makeController(simulated: false, probe: probe)
    c.start()
    c.arSession.currentFrame = ARFrame()
    check(c.floorSizeCaution == nil, "no caution at the start")
    await feed(c, rectRoom(width: 12, depth: 9))               // 108 m2 in progress
    check(c.floorSizeCaution == nil, "108 m2 is fine \(c.scannedFloorAreaM2)")
    c.finishRoom()
    await expect("room 1") { c.flow.draftAwaitingName != nil }
    _ = c.nameRoom("Majlis", kind: .livingRoom, then: .scanNextRoom)
    check(c.floorSizeCaution == nil, "still fine at \(c.scannedFloorAreaM2)")
    await feed(c, rectRoom(width: 8, depth: 7))                // +56 -> 164 m2
    check(c.floorSizeCaution?.contains("186") == true, "caution above 150 m2: \(c.scannedFloorAreaM2) \(String(describing: c.floorSizeCaution))")
    c.leave()
}

Task { @MainActor in
    testMapper()
    testCapability()
    await testSimulatedFlow()
    await testRealFlow()
    await testRealErrorsAndInterruptions()
    await testMergeFailureKeepsRooms()
    await testRealUnexpectedEndAndLeave()
    await testCancelWhileProcessingAndWatchdog()
    await testWatchdogAndWorldMapTimeoutAreBounded()
    await testARSessionRunsBeforeTheViewAndDelegateIsChained()
    await testNoCameraFramesIsReported()
    await testTrackingHelpCountsOnlyTimeLost()
    await testWallDeltasKeepFinishFromDependingOnOneCallback()
    await testPracticeRoomsDoNotShareIdsAcrossScans()
    await testMergeFailuresUseMergeWords()
    await testARErrorsMapToWords()
    await testARFailureOnFirstRoomCanScanAgain()
    await testARFailureWithFinishedRoomsOnlyOffersFinish()
    await testPausedARSessionIsRunAgainForTheNextFirstRoom()
    await testRecoveryCopyFollowsTheScan()
    await testForegroundClockDoesNotCountTimeAway()
    await testFloorSizeCaution()
    print("checks: \(checks), failures: \(failures)")
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
