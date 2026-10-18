import XCTest
import FeelCore
@testable import Lantern

@MainActor
final class CloudContextIntegrationTests: XCTestCase {
    private final class Query: ChalkQuerying {
        var isEnabled = false
        var identity = UUID()
        var sessionIdentity: UUID? { isEnabled ? identity : nil }
        var pending: ((Result<[String:Any],ChalkQueryError>) -> Void)?
        var calls = 0
        func setEnabled(_ enabled: Bool) { isEnabled = enabled; identity = UUID() }
        func cancelAll() {}
        func query(_ operation: ChalkContextRequest, completion: @escaping (Result<[String:Any],ChalkQueryError>) -> Void) { calls += 1; pending = completion }
        func complete() { pending?(.success(["object_history.spoken":"Keys were last confirmed at the fixture desk."])) }
    }
    private func fixture() -> (LanternModel, Query) {
        let query = Query()
        let model = LanternModel(voice: RealtimeVoiceSession(configuration:nil,speaksLocally:false),
                                 chalkStore:MemoryChalkStore(), localFinder:StubLocalFinder(), uploader:nil, chalkQuery:query)
        model.voice.setSpokenOutput(false)
        return (model,query)
    }
    func testReadConsentIsIndependentOfUploadConsentAndRequiredForHistory() {
        let (model,query) = fixture()
        XCTAssertNotNil(model.performVoiceCommand(.lastSeen("keys"))["error"])
        XCTAssertEqual(query.calls,0)
        XCTAssertNil(model.performVoiceCommand(.setContextReads(true))["error"])
        XCTAssertFalse(model.memoryUploadsEnabled)
        XCTAssertEqual(model.performVoiceCommand(.lastSeen("keys"))["pending"] as? Bool,true)
        query.complete(); XCTAssertEqual(model.lastSeenNotice,"Keys were last confirmed at the fixture desk.")
        XCTAssertFalse(model.voice.spokenOutputEnabled)
    }
    func testStopNewCommandAndLocalCaptureEachDiscardLateHistory() {
        for action in 0..<3 {
            let (model,query) = fixture(); _ = model.performVoiceCommand(.setContextReads(true))
            _ = model.performVoiceCommand(.lastSeen("keys"))
            if action == 0 { model.stop() }
            if action == 1 { _ = model.performVoiceCommand(.status) }
            if action == 2 { model.localVoice.onCaptureWillStart?() }
            query.complete(); XCTAssertNil(model.lastSeenNotice)
        }
    }
    func testAccountSwitchAndConsentWithdrawalDiscardHistoryAndClearCachedNotice() {
        for action in 0..<2 {
            let (model,query) = fixture(); _ = model.performVoiceCommand(.setContextReads(true))
            _ = model.performVoiceCommand(.lastSeen("keys"))
            if action == 0 { query.identity = UUID(); _ = model.voiceSnapshot() }
            else { _ = model.performVoiceCommand(.setContextReads(false)) }
            query.complete(); XCTAssertNil(model.lastSeenNotice)
        }
    }
    func testStrictVoiceToolsRejectCoercedConsentOrExtraIdentity() throws {
        XCTAssertEqual(try VoiceCommand.decode(name:"last_seen",arguments:#"{"object":"keys"}"#),.lastSeen("keys"))
        XCTAssertEqual(try VoiceCommand.decode(name:"set_context_reads",arguments:#"{"enabled":true}"#),.setContextReads(true))
        XCTAssertThrowsError(try VoiceCommand.decode(name:"set_context_reads",arguments:#"{"enabled":1}"#))
        XCTAssertThrowsError(try VoiceCommand.decode(name:"last_seen",arguments:#"{"object":"keys","user_id":"another"}"#))
    }
}
