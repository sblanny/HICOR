import XCTest
@testable import HICOR

final class ConsistencyValidatorTests: XCTestCase {

    private func makeResult(
        rightSPHs: [Double],
        leftSPHs: [Double],
        rightCYLs: [Double]? = nil,
        leftCYLs: [Double]? = nil,
        rightMachineAvgSPH: Double? = nil,
        leftMachineAvgSPH: Double? = nil,
        rightMachineAvgCYL: Double? = nil,
        leftMachineAvgCYL: Double? = nil,
        rightMachineAvgAX: Int? = nil,
        leftMachineAvgAX: Int? = nil,
        photoIndex: Int = 0
    ) -> PrintoutResult {
        let rCyls = rightCYLs ?? Array(repeating: -0.50, count: rightSPHs.count)
        let lCyls = leftCYLs  ?? Array(repeating: -0.50, count: leftSPHs.count)
        let rRight = zip(rightSPHs, rCyls).map { (sph, cyl) in
            RawReading(id: UUID(), sph: sph, cyl: cyl, ax: 90, eye: .right, sourcePhotoIndex: photoIndex)
        }
        let rLeft = zip(leftSPHs, lCyls).map { (sph, cyl) in
            RawReading(id: UUID(), sph: sph, cyl: cyl, ax: 90, eye: .left, sourcePhotoIndex: photoIndex)
        }
        let right = EyeReading(id: UUID(), eye: .right, readings: rRight, machineAvgSPH: rightMachineAvgSPH, machineAvgCYL: rightMachineAvgCYL, machineAvgAX: rightMachineAvgAX, sourcePhotoIndex: photoIndex, machineType: .desktop)
        let left  = EyeReading(id: UUID(), eye: .left,  readings: rLeft,  machineAvgSPH: leftMachineAvgSPH,  machineAvgCYL: leftMachineAvgCYL,  machineAvgAX: leftMachineAvgAX,  sourcePhotoIndex: photoIndex, machineType: .desktop)
        return PrintoutResult(rightEye: right, leftEye: left, pd: nil, machineType: .desktop, sourcePhotoIndex: photoIndex, rawText: "")
    }

    private func assertConsistent(_ result: ConsistencyValidator.Result, expectedDroppedCount: Int = 0, file: StaticString = #filePath, line: UInt = #line) {
        if case .consistent(let dropped) = result {
            XCTAssertEqual(dropped.count, expectedDroppedCount, file: file, line: line)
        } else {
            XCTFail("Expected .consistent, got \(result)", file: file, line: line)
        }
    }

    func test2PhotosConsistent_returnsConsistent_withEmptyDroppedOutliers() {
        let p1 = makeResult(rightSPHs: [-2.00, -2.25], leftSPHs: [-2.00, -2.25], photoIndex: 0)
        let p2 = makeResult(rightSPHs: [-2.25, -2.00], leftSPHs: [-2.25, -2.00], photoIndex: 1)
        let outcome = ConsistencyValidator().validate([p1, p2])
        if case .consistent(let dropped) = outcome {
            XCTAssertTrue(dropped.isEmpty, "All readings agree — no outliers expected")
        } else {
            XCTFail("Expected .consistent, got \(outcome)")
        }
    }

    func test2PhotosSignMismatch_returnsAddPhoto_count2() {
        let p1 = makeResult(rightSPHs: [+1.50], leftSPHs: [-2.00], photoIndex: 0)
        let p2 = makeResult(rightSPHs: [+1.75], leftSPHs: [-2.25], photoIndex: 1)
        let outcome = ConsistencyValidator().validate([p1, p2])
        if case .inconsistentAddPhoto(_, let count) = outcome {
            XCTAssertEqual(count, 2)
        } else {
            XCTFail("Expected .inconsistentAddPhoto, got \(outcome)")
        }
    }

    func test2PhotosSpreadTooWide_returnsAddPhoto_count2() {
        let p1 = makeResult(rightSPHs: [-2.00], leftSPHs: [-2.00], photoIndex: 0)
        let p2 = makeResult(rightSPHs: [-4.00], leftSPHs: [-2.25], photoIndex: 1)
        let outcome = ConsistencyValidator().validate([p1, p2])
        if case .inconsistentAddPhoto(let reason, let count) = outcome {
            XCTAssertEqual(count, 2)
            XCTAssertTrue(reason.contains("AVG") && reason.contains("differs"),
                          "Reason should describe AVG divergence, got: \(reason)")
        } else {
            XCTFail("Expected .inconsistentAddPhoto, got \(outcome)")
        }
    }

