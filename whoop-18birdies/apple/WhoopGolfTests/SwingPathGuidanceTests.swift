import XCTest
@testable import WhoopGolf

final class SwingPathGuidanceTests: XCTestCase {
    func testTrailRightDefaultIsTheShippedWrist() {
        XCTAssertEqual(WatchWristMount.golferDefault, .trailRight)
        XCTAssertEqual(WatchWristMount.trailRight.pathSign, -1)
        XCTAssertEqual(WatchWristMount.leadLeft.pathSign, 1)
        XCTAssertEqual(WatchWristMount.trailRight.coachingName, "trail wrist")
        XCTAssertEqual(WatchWristMount.leadLeft.coachingName, "lead wrist")
    }

    func testLoadFallsBackToTrailRightWhenUnset() {
        let defaults = UserDefaults(suiteName: "whoopgolf.wrist.test.\(UUID().uuidString)")!
        XCTAssertEqual(WatchWristMount.load(defaults: defaults), .trailRight)
        WatchWristMount.save(.leadLeft, defaults: defaults)
        XCTAssertEqual(WatchWristMount.load(defaults: defaults), .leadLeft)
        WatchWristMount.save(.trailRight, defaults: defaults)
        XCTAssertEqual(WatchWristMount.load(defaults: defaults), .trailRight)
    }

    func testLoadIgnoresCorruptStoredWristAndReturnsDefault() {
        let defaults = UserDefaults(suiteName: "whoopgolf.wrist.corrupt.\(UUID().uuidString)")!
        defaults.set("not-a-wrist", forKey: WatchWristMount.storageKey)
        XCTAssertEqual(WatchWristMount.load(defaults: defaults), .trailRight)
    }

    func testTrailRightMirrorsLeadLeftPathClass() {
        let rawYaw = 20.0
        let lead = SwingPathGuidance.classify(downswingYawDegrees: rawYaw, wrist: .leadLeft)
        let trail = SwingPathGuidance.classify(downswingYawDegrees: rawYaw, wrist: .trailRight)
        XCTAssertEqual(lead.path, .inToOut)
        XCTAssertEqual(trail.path, .outToIn)
        XCTAssertEqual(lead.correctedYawDegrees, 20.0)
        XCTAssertEqual(trail.correctedYawDegrees, -20.0)
    }

    func testNegativeYawMirrorFlipsPathClassAcrossMounts() {
        let rawYaw = -20.0
        let lead = SwingPathGuidance.classify(downswingYawDegrees: rawYaw, wrist: .leadLeft)
        let trail = SwingPathGuidance.classify(downswingYawDegrees: rawYaw, wrist: .trailRight)
        XCTAssertEqual(lead.path, .outToIn)
        XCTAssertEqual(trail.path, .inToOut)
        XCTAssertEqual(lead.correctedYawDegrees, -20.0)
        XCTAssertEqual(trail.correctedYawDegrees, 20.0)
    }

    func testNilOrNonFiniteYawIsUnknown() {
        let missing = SwingPathGuidance.classify(downswingYawDegrees: nil, wrist: .trailRight)
        XCTAssertEqual(missing.path, .unknown)
        XCTAssertNil(missing.correctedYawDegrees)

        let infinite = SwingPathGuidance.classify(
            downswingYawDegrees: .infinity,
            wrist: .trailRight
        )
        XCTAssertEqual(infinite.path, .unknown)
        XCTAssertNil(infinite.correctedYawDegrees)
    }

    func testOnPlaneBandUsesCorrectedYaw() {
        let result = SwingPathGuidance.classify(downswingYawDegrees: 4, wrist: .trailRight)
        XCTAssertEqual(result.path, .onPlane)
        XCTAssertEqual(SwingPathGuidance.coachingLabel(.inToOut), "in-to-out")
        XCTAssertEqual(SwingPathGuidance.coachingLabel(.outToIn), "out-to-in")
        XCTAssertEqual(SwingPathGuidance.coachingLabel(.onPlane), "on-plane")
        XCTAssertEqual(SwingPathGuidance.coachingLabel(.unknown), "no path yet")
        XCTAssertTrue(
            SwingPathGuidance.provenanceCaption(wrist: .trailRight)
                .contains("trail wrist")
        )
    }

