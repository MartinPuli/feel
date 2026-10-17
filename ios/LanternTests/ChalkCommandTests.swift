import XCTest
import FeelCore
@testable import Lantern

private final class ChalkStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int,Data,TimeInterval))?
    private var cancelled=false
    private let lock=NSLock()
    override class func canInit(with request:URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        do {
            let (status,data,delay)=try Self.handler!(request)
            DispatchQueue.global().asyncAfter(deadline:.now()+delay) { [self] in
                lock.lock(); let stopped=cancelled; lock.unlock()
                guard !stopped else { return }
                client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
                client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
            }
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() { lock.lock(); cancelled=true; lock.unlock() }
}
@MainActor
final class ChalkCommandTests:XCTestCase {
    private func makeModel() -> LanternModel {
        let config=URLSessionConfiguration.ephemeral; config.protocolClasses=[ChalkStub.self]
        let model=LanternModel(cloudTransport:ChalkTransport(session:URLSession(configuration:config)),cloudToken:"test-app-token")
        model.startSimulation(memory:true); model.placeName="Entrance"; model.remember()
        model.simulateMove(metres:-2)
        model.cloudEndpoint="https://feel.example"; model.cloudSharing=true; model.cloudEnabled=true
        return model
    }
    nonisolated private static func body(_ request:URLRequest) throws -> [String:Any] {
        if let data=request.httpBody { return try JSONSerialization.jsonObject(with:data) as! [String:Any] }
        let stream=request.httpBodyStream!; stream.open(); defer { stream.close() }
        var data=Data(); var buffer=[UInt8](repeating:0,count:4096)
        while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count); if n<=0 { break }; data.append(buffer,count:n) }
        return try JSONSerialization.jsonObject(with:data) as! [String:Any]
    }
    nonisolated private static func reply(_ request:URLRequest,action:String="recall",id:String?=nil,name:String?=nil,delay:Double=0) throws -> (Int,Data,TimeInterval) {
        let input=try Self.body(request)
        let response:[String:Any]=["request_id":input["request_id"]!,"session_id":input["session_id"]!,
            "trace_id":"trace-test","latency_ms":12,
            "decision":["action":action,"place_id":id as Any? ?? NSNull(),"name":name as Any? ?? NSNull(),"message":"Selected entrance"]]
        return (200,try JSONSerialization.data(withJSONObject:response),delay)
    }
    private func send(_ model:LanternModel) { model.commandText="Take me back where we entered"; model.submitTypedCommand() }
    private func settle(_ model:LanternModel) async {
        for _ in 0..<260 { if !model.cloudPending { return }; try? await Task.sleep(nanoseconds:20_000_000) }
        XCTFail("Cloud request did not settle")
    }
    func testRecallUsesExistingPlaceAndExplicitRetentionConsent() async {
        let model=makeModel(); defer { model.stop() }; let id=model.spatialMemory.bookmarks[0].id
        ChalkStub.handler={ request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer test-app-token")
            let payload=try Self.body(request); XCTAssertEqual(payload["consent"] as? Bool,false)
            let context=payload["context"] as! [String:Any]; XCTAssertNil(context["coordinates"])
            return try Self.reply(request,id:id)
        }
        send(model); await settle(model)
        XCTAssertEqual(model.spatialMemory.activeID,id); XCTAssertEqual(model.packet.highlight,3)
        XCTAssertFalse(model.cloudFeedbackAvailable); XCTAssertNotNil(model.cloudLatency)
    }
    func testUnknownPlaceCannotMoveOrSelect() async {
        let model=makeModel(); defer { model.stop() }
        ChalkStub.handler={ try Self.reply($0,id:"not-in-current-session") }
        send(model); await settle(model)
        XCTAssertNil(model.spatialMemory.activeID); XCTAssertTrue(model.cloudNotice.contains("No cloud action"))
    }
    func testStopImmediatelyCancelsDelayedReply() async {
        let model=makeModel(); let id=model.spatialMemory.bookmarks[0].id
        ChalkStub.handler={ try Self.reply($0,id:id,delay:0.2) }
        send(model); try? await Task.sleep(nanoseconds:30_000_000)
        model.commandText="stop"; model.submitTypedCommand()
        XCTAssertEqual(model.mode,.stopped); XCTAssertFalse(model.cloudPending)
        try? await Task.sleep(nanoseconds:300_000_000)
        XCTAssertNil(model.spatialMemory.activeID); XCTAssertEqual(model.packet.bands,[0,0,0,0,0,0,0])
        XCTAssertEqual(model.commandNotice,"Stopped. Guidance is neutral.")
    }
    func testSessionReplacementAndManualSelectionCancelReply() async {
        let model=makeModel(); defer { model.stop() }; let id=model.spatialMemory.bookmarks[0].id
        ChalkStub.handler={ try Self.reply($0,id:id,delay:0.2) }
        send(model); try? await Task.sleep(nanoseconds:30_000_000); model.resetSimulatedSession()
        try? await Task.sleep(nanoseconds:250_000_000)
        XCTAssertNil(model.spatialMemory.activeID); XCTAssertTrue(model.spatialMemory.bookmarks.isEmpty)
        model.placeName="New place"; model.remember(); let newID=model.spatialMemory.bookmarks[0].id
        ChalkStub.handler={ try Self.reply($0,id:newID,delay:0.2) }
        send(model); try? await Task.sleep(nanoseconds:30_000_000); model.selectPlace(newID)
        try? await Task.sleep(nanoseconds:250_000_000)
        XCTAssertNil(model.spatialMemory.activeID); XCTAssertFalse(model.cloudPending)
    }
    func testTrackingLostWhileWaitingRejectsGuidance() async {
        let model=makeModel(); defer { model.stop() }; let id=model.spatialMemory.bookmarks[0].id
        ChalkStub.handler={ try Self.reply($0,id:id,delay:0.1) }
        send(model); model.simulatedTracking=false; await settle(model)
        XCTAssertNil(model.spatialMemory.activeID); XCTAssertTrue(model.cloudNotice.contains("Tracking"))
    }
    func testServerFailureAndSharingOffDoNotFallbackToAction() async {
        let model=makeModel(); defer { model.stop() }
        ChalkStub.handler={ _ in (503,Data(),0) }; send(model); await settle(model)
        XCTAssertNil(model.spatialMemory.activeID); XCTAssertTrue(model.cloudNotice.contains("No cloud action"))
        model.cloudSharing=false
        ChalkStub.handler={ _ in XCTFail("Sharing disabled must not send"); return (200,Data(),0) }
        send(model); XCTAssertFalse(model.cloudPending); XCTAssertNil(model.spatialMemory.activeID)
    }
    func testRememberRejectsMovementDuringNetworkRequest() async {
        let model=makeModel(); defer { model.stop() }
        ChalkStub.handler={ try Self.reply($0,action:"remember",name:"Desk",delay:0.1) }
        send(model); model.simulateMove(metres:0.5); await settle(model)
        XCTAssertEqual(model.spatialMemory.bookmarks.count,1)
        XCTAssertTrue(model.cloudNotice.contains("You moved"))
    }
    func testExpiredReplyDoesNotRun() async {
        let model=makeModel(); defer { model.stop() }; let id=model.spatialMemory.bookmarks[0].id
        ChalkStub.handler={ try Self.reply($0,id:id,delay:4.1) }
        send(model); await settle(model)
        XCTAssertNil(model.spatialMemory.activeID); XCTAssertTrue(model.cloudNotice.contains("too late"))
    }
    func testMalformedDecisionsAndMismatchedRequestAreRejected() async {
        let model=makeModel(); defer { model.stop() }
        for variant in ["unknown-action","missing-message","wrong-request"] {
            ChalkStub.handler={ request in
                let (_,data,_)=try Self.reply(request,action:"list_places")
                var result=try JSONSerialization.jsonObject(with:data) as! [String:Any]
                var decision=result["decision"] as! [String:Any]
                if variant == "unknown-action" { decision["action"]="raw_pwm" }
                if variant == "missing-message" { decision.removeValue(forKey:"message") }
                if variant == "wrong-request" { result["request_id"]="other-request" }
                result["decision"]=decision
                return (200,try JSONSerialization.data(withJSONObject:result),0)
            }
            send(model); await settle(model)
            XCTAssertNil(model.spatialMemory.activeID); XCTAssertTrue(model.cloudNotice.contains("No cloud action"))
        }
    }
    func testLanguageChangeCancelsAndReturnPointUsesLocalPoint() async {
        let model=makeModel(); defer { model.stop() }
        model.setReturnPoint()
        ChalkStub.handler={ request in
            let payload=try Self.body(request); let context=payload["context"] as! [String:Any]
            XCTAssertEqual(context["has_return_point"] as? Bool,true)
            return try Self.reply(request,action:"return_to_point",delay:0.1)
        }
        send(model); model.commandLanguage = .es
        try? await Task.sleep(nanoseconds:200_000_000)
        XCTAssertNil(model.spatialMemory.activeID)
        send(model); await settle(model)
        XCTAssertEqual(model.spatialMemory.activeID,SpatialMemoryManager.returnID)
    }
    func testNetworkTimeoutAndConsentRevocationLeaveGuidanceUnchanged() async {
        let model=makeModel(); defer { model.stop() }; let id=model.spatialMemory.bookmarks[0].id
        ChalkStub.handler={ _ in throw URLError(.timedOut) }
        send(model); await settle(model); XCTAssertNil(model.spatialMemory.activeID)
        ChalkStub.handler={ try Self.reply($0,id:id,delay:0.1) }
        send(model); model.cloudSharing=false
        try? await Task.sleep(nanoseconds:200_000_000)
        XCTAssertFalse(model.cloudPending); XCTAssertNil(model.spatialMemory.activeID)
    }
    func testFeedbackRequiresPositiveReceipt() async {
        let model=makeModel(); defer { model.stop() }; model.cloudFeedbackConsent=true
        ChalkStub.handler={ try Self.reply($0,action:"clarify") }
        send(model); await settle(model)
        ChalkStub.handler={ _ in (200,Data("{\"recorded\":false}".utf8),0) }
        model.sendCloudFeedback(correct:true)
        for _ in 0..<50 {
            if model.cloudFeedbackAvailable { break }
            try? await Task.sleep(nanoseconds:20_000_000)
        }
        XCTAssertTrue(model.cloudFeedbackAvailable); XCTAssertTrue(model.cloudNotice.contains("could not be saved"))
    }
    func testFeedbackHasSessionAndDoesNotExecuteCorrection() async {
        let model=makeModel(); defer { model.stop() }; let id=model.spatialMemory.bookmarks[0].id
        model.cloudFeedbackConsent=true
        ChalkStub.handler={ try Self.reply($0,action:"clarify") }
        send(model); await settle(model); XCTAssertTrue(model.cloudFeedbackAvailable)
        model.cloudCorrectedPlace=id
        let sent=expectation(description:"Feedback sent")
        let session=model.spatialMemory.session
        ChalkStub.handler={ request in
            XCTAssertEqual(request.url?.path,"/v1/feedback")
            let payload=try Self.body(request)
            XCTAssertEqual(payload["session_id"] as? String,session)
            XCTAssertEqual(payload["corrected_place_id"] as? String,id)
            XCTAssertEqual(payload["outcome"] as? String,"incorrect")
            sent.fulfill(); return (200,Data("{\"recorded\":true}".utf8),0)
        }
        model.sendCloudFeedback(correct:false); await fulfillment(of:[sent],timeout:1)
        XCTAssertNil(model.spatialMemory.activeID)
    }
}