    func test3PhotosMajorityAgree_outliersReturnedInResult() {
        let p1 = makeResult(rightSPHs: [-2.25], leftSPHs: [-2.25], photoIndex: 0)
        let p2 = makeResult(rightSPHs: [-2.25], leftSPHs: [-2.25], photoIndex: 1)
        let p3 = makeResult(rightSPHs: [-4.00], leftSPHs: [-2.25], photoIndex: 2)
        let outcome = ConsistencyValidator().validate([p1, p2, p3])
        if case .consistent(let dropped) = outcome {
            XCTAssertEqual(dropped.count, 1, "One outlier reading should be dropped")
            XCTAssertEqual(dropped.first?.reading.sph, -4.00)
            XCTAssertEqual(dropped.first?.photoIndex, 2)
            XCTAssertEqual(dropped.first?.eye, .right)
        } else {
            XCTFail("Expected .consistent with dropped outlier, got \(outcome)")
        }
    }

    func testDroppedReadingReasonIncludesThreshold() {
        let p1 = makeResult(rightSPHs: [-2.25], leftSPHs: [-2.25], photoIndex: 0)
        let p2 = makeResult(rightSPHs: [-2.25], leftSPHs: [-2.25], photoIndex: 1)
        let p3 = makeResult(rightSPHs: [-4.00], leftSPHs: [-2.25], photoIndex: 2)
        let outcome = ConsistencyValidator().validate([p1, p2, p3])
        guard case .consistent(let dropped) = outcome, let first = dropped.first else {
            return XCTFail("Expected a dropped outlier")
        }
        XCTAssertTrue(first.reason.contains("SPH"), "Reason should name SPH, got: \(first.reason)")
        XCTAssertTrue(first.reason.contains("majority"), "Reason should mention majority, got: \(first.reason)")
        XCTAssertTrue(first.reason.contains("differs"), "Reason should describe divergence, got: \(first.reason)")
        XCTAssertTrue(first.reason.contains("D"), "Reason should include diopter unit, got: \(first.reason)")
    }

    func testNoOutliers_droppedOutliersIsEmpty() {
        let p1 = makeResult(rightSPHs: [-2.00], leftSPHs: [-2.00], photoIndex: 0)
        let p2 = makeResult(rightSPHs: [-2.25], leftSPHs: [-2.00], photoIndex: 1)
        let p3 = makeResult(rightSPHs: [-2.00], leftSPHs: [-2.25], photoIndex: 2)
        let outcome = ConsistencyValidator().validate([p1, p2, p3])
        if case .consistent(let dropped) = outcome {
            XCTAssertTrue(dropped.isEmpty, "All readings agree — dropped list must be explicitly empty, got \(dropped.count)")
        } else {
            XCTFail("Expected .consistent, got \(outcome)")
        }
    }

    func test3PhotosAllDisagree_returnsAddPhoto_count3() {
        let p1 = makeResult(rightSPHs: [-2.00], leftSPHs: [-2.00], photoIndex: 0)
        let p2 = makeResult(rightSPHs: [-4.00], leftSPHs: [-2.25], photoIndex: 1)
        let p3 = makeResult(rightSPHs: [-6.00], leftSPHs: [-2.25], photoIndex: 2)
        let outcome = ConsistencyValidator().validate([p1, p2, p3])
        if case .inconsistentAddPhoto(_, let count) = outcome {
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected .inconsistentAddPhoto (3 photos, no majority), got \(outcome)")
        }
    }

    func test5PhotosStillInconsistent_returnsEscalate() {
        let photos = (0..<5).map { idx in
            makeResult(rightSPHs: [Double(idx) * -1.0 - 2.0], leftSPHs: [-2.00], photoIndex: idx)
        }
        let outcome = ConsistencyValidator().validate(photos)
        if case .inconsistentEscalate = outcome {
            // expected
        } else {
            XCTFail("Expected .inconsistentEscalate at 5 photos with no agreement, got \(outcome)")
        }
    }

