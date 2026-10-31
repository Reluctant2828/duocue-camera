import XCTest
@testable import DuoCue

final class RecordingRequestStateTests: XCTestCase {
    func testStoppedPermissionRequestCannotStartRecordingAfterCameraRestart() throws {
        var state = RecordingRequestState()
        let oldRequest = try XCTUnwrap(state.beginPreparation())
        state.cancelPreparation()
        XCTAssertFalse(state.finishPreparation(oldRequest))
        XCTAssertNil(state.preparationID)
    }

    func testDelayedOldPermissionDoesNotConsumeNewRecordingRequest() throws {
        var state = RecordingRequestState()
        let oldRequest = try XCTUnwrap(state.beginPreparation())
        state.cancelPreparation()
        let newRequest = try XCTUnwrap(state.beginPreparation())

        XCTAssertFalse(state.finishPreparation(oldRequest))
        XCTAssertEqual(state.preparationID, newRequest)
        XCTAssertTrue(state.finishPreparation(newRequest))
        XCTAssertNil(state.preparationID)
    }

    func testRapidRecordTapsReserveOnlyOnePreparation() throws {
        var state = RecordingRequestState()
        let request = try XCTUnwrap(state.beginPreparation())
        XCTAssertNil(state.beginPreparation())
        XCTAssertTrue(state.finishPreparation(request))
        XCTAssertFalse(state.finishPreparation(request))
    }
}
