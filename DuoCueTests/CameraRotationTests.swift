import XCTest
@testable import DuoCue

final class CameraRotationTests: XCTestCase {
    func testCaptureWaitsForInitialSensorAngleInsteadOfAssumingPortrait90() {
        var state = CaptureRotationState()
        XCTAssertNil(state.latestAngle)
        XCTAssertNil(state.beginRecording())
        XCTAssertFalse(state.isRecording)

        state.update(270)
        XCTAssertEqual(state.beginRecording(), 270)
    }

    func testMovieRetainsItsStartingTransformWhileNextMovieUsesLatestAngle() {
        var state = CaptureRotationState()
        state.update(180)
        XCTAssertEqual(state.beginRecording(), 180)
        state.update(0)
        XCTAssertEqual(state.latestAngle, 0)
        XCTAssertEqual(state.movieAngle, 180)

        state.finishRecording()
        XCTAssertEqual(state.movieAngle, 0)
        XCTAssertEqual(state.beginRecording(), 0)
    }

    func testSensorSpecificAngleIsPreservedWithoutAnOrientationLookupTable() {
        var state = CaptureRotationState()
        XCTAssertTrue(state.update(271.5))
        XCTAssertEqual(state.latestAngle, 271.5)
        XCTAssertEqual(state.beginRecording(), 271.5)
        XCTAssertNil(state.beginRecording())
    }

    func testInvalidCoordinatorValueCannotReplaceLastGoodCaptureAngle() {
        var state = CaptureRotationState()
        state.update(90)
        XCTAssertFalse(state.update(.nan))
        XCTAssertFalse(state.update(.infinity))
        XCTAssertEqual(state.latestAngle, 90)
    }
}