    func testTightSpreadWithinThresholdIsConsistent() {
        let p1 = makeResult(rightSPHs: [-2.00, -2.25, -2.00], leftSPHs: [-2.00, -2.25, -2.25], photoIndex: 0)
        let p2 = makeResult(rightSPHs: [-2.00, -2.25, -2.00], leftSPHs: [-2.00, -2.25, -2.25], photoIndex: 1)
        let outcome = ConsistencyValidator().validate([p1, p2])
        assertConsistent(outcome)
    }

    func testImplausibleSphValuesFilteredFromSignAverage() {
        // Defense-in-depth: an sph=+90 (axis misread as SPH) must not flip the
        // eye's average sign and trigger a false mismatch.
        let rRight = [
            RawReading(id: UUID(), sph: -2.00, cyl: -0.50, ax: 90, eye: .right, sourcePhotoIndex: 0),
            RawReading(id: UUID(), sph: -2.25, cyl: -0.50, ax: 90, eye: .right, sourcePhotoIndex: 0)
        ]
        let rLeft = [
            RawReading(id: UUID(), sph: -2.00, cyl: -0.50, ax: 90, eye: .left, sourcePhotoIndex: 0),
            RawReading(id: UUID(), sph: -2.00, cyl: -0.50, ax: 90, eye: .left, sourcePhotoIndex: 0),
            RawReading(id: UUID(), sph: +90.0, cyl: -0.50, ax: 90, eye: .left, sourcePhotoIndex: 0)
        ]
        let right = EyeReading(id: UUID(), eye: .right, readings: rRight, machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: 0, machineType: .handheld)
        let left  = EyeReading(id: UUID(), eye: .left,  readings: rLeft,  machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: 0, machineType: .handheld)
        let p1 = PrintoutResult(rightEye: right, leftEye: left, pd: nil, machineType: .handheld, sourcePhotoIndex: 0, rawText: "")
        let p2 = makeResult(rightSPHs: [-2.00], leftSPHs: [-2.00], photoIndex: 1)
        let outcome = ConsistencyValidator().validate([p1, p2])
        assertConsistent(outcome)
    }

    // MARK: - AVG-based agreement (MIKE_RX_PROCEDURE.md §1, §4)

    func testWideRawRangeButAVGsAgree_consistent() {
        // Real failure from device test: raw readings span 0.00 → 2.00 D
        // (within-printout machine noise — expected and absorbed by the
        // machine's AVG line). The two printouts' AVGs differ by only 0.75 D,
        // which is within Mike's 1.00 D agreement threshold → consistent.
        let p1 = makeResult(
            rightSPHs: [0.00, 1.00, 1.50],
            leftSPHs:  [0.00, 1.00, 1.50],
            rightMachineAvgSPH: 0.75,
            leftMachineAvgSPH:  0.75,
            photoIndex: 0
        )
        let p2 = makeResult(
            rightSPHs: [0.75, 2.00, 2.00],
            leftSPHs:  [0.75, 2.00, 2.00],
            rightMachineAvgSPH: 1.50,
            leftMachineAvgSPH:  1.50,
            photoIndex: 1
        )
        let outcome = ConsistencyValidator().validate([p1, p2])
        if case .consistent(let dropped) = outcome {
            XCTAssertTrue(dropped.isEmpty, "AVGs differ by 0.75 D — within threshold; expected no drops")
        } else {
            XCTFail("Expected .consistent, got \(outcome)")
        }
    }

