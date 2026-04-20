import XCTest
@testable import HICOR

final class PowerVectorTests: XCTestCase {

    private let tol = 1e-6

    // MARK: - toM (spherical equivalent)

    func testToM_standardReading_equalsSphPlusHalfCyl() {
        XCTAssertEqual(PowerVector.toM(sph: -2.00, cyl: -1.00), -2.50, accuracy: tol)
        XCTAssertEqual(PowerVector.toM(sph: +1.00, cyl: -0.50), +0.75, accuracy: tol)
        XCTAssertEqual(PowerVector.toM(sph: 0.00, cyl: 0.00), 0.00, accuracy: tol)
    }

    // MARK: - J0 / J45 for a known angle

    func testToJ0_axis90_usesCosine180() {
        // At axis 90°, 2α = 180°; cos(180°) = -1.
        // J0 = -cyl/2 * cos(180°) = cyl/2 = -0.50 for cyl=-1.00.
        XCTAssertEqual(PowerVector.toJ0(cyl: -1.00, axDegrees: 90), -0.50, accuracy: tol)
    }

    func testToJ45_axis90_isZero() {
        XCTAssertEqual(PowerVector.toJ45(cyl: -1.00, axDegrees: 90), 0.0, accuracy: tol)
    }

    func testToJ0_axis45_isZero() {
        // At axis 45°, 2α = 90°; cos(90°) = 0.
        XCTAssertEqual(PowerVector.toJ0(cyl: -1.00, axDegrees: 45), 0.0, accuracy: tol)
    }

    func testToJ45_axis45_capturesFullCyl() {
        // At axis 45°, 2α = 90°; sin(90°) = 1; J45 = -cyl/2.
        XCTAssertEqual(PowerVector.toJ45(cyl: -1.00, axDegrees: 45), 0.50, accuracy: tol)
    }

    // MARK: - Round-trip (sph, cyl, ax) → vectors → back

    func testReconstruct_roundtrip_standardReading() {
        let (sph, cyl, ax) = roundTrip(sph: -2.00, cyl: -1.00, ax: 90)
        XCTAssertEqual(sph, -2.00, accuracy: 1e-6)
        XCTAssertEqual(cyl, -1.00, accuracy: 1e-6)
        XCTAssertEqual(ax, 90)
    }

    func testReconstruct_roundtrip_highMinus() {
        let (sph, cyl, ax) = roundTrip(sph: -3.50, cyl: -2.25, ax: 45)
        XCTAssertEqual(sph, -3.50, accuracy: 1e-6)
        XCTAssertEqual(cyl, -2.25, accuracy: 1e-6)
        XCTAssertEqual(ax, 45)
    }

    func testReconstruct_roundtrip_positiveSph() {
        let (sph, cyl, ax) = roundTrip(sph: +1.00, cyl: -0.50, ax: 135)
        XCTAssertEqual(sph, +1.00, accuracy: 1e-6)
        XCTAssertEqual(cyl, -0.50, accuracy: 1e-6)
        XCTAssertEqual(ax, 135)
    }

    func testReconstruct_roundtrip_axisNear180_preservesAxis() {
        // Axis circularity — 179° must not collapse toward 90°.
        let (_, _, ax) = roundTrip(sph: -2.00, cyl: -1.00, ax: 179)
        XCTAssertEqual(ax, 179)
    }

    func testReconstruct_roundtrip_axisNear0_preservesAxis() {
        let (_, _, ax) = roundTrip(sph: -2.00, cyl: -1.00, ax: 1)
        XCTAssertEqual(ax, 1)
    }

    func testReconstruct_roundtrip_axis180_normalizesToHicorConvention() {
        // HICOR normalizes axis to the (0, 180] range (1..180); 180° stays 180,
        // not 0, so it survives the RawReading 1-180 clamp used downstream.
        let (_, _, ax) = roundTrip(sph: -2.00, cyl: -1.00, ax: 180)
        XCTAssertEqual(ax, 180)
    }

    func testReconstruct_zeroCyl_preservesSphAndCyl() {
        let result = PowerVector.reconstruct(
            m: PowerVector.toM(sph: -3.00, cyl: 0.0),
            j0: PowerVector.toJ0(cyl: 0.0, axDegrees: 90),
            j45: PowerVector.toJ45(cyl: 0.0, axDegrees: 90)
        )
        XCTAssertEqual(result.sph, -3.00, accuracy: 1e-6)
        XCTAssertEqual(result.cyl, 0.0, accuracy: 1e-6)
        // Axis is meaningless when cyl = 0 — any value is clinically equivalent —
        // but the reconstruction should produce a valid axis in (0, 180] so
        // downstream consumers never see 0 or negative.
        XCTAssertGreaterThan(result.ax, 0)
        XCTAssertLessThanOrEqual(result.ax, 180)
    }

    // MARK: - Averaging axis across two readings that straddle 0/180°

    func testReconstructedAxisFromVectorMean_straddling179And1_doesNotCollapseTo90() {
        // Two readings at 179° and 1° should average to near 0°/180°, NOT 90°.
        // Simple arithmetic mean gives (179 + 1)/2 = 90, which is clinically
        // wrong (180° and 0° are the same axis). Thibos J0/J45 averaging fixes
        // this.
        let a_j0 = PowerVector.toJ0(cyl: -1.00, axDegrees: 179)
        let a_j45 = PowerVector.toJ45(cyl: -1.00, axDegrees: 179)
        let b_j0 = PowerVector.toJ0(cyl: -1.00, axDegrees: 1)
        let b_j45 = PowerVector.toJ45(cyl: -1.00, axDegrees: 1)
        let meanM = PowerVector.toM(sph: -2.00, cyl: -1.00)
        let meanJ0 = (a_j0 + b_j0) / 2.0
        let meanJ45 = (a_j45 + b_j45) / 2.0
        let recon = PowerVector.reconstruct(m: meanM, j0: meanJ0, j45: meanJ45)
        // Expect axis within 2° of 180° (or equivalently 0°), not 90°.
        let distFrom180 = min(abs(recon.ax - 180), abs(recon.ax - 0))
        XCTAssertLessThanOrEqual(distFrom180, 2, "axis circularity failed: got \(recon.ax)")
        XCTAssertGreaterThan(abs(recon.ax - 90), 85, "axis collapsed toward 90° — power-vector averaging broken")
    }
}

// MARK: - Helpers

private func roundTrip(sph: Double, cyl: Double, ax: Int) -> (sph: Double, cyl: Double, ax: Int) {
    let m = PowerVector.toM(sph: sph, cyl: cyl)
    let j0 = PowerVector.toJ0(cyl: cyl, axDegrees: ax)
    let j45 = PowerVector.toJ45(cyl: cyl, axDegrees: ax)
    return PowerVector.reconstruct(m: m, j0: j0, j45: j45)
}
