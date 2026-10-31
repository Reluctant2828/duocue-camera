import XCTest
@testable import DuoCue

@MainActor
final class DeferredRotationTests: XCTestCase {
    func testPreviewMutationWaitsUntilLayoutCallbackHasReturned() async {
        let queue = DeferredRotationUpdates()
        let applied = expectation(description: "deferred preview update")
        var insideLayout = true
        var received: CGFloat?
        queue.enqueue(270) { angle in
            XCTAssertFalse(insideLayout, "Updating the capture connection inside layout can re-enter framework locks")
            received = angle
            applied.fulfill()
        }
        XCTAssertNil(received)
        insideLayout = false
        await fulfillment(of: [applied], timeout: 2)
        XCTAssertEqual(received, 270)
    }

    func testRapidRotationEventsApplyOnlyTheLatestAngle() async {
        let queue = DeferredRotationUpdates()
        let applied = expectation(description: "latest rotation only")
        var received: [CGFloat] = []
        let angles: [CGFloat] = [0, 90, 180, 270]
        for angle in angles {
            queue.enqueue(angle) { received.append($0); applied.fulfill() }
        }
        await fulfillment(of: [applied], timeout: 2)
        XCTAssertEqual(received, [270])
    }

    func testDisconnectInvalidatesQueuedWorkWithoutDroppingReplacementPreview() async {
        let queue = DeferredRotationUpdates()
        let applied = expectation(description: "replacement preview")
        var received: [CGFloat] = []
        queue.enqueue(180) { received.append($0) }
        queue.invalidate()
        queue.enqueue(90) { received.append($0); applied.fulfill() }
        await fulfillment(of: [applied], timeout: 2)
        XCTAssertEqual(received, [90])
    }

    func testReentrantRotationSchedulesNextTurnInsteadOfNesting() async {
        let queue = DeferredRotationUpdates()
        let applied = expectation(description: "reentrant notification completed")
        var inFirstUpdate = false
        queue.enqueue(90) { _ in
            inFirstUpdate = true
            queue.enqueue(180) { angle in
                XCTAssertFalse(inFirstUpdate)
                XCTAssertEqual(angle, 180)
                applied.fulfill()
            }
            inFirstUpdate = false
        }
        await fulfillment(of: [applied], timeout: 2)
    }
}
