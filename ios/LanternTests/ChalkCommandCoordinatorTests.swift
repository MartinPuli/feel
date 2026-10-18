import XCTest
@testable import Lantern

private final class FakeCommandTransport: ChalkCommandTransporting {
    var requests: [ChalkRequest] = []
    var feedbackCalls = 0
    var deleted: [String] = []
    var beforeReply: (() -> Void)?
    var action: ChalkDecision.Action = .recall
    var delayNanoseconds: UInt64 = 0
    func interpret(_ request: ChalkRequest, endpoint: String, token: String) async throws -> ChalkResponse {
        requests.append(request)
        if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
        beforeReply?()
        return ChalkResponse(requestId: request.requestId, sessionId: request.sessionId,
            decision: ChalkDecision(action: action, placeId: action == .recall ? "a" : nil,
                                    name: nil, message: "Entrance selected."), traceId: "trace", latencyMs: 20)
    }
    func feedback(traceId: String, sessionId: String, correct: Bool, correctedPlaceId: String?,
                  endpoint: String, token: String) async throws -> ChalkFeedbackResponse {
        feedbackCalls += 1
        return ChalkFeedbackResponse(recorded: true, aliasSaved: correctedPlaceId != nil, actionExecuted: false)
    }
    func deleteSession(_ sessionId: String, endpoint: String, token: String) async throws { deleted.append(sessionId) }
}