    func testRawReadingsAgreeButMachineAVGsDisagree_returnsAddPhoto() {
        // Edge case: parsed AVG itself disagrees even though raws happen to
        // match. Could indicate a misread AVG line — should still trigger a
        // retake rather than be silently ignored.
        let p1 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: 1.00,
            leftMachineAvgSPH:  1.00,
            photoIndex: 0
        )
        let p2 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: 3.50,
            leftMachineAvgSPH:  3.50,
            photoIndex: 1
        )
        let outcome = ConsistencyValidator().validate([p1, p2])
        if case .inconsistentAddPhoto(let reason, _) = outcome {
            XCTAssertTrue(reason.contains("AVG"), "Reason should reference AVG comparison, got: \(reason)")
        } else {
            XCTFail("Expected .inconsistentAddPhoto, got \(outcome)")
        }
    }

    func testAVGsDifferExactly100D_consistentAtBoundary() {
        // Section 1: "within 1.00 D" — equality is in. Threshold uses `>` so
        // a diff of exactly 1.00 D is accepted.
        let p1 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: -1.00,
            leftMachineAvgSPH:  -1.00,
            photoIndex: 0
        )
        let p2 = makeResult(
            rightSPHs: [-2.00],
            leftSPHs:  [-2.00],
            rightMachineAvgSPH: -2.00,
            leftMachineAvgSPH:  -2.00,
            photoIndex: 1
        )
        let outcome = ConsistencyValidator().validate([p1, p2])
        if case .consistent = outcome {
            // expected
        } else {
            XCTFail("Expected .consistent at exact 1.00 D boundary, got \(outcome)")
        }
    }

    func testThreePrintoutsOneAVGOutlier_droppedAndConsistent() {
        // Three printouts, all left-eye AVGs: -2.00, -2.25, -4.00.
        // The third deviates by 1.875 D from the majority's 2.125 D mean —
        // dropped at the AVG level, surfaced as DroppedReading entries.
        let p1 = makeResult(
            rightSPHs: [-2.00],
            leftSPHs:  [-2.00],
            rightMachineAvgSPH: -2.00,
            leftMachineAvgSPH:  -2.00,
            photoIndex: 0
        )
        let p2 = makeResult(
            rightSPHs: [-2.00],
            leftSPHs:  [-2.25],
            rightMachineAvgSPH: -2.00,
            leftMachineAvgSPH:  -2.25,
            photoIndex: 1
        )
        let p3 = makeResult(
            rightSPHs: [-2.00],
            leftSPHs:  [-4.00],
            rightMachineAvgSPH: -2.00,
            leftMachineAvgSPH:  -4.00,
            photoIndex: 2
        )
        let outcome = ConsistencyValidator().validate([p1, p2, p3])
        if case .consistent(let dropped) = outcome {
            XCTAssertEqual(dropped.count, 1, "One outlier reading from photo 2 should be dropped")
            XCTAssertEqual(dropped.first?.photoIndex, 2)
            XCTAssertEqual(dropped.first?.eye, .left)
            let reason = dropped.first?.reason ?? ""
            XCTAssertTrue(reason.contains("SPH"), "Reason should name SPH, got: \(reason)")
            XCTAssertTrue(reason.contains("majority"), "Reason should mention majority, got: \(reason)")
            XCTAssertTrue(reason.contains("differs"), "Reason should describe divergence, got: \(reason)")
            XCTAssertTrue(reason.contains("D"), "Reason should include diopter unit, got: \(reason)")
        } else {
            XCTFail("Expected .consistent with one drop, got \(outcome)")
        }
    }

    // MARK: - Plano CYL axis-check skip
    //
    // When CYL is 0.00 (plano), axis is clinically meaningless — the
    // autorefractor emits a placeholder (typically 180°) that varies
    // arbitrarily. The pairwise check must skip the axis comparison
    // when either printout has plano CYL.

    func testTwoPrintoutsBothPlanoCYL_axisIgnored() {
        let p1 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: -1.00,
            leftMachineAvgSPH:  -1.00,
            rightMachineAvgCYL: 0.00,
            leftMachineAvgCYL:  0.00,
            rightMachineAvgAX: 180,
            leftMachineAvgAX:  180,
            photoIndex: 0
        )
        let p2 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: -1.00,
            leftMachineAvgSPH:  -1.00,
            rightMachineAvgCYL: 0.00,
            leftMachineAvgCYL:  0.00,
            rightMachineAvgAX: 90,   // 90° vs 180° — would exceed any cyl tolerance
            leftMachineAvgAX:  90,
            photoIndex: 1
        )
        assertConsistent(ConsistencyValidator().validate([p1, p2]))
    }

    func testTwoPrintoutsBothNonPlanoCYL_axisCheckedAndAccepted() {
        let p1 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: -1.00,
            leftMachineAvgSPH:  -1.00,
            rightMachineAvgCYL: -0.50,
            leftMachineAvgCYL:  -0.50,
            rightMachineAvgAX: 90,
            leftMachineAvgAX:  90,
            photoIndex: 0
        )
        let p2 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: -1.00,
            leftMachineAvgSPH:  -1.00,
            rightMachineAvgCYL: -0.50,
            leftMachineAvgCYL:  -0.50,
            rightMachineAvgAX: 95,    // within 15° tolerance for cyl 0.50-1.00
            leftMachineAvgAX:  95,
            photoIndex: 1
        )
        assertConsistent(ConsistencyValidator().validate([p1, p2]))
    }

    func testTwoPrintoutsBothNonPlanoCYL_axisOutOfRangeFlags() {
        let p1 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: -1.00,
            leftMachineAvgSPH:  -1.00,
            rightMachineAvgCYL: -0.50,
            leftMachineAvgCYL:  -0.50,
            rightMachineAvgAX: 90,
            leftMachineAvgAX:  90,
            photoIndex: 0
        )
        let p2 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: -1.00,
            leftMachineAvgSPH:  -1.00,
            rightMachineAvgCYL: -0.50,
            leftMachineAvgCYL:  -0.50,
            rightMachineAvgAX: 130,   // 40° diff > 15° tolerance for cyl 0.50-1.00
            leftMachineAvgAX:  130,
            photoIndex: 1
        )
        let outcome = ConsistencyValidator().validate([p1, p2])
        if case .inconsistentAddPhoto(let reason, _) = outcome {
            XCTAssertTrue(reason.contains("axis"), "Reason should reference axis, got: \(reason)")
        } else {
            XCTFail("Expected .inconsistentAddPhoto for axis out of tolerance, got \(outcome)")
        }
    }

    func testOnePlanoOneNonPlanoCYL_flagsOnCYLNotAxis() {
        // 0.00 vs -0.50 cyl exceeds the 0.50 D agreement threshold.
        // Path should fail on CYL before axis is even examined.
        let p1 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: -1.00,
            leftMachineAvgSPH:  -1.00,
            rightMachineAvgCYL: 0.00,
            leftMachineAvgCYL:  0.00,
            rightMachineAvgAX: 180,
            leftMachineAvgAX:  180,
            photoIndex: 0
        )
        let p2 = makeResult(
            rightSPHs: [-1.00],
            leftSPHs:  [-1.00],
            rightMachineAvgSPH: -1.00,
            leftMachineAvgSPH:  -1.00,
            rightMachineAvgCYL: -0.75,
            leftMachineAvgCYL:  -0.75,
            rightMachineAvgAX: 95,
            leftMachineAvgAX:  95,
            photoIndex: 1
        )
        let outcome = ConsistencyValidator().validate([p1, p2])
        if case .inconsistentAddPhoto(let reason, _) = outcome {
            XCTAssertTrue(reason.contains("cylinder"), "Reason should reference cylinder, got: \(reason)")
            XCTAssertFalse(reason.contains("axis"), "Reason must not reference axis when CYL fails first, got: \(reason)")
        } else {
            XCTFail("Expected .inconsistentAddPhoto on CYL diff, got \(outcome)")
        }
    }

    func testSignMismatchSkippedWhenOneEyeBlind() {
        let rRight = [RawReading(id: UUID(), sph: +1.50, cyl: -0.50, ax: 90, eye: .right, sourcePhotoIndex: 0)]
        let right = EyeReading(id: UUID(), eye: .right, readings: rRight, machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: 0, machineType: .handheld)
        let p1 = PrintoutResult(rightEye: right, leftEye: nil, pd: nil, machineType: .handheld, sourcePhotoIndex: 0, rawText: "")
        let rRight2 = [RawReading(id: UUID(), sph: +1.75, cyl: -0.50, ax: 90, eye: .right, sourcePhotoIndex: 1)]
        let right2 = EyeReading(id: UUID(), eye: .right, readings: rRight2, machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: 1, machineType: .handheld)
        let p2 = PrintoutResult(rightEye: right2, leftEye: nil, pd: nil, machineType: .handheld, sourcePhotoIndex: 1, rawText: "")
        let outcome = ConsistencyValidator().validate([p1, p2])
        assertConsistent(outcome)
    }
}