    func testOnPlaneBoundaryIsExclusiveOfThreshold() {
        let justInside = SwingPathGuidance.classify(
            downswingYawDegrees: SwingPathGuidance.onPlaneDegrees - 0.1,
            wrist: .leadLeft
        )
        XCTAssertEqual(justInside.path, .onPlane)

        let atThreshold = SwingPathGuidance.classify(
            downswingYawDegrees: SwingPathGuidance.onPlaneDegrees,
            wrist: .leadLeft
        )
        XCTAssertEqual(atThreshold.path, .inToOut)
    }

    func testImproverCopyNamesTrailWristForDefaultMount() {
        let cue = GolfImprover.cue(path: .outToIn, tempoRatio: 3.0, wrist: .trailRight)
        XCTAssertTrue(cue.lowercased().contains("trail"))
        XCTAssertFalse(cue.lowercased().contains("lead arm"))
    }

    func testImproverMapsPathAndTempoToStableCuesAndDrills() {
        let trailOut = GolfImprover.cue(path: .outToIn, tempoRatio: 3.0, wrist: .trailRight)
        let leadOut = GolfImprover.cue(path: .outToIn, tempoRatio: 3.0, wrist: .leadLeft)
        XCTAssertTrue(trailOut.contains("trail elbow"))
        XCTAssertTrue(leadOut.contains("lead arm"))

        let trailIn = GolfImprover.cue(path: .inToOut, tempoRatio: 3.0, wrist: .trailRight)
        let leadIn = GolfImprover.cue(path: .inToOut, tempoRatio: 3.0, wrist: .leadLeft)
        XCTAssertTrue(trailIn.contains("trail hand"))
        XCTAssertTrue(leadIn.contains("lead wrist"))

        let onPlane = GolfImprover.cue(path: .onPlane, tempoRatio: 3.0, wrist: .trailRight)
        XCTAssertTrue(onPlane.contains("trail wrist"))

        let unknown = GolfImprover.cue(path: .unknown, tempoRatio: nil, wrist: .trailRight)
        XCTAssertTrue(unknown.lowercased().contains("pause"))

        let rush = GolfImprover.cue(path: .onPlane, tempoRatio: 2.0, wrist: .trailRight)
        XCTAssertTrue(rush.lowercased().contains("rushing"))
        XCTAssertEqual(
            GolfImprover.drill(path: .onPlane, tempoRatio: 2.0),
            "Drill: three slow rehearsals, 1-second pause at the top, then swing"
        )
        XCTAssertTrue(
            GolfImprover.drill(path: .outToIn, tempoRatio: 3.0)
                .lowercased()
                .contains("headcover")
        )
        XCTAssertTrue(
            GolfImprover.drill(path: .inToOut, tempoRatio: 3.0)
                .contains("9-to-3")
        )
    }

    func testImproverConsistencyCaptionBands() {
        XCTAssertTrue(
            GolfImprover.consistencyCaption(tempoCV: nil)
                .lowercased()
                .contains("need")
        )
        XCTAssertTrue(
            GolfImprover.consistencyCaption(tempoCV: 0.05)
                .lowercased()
                .contains("tight")
        )
        XCTAssertTrue(
            GolfImprover.consistencyCaption(tempoCV: 0.15)
                .lowercased()
                .contains("usable")
        )
        XCTAssertTrue(
            GolfImprover.consistencyCaption(tempoCV: 0.30)
                .lowercased()
                .contains("scattered")
        )
    }

    func testLiveFaceOmitsInventedHoleMap() {
        let face = WatchLiveFace(holeNumber: 7, lastShotYards: 184, wristMount: .trailRight)
        XCTAssertFalse(face.hasHoleMap)
        XCTAssertNil(face.frontYards)
        XCTAssertNil(face.middleYards)
        XCTAssertNil(face.backYards)
        XCTAssertEqual(face.wristMount, .trailRight)
        XCTAssertEqual(face.holeNumber, 7)
        XCTAssertEqual(face.lastShotYards, 184)
        XCTAssertEqual(face.schemaVersion, WatchLiveFace.currentSchemaVersion)
    }

    func testLiveFaceReportsHoleMapOnlyWhenYardsPresent() {
        let mapped = WatchLiveFace(
            holeNumber: 3,
            frontYards: 140,
            middleYards: 155,
            backYards: 170,
            lastShotYards: 162,
            wristMount: .trailRight
        )
        XCTAssertTrue(mapped.hasHoleMap)
    }
}