@MainActor
final class ChalkCommandCoordinatorTests: XCTestCase {
    private func snapshot(session: String = "session", tracking: Bool = true) -> ChalkCommandSnapshot {
        ChalkCommandSnapshot(sessionId: session, context: ChalkContext(places: [ChalkPlace(id: "a", name: "Entrance")],
            trackingValid: tracking, restoring: false, mode: "live", hasReturnPoint: false))
    }
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ChalkCoordinatorTests.\(UUID().uuidString)")!
    }
    private func coordinator(_ transport: FakeCommandTransport, storage: UserDefaults? = nil,
                             now: @escaping () -> TimeInterval = { 1 }) -> ChalkCommandCoordinator {
        let result = ChalkCommandCoordinator(transport: transport, defaults: storage ?? defaults(),
            readToken: { String(repeating: "x", count: 32) }, writeToken: { _ in true }, now: now)
        result.endpoint = "https://feel.example"
        result.sharingEnabled = true
        result.captureContext = { self.snapshot() }
        return result
    }
    private func drain() async {
        // Tasks inherit the main actor; yielding lets the fake transport complete.
        for _ in 0..<10 { await Task.yield() }
    }
    func testSharingAndRetentionDefaultOff() {
        let transport = FakeCommandTransport()
        let coordinator = ChalkCommandCoordinator(transport: transport, defaults: defaults(),
            readToken: { "" }, writeToken: { _ in true })
        XCTAssertFalse(coordinator.sharingEnabled)
        XCTAssertFalse(coordinator.retentionEnabled)
        coordinator.submit("Recall entrance")
        XCTAssertFalse(coordinator.isBusy)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testStopNeedsNoCloudConfigurationOrCamera() {
        let transport = FakeCommandTransport()
        let coordinator = ChalkCommandCoordinator(transport: transport, defaults: defaults(),
            readToken: { "" }, writeToken: { _ in true })
        var applied: ChalkDecision.Action?
        coordinator.applyDecision = { applied = $0.action; return "Stopped." }
        coordinator.submit("Stop!")
        XCTAssertEqual(applied, .stop)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testValidReplyAppliesOnceAndFeedbackDoesNotExecuteAgain() async {
        let transport = FakeCommandTransport()
        let sut = self.coordinator(transport)
        var applied = 0
        sut.applyDecision = { _ in applied += 1; return "Selected locally." }
        sut.submit("Find entrance")
        await drain()
        XCTAssertEqual(applied, 1)
        XCTAssertTrue(sut.canGiveFeedback)
        XCTAssertFalse(transport.requests[0].consent)
        XCTAssertTrue(sut.correctionPlaces.isEmpty)
        sut.submitFeedback(correct: true)
        await drain()
        XCTAssertEqual(transport.feedbackCalls, 1)
        XCTAssertEqual(applied, 1)
        XCTAssertFalse(sut.canGiveFeedback)
    }
    func testContextOrSessionChangesRejectReply() async {
        for change in [snapshot(session: "new"), snapshot(tracking: false)] {
            let transport = FakeCommandTransport()
            let coordinator = self.coordinator(transport)
            var applied = false
            coordinator.applyDecision = { _ in applied = true; return "Applied." }
            transport.beforeReply = { coordinator.captureContext = { change } }
            coordinator.submit("Find entrance")
            await drain()
            XCTAssertFalse(applied)
            XCTAssertFalse(coordinator.canGiveFeedback)
            XCTAssertTrue(coordinator.status.contains("session changed"))
        }
    }
    func testExpiredReplyIsNotApplied() async {
        let transport = FakeCommandTransport()
        var time: TimeInterval = 1
        let sut = coordinator(transport, now: { time })
        var applied = false
        sut.applyDecision = { _ in applied = true; return "Applied." }
        transport.beforeReply = { time = 6 }
        sut.submit("Find entrance")
        await drain()
        XCTAssertFalse(applied)
        XCTAssertFalse(sut.isBusy)
    }
    func testCancellationRejectsTransportThatStillReturns() async {
        let transport = FakeCommandTransport()
        let coordinator = self.coordinator(transport)
        var applied = false
        coordinator.applyDecision = { _ in applied = true; return "Applied." }
        transport.beforeReply = { coordinator.cancel(reason: "Tracking lost.") }
        coordinator.submit("Find entrance")
        await drain()
        XCTAssertFalse(applied)
        XCTAssertEqual(coordinator.status, "Tracking lost.")
    }
    func testDeadlineCancelsARequestBeforeTransportCompletes() async {
        let transport = FakeCommandTransport()
        transport.delayNanoseconds = 5_000_000_000
        let sut = ChalkCommandCoordinator(transport: transport, defaults: defaults(),
            readToken: { String(repeating: "x", count: 32) }, writeToken: { _ in true }, freshness: 0.02)
        sut.endpoint = "https://feel.example"; sut.sharingEnabled = true
        sut.captureContext = { self.snapshot() }
        var applied = false
        sut.applyDecision = { _ in applied = true; return "Applied." }
        sut.submit("Find entrance")
        let expired = expectation(description: "bounded deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { expired.fulfill() }
        await fulfillment(of: [expired], timeout: 1)
        XCTAssertFalse(sut.isBusy)
        XCTAssertFalse(applied)
        XCTAssertTrue(sut.status.contains("took too long"))
    }

    func testConsentedCorrectionIsLimitedToOriginalPlaces() async {
        let transport = FakeCommandTransport()
        let coordinator = self.coordinator(transport)
        coordinator.retentionEnabled = true
        coordinator.submit("Find entrance")
        await drain()
        XCTAssertTrue(transport.requests[0].consent)
        XCTAssertEqual(coordinator.correctionPlaces.map(\.id), ["a"])
        coordinator.submitFeedback(correct: false, correctedPlaceId: "invented")
        await drain()
        XCTAssertEqual(transport.feedbackCalls, 0)
        coordinator.submitFeedback(correct: false, correctedPlaceId: "a")
        await drain()
        XCTAssertEqual(transport.feedbackCalls, 1)
    }
    func testHistoryDeletionSurvivesCoordinatorRecreationAndDoesNotNeedSharing() async {
        let storage = defaults(), transport = FakeCommandTransport()
        let first = coordinator(transport, storage: storage)
        first.submit("Find entrance")
        await drain()
        XCTAssertEqual(first.historySessionCount, 1)
        let next = coordinator(transport, storage: storage)
        next.sharingEnabled = false
        next.deleteHistory()
        await drain()
        XCTAssertEqual(transport.deleted, ["session"])
        XCTAssertEqual(next.historySessionCount, 0)
        XCTAssertFalse(next.canGiveFeedback)
    }
}
