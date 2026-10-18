import XCTest
@testable import Lantern

final class AuthenticatedVoiceTests: XCTestCase {
    private var store: KeychainStore<AuthSessionTokens>!
    private let production = VoiceConfiguration(endpoint: "https://voice.example/session", authMode: .supabase)
    private let user = "11111111-1111-4111-8111-111111111111"
    private let sessionID = "22222222-2222-4222-8222-222222222222"
    override func setUp() { store = KeychainStore(service: "feel.voice.auth.tests." + UUID().uuidString, account: "fixture") }
    override func tearDown() { store.clear(); StubURLProtocol.handler = nil; StubURLProtocol.lastRequest = nil; StubURLProtocol.lastBody = nil }
    private func tokens(user: String? = nil, session: String? = "22222222-2222-4222-8222-222222222222", expiry: TimeInterval = Date().timeIntervalSince1970 + 3600, anonymous: Bool = false, refresh: String = "fixture-refresh") -> AuthSessionTokens {
        func part(_ value: [String:Any]) -> String {
            try! JSONSerialization.data(withJSONObject:value).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        }
        var claims: [String:Any] = ["sub":user ?? self.user,"role":"authenticated","exp":expiry,"is_anonymous":anonymous]
        if let session { claims["session_id"] = session }
        let value = part(["alg":"HS256"]) + "." + part(claims) + ".fixture"
        return AuthSessionTokens(accessToken:value,refreshToken:refresh,email:"fixture@example.com")
    }
    private func client() -> VoiceTokenClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        return VoiceTokenClient(store:store,session:URLSession(configuration:config))
    }
    private var reply: Data { try! JSONSerialization.data(withJSONObject:["value":"ephemeral-fixture","expires_at":Date().timeIntervalSince1970 + 300]) }

    func testOldDemoConfigurationDecodesButProductionNeverPersistsUserToken() throws {
        let old = #"{"endpoint":"https://voice.example/session","accessToken":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#
        XCTAssertEqual(try JSONDecoder().decode(VoiceConfiguration.self,from:Data(old.utf8)).authMode,.demo)
        XCTAssertTrue(production.isValid)
        XCTAssertEqual(production.accessToken,"")
        XCTAssertFalse(VoiceConfiguration(endpoint:production.endpoint,accessToken:tokens().accessToken,authMode:.supabase).isValid)
        let encoded = try JSONEncoder().encode(production)
        XCTAssertFalse(String(decoding:encoded,as:UTF8.self).contains("fixture-refresh"))
    }
    func testAuthoritativeBuildNeverFallsBackToSavedDemoOrUnknownMode() {
        let saved = VoiceConfiguration(endpoint:"https://old.example/session",accessToken:String(repeating:"a",count:32))
        let info: [String:Any] = ["FEEL_VOICE_AUTH_MODE":"supabase","FEEL_VOICE_ENDPOINT":production.endpoint,"FEEL_VOICE_ACCESS_TOKEN":"old-demo-code"]
        XCTAssertEqual(VoiceConfigurationStore.launchConfiguration(info:info,saved:saved),production)
        XCTAssertNil(VoiceConfigurationStore.launchConfiguration(info:["FEEL_VOICE_AUTH_MODE":"supabase"],saved:saved))
        XCTAssertNil(VoiceConfigurationStore.launchConfiguration(info:["FEEL_VOICE_AUTH_MODE":"unknown"],saved:saved))
        XCTAssertEqual(VoiceConfigurationStore.launchConfiguration(info:[:],saved:saved),saved)
    }
    func testMissingExpiredAndAnonymousCredentialsFailWithoutRequest() throws {
        let c = client()
        for value in [nil,tokens(expiry:0),tokens(anonymous:true)] {
            if let value { try store.save(value) } else { store.clear() }
            var failure: Error?
            c.fetch(production) { if case .failure(let error) = $0 { failure = error } }
            XCTAssertEqual(failure as? VoiceTokenClient.TokenError,.authentication)
            XCTAssertNil(StubURLProtocol.lastRequest)
        }
    }
    func testFetchUsesCurrentUserBearerAndEmptyRequestNotStoredDemoCode() throws {
        let current = tokens(); try store.save(current)
        let c = client(), done = expectation(description:"credential")
        let response = reply
        StubURLProtocol.handler = { request, body in
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer \(current.accessToken)")
            XCTAssertTrue(body == nil || body?.isEmpty == true)
            return (200,response)
        }
        c.fetch(production) { result in XCTAssertEqual(try? result.get(),"ephemeral-fixture"); done.fulfill() }
        wait(for:[done],timeout:3)
    }
    func testLateCredentialAfterSignOutAccountSwitchOrCancelIsNeverAccepted() throws {
        for change in 0..<3 {
            try store.save(tokens())
            let c = client(), started = expectation(description:"started"), done = expectation(description:"rejected")
            let release = DispatchSemaphore(value:0), response = reply
            StubURLProtocol.handler = { _, _ in started.fulfill(); _ = release.wait(timeout:.now()+3); return (200,response) }
            c.fetch(production) { result in
                if case .success = result { XCTFail("stale ephemeral credential accepted") }; done.fulfill()
            }
            wait(for:[started],timeout:2)
            if change == 0 { store.clear() }
            if change == 1 { try store.save(tokens(user:"33333333-3333-4333-8333-333333333333")) }
            if change == 2 { c.cancel() }
            release.signal(); wait(for:[done],timeout:3)
        }
    }
    func testPendingCredentialAcceptsSameSessionRefreshButRejectsNewSessionAndExpiry() throws {
        for scenario in 0..<5 {
            let original = tokens(session: scenario == 3 ? nil : sessionID)
            try store.save(original)
            let c = client(), started = expectation(description:"started"), done = expectation(description:"refresh result")
            let release = DispatchSemaphore(value:0), response = reply
            StubURLProtocol.handler = { _, _ in started.fulfill(); _ = release.wait(timeout:.now()+3); return (200,response) }
            c.fetch(production) { result in
                if scenario == 0 || scenario == 4 { XCTAssertEqual(try? result.get(),"ephemeral-fixture") }
                else {
                    if case .success = result { XCTFail("invalid or changed login session accepted") }
                }
                done.fulfill()
            }
            wait(for:[started],timeout:2)
            switch scenario {
            case 0: try store.save(tokens(expiry:Date().timeIntervalSince1970 + 7200,refresh:"rotated"))
            case 1: try store.save(tokens(session:"44444444-4444-4444-8444-444444444444",refresh:"new-login"))
            case 2: try store.save(tokens(expiry:0,refresh:"expired"))
            case 3: try store.save(tokens(session:nil,refresh:"legacy-rotated"))
            default: break // An unchanged token is still accepted.
            }
            release.signal(); wait(for:[done],timeout:3)
        }
    }
    func testLegacyIdentityCannotOutliveBearerReplacementAndMalformedSessionIsRejected() throws {
        let original = tokens(session:nil,expiry:Date().timeIntervalSince1970 + 3600)
        let replacement = tokens(session:nil,expiry:Date().timeIntervalSince1970 + 7200)
        XCTAssertNotNil(VoiceUserAuthentication.identity(original))
        XCTAssertNotEqual(VoiceUserAuthentication.identity(original),VoiceUserAuthentication.identity(replacement))
        var parts = tokens().accessToken.split(separator:".").map(String.init)
        let malformed: [String:Any] = ["sub":user,"role":"authenticated","exp":Date().timeIntervalSince1970 + 3600,"session_id":123]
        parts[1] = try JSONSerialization.data(withJSONObject:malformed).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        XCTAssertNil(VoiceUserAuthentication.identity(AuthSessionTokens(accessToken:parts.joined(separator:"."),refreshToken:"fixture",email:"fixture@example.com")))
    }
    func testRejectedDemoAccessCodeDoesNotAskForAccountSignIn() {
        for status in [401,403] {
            let c = client(), done = expectation(description:"demo rejection")
            StubURLProtocol.handler = { _, _ in (status,Data()) }
            let demo = VoiceConfiguration(endpoint:production.endpoint,accessToken:String(repeating:"a",count:32))
            c.fetch(demo) { result in
                if case .failure(let error) = result { XCTAssertEqual(error as? VoiceTokenClient.TokenError,.unavailable) }
                else { XCTFail("rejected demo code accepted") }
                done.fulfill()
            }
            wait(for:[done],timeout:3)
        }
    }
    func testProductionConnectionRequiresSignInBeforeMicrophonePermission() {
        var permissions = 0
        let voice = RealtimeVoiceSession(configuration:production,speaksLocally:false,bundleInfo:[:],userSession:{nil},requestPermission:{ _ in permissions += 1 })
        voice.start()
        XCTAssertEqual(voice.phase,.failed); XCTAssertEqual(permissions,0)
        XCTAssertTrue(voice.errorMessage.contains("Sign in"))
    }
    func testProductionBundleCannotBeOverriddenByExplicitDemoConfigurationOrSetup() {
        let demo = VoiceConfiguration(endpoint:"https://old.example/session",accessToken:String(repeating:"a",count:32))
        let voice = RealtimeVoiceSession(configuration:demo,speaksLocally:false,
            bundleInfo:["FEEL_VOICE_AUTH_MODE":"supabase","FEEL_VOICE_ENDPOINT":production.endpoint],userSession:{nil},requestPermission:{$0(true)})
        XCTAssertEqual(voice.configuration,production)
        XCTAssertThrowsError(try voice.saveConfiguration(endpoint:demo.endpoint,accessToken:demo.accessToken))
    }
    func testAccountChangeDuringPermissionOrEphemeralFetchNeverOpensSocket() {
        for duringPermission in [true,false] {
            var current: AuthSessionTokens? = tokens()
            var permission: ((Bool)->Void)?
            let token = AuthVoiceToken(), transport = AuthVoiceTransport(), audio = AuthVoiceAudio()
            let voice = RealtimeVoiceSession(tokenClient:token,audio:audio,transportFactory:{transport},configuration:production,speaksLocally:false,
                bundleInfo:[:],userSession:{current},requestPermission:{permission=$0})
            voice.start()
            if !duringPermission { permission?(true) }
            current = nil
            if duringPermission { permission?(true) } else { token.complete() }
            XCTAssertEqual(transport.opens,0); XCTAssertFalse(voice.isActive)
        }
    }
    func testLogoutStopsAudioAndRejectsFurtherToolCallsWhileTokenRefreshKeepsVoice() {
        var current: AuthSessionTokens? = tokens()
        let token = AuthVoiceToken(), transport = AuthVoiceTransport(), audio = AuthVoiceAudio()
        let voice = RealtimeVoiceSession(tokenClient:token,audio:audio,transportFactory:{transport},configuration:production,speaksLocally:false,
            bundleInfo:[:],userSession:{current},requestPermission:{$0(true)})
        var commands = 0; voice.onCommand = { _ in commands += 1; return [:] }
        voice.start(); token.complete()
        transport.onEvent?(["type":"session.created"]); transport.onEvent?(["type":"session.updated"])
        XCTAssertTrue(audio.running)
        current = tokens(expiry:Date().timeIntervalSince1970 + 7200,refresh:"rotated")
        XCTAssertTrue(voice.validateUserAuthentication()); XCTAssertTrue(voice.isActive)
        current = nil
        transport.onEvent?(["type":"response.function_call_arguments.done","call_id":"late","name":"stop","arguments":"{}"])
        XCTAssertEqual(commands,0); XCTAssertFalse(audio.running); XCTAssertFalse(voice.isActive); XCTAssertGreaterThan(transport.closes,0)
    }
    func testPauseDuringFetchRejectsEvenSuccessfulCredential() {
        let current = tokens(), token = AuthVoiceToken(), transport = AuthVoiceTransport()
        let voice = RealtimeVoiceSession(tokenClient:token,audio:AuthVoiceAudio(),transportFactory:{transport},configuration:production,speaksLocally:false,
            bundleInfo:[:],userSession:{current},requestPermission:{$0(true)})
        voice.start(); voice.pauseAssistant(); token.complete()
        XCTAssertEqual(transport.opens,0); XCTAssertTrue(voice.isPausedByUser); XCTAssertFalse(voice.isActive)
    }
}

private final class AuthVoiceToken: VoiceTokenFetching {
    var completion: ((Result<String,Error>)->Void)?
    func fetch(_ configuration: VoiceConfiguration,completion:@escaping (Result<String,Error>)->Void) { self.completion=completion }
    func cancel() {}
    func complete() { completion?(.success("ephemeral-fixture")) }
}
private final class AuthVoiceTransport: VoiceTransport {
    var onEvent: (([String:Any])->Void)?
    var onFailure: (()->Void)?
    var opens=0, closes=0
    func open(token:String) { opens += 1 }
    func send(_ event:[String:Any],completion:@escaping (Bool)->Void) { completion(true) }
    func close() { closes += 1 }
}
private final class AuthVoiceAudio: VoiceAudioIO {
    var pendingPlayback=false
    var playedMilliseconds=0
    var running=false
    func start(onInput:@escaping (Data)->Void,onPlaybackDrained:@escaping ()->Void) throws { running=true }
    func play(_ pcm:Data) throws {}
    func interruptPlayback() {}
    func stop() { running=false }
}
