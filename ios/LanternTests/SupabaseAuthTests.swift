import XCTest
@testable import Lantern

private final class StubAuthClient: AuthClient {
    var pending: ((Result<AuthSessionTokens, AuthError>) -> Void)?
    var signIns: [(String, String)] = []
    var signedOutTokens: [String] = []
    func signIn(email: String, password: String, completion: @escaping (Result<AuthSessionTokens, AuthError>) -> Void) {
        signIns.append((email, password)); pending = completion
    }
    var pendingSignUp: ((Result<AuthSessionTokens?, AuthError>) -> Void)?
    var signUps: [(String, String)] = []
    func signUp(email: String, password: String, completion: @escaping (Result<AuthSessionTokens?, AuthError>) -> Void) {
        signUps.append((email, password)); pendingSignUp = completion
    }
    func signOut(accessToken: String) { signedOutTokens.append(accessToken) }
}

final class SupabaseAuthTests: XCTestCase {
    private var store: KeychainStore<AuthSessionTokens>!
    private let tokens = AuthSessionTokens(accessToken: "access", refreshToken: "refresh", email: "demo@feel.test")

    override func setUp() {
        store = KeychainStore(service: "org.feel.hackharvard.auth.tests", account: name)
        store.clear()
    }
    override func tearDown() { store.clear() }

    func testConfigurationAcceptsPublishableKeyAndRefusesSecrets() {
        let url = "https://abcdefgh.supabase.co"
        XCTAssertNotNil(SupabaseConfiguration(url: url, publishableKey: "sb_publishable_0123456789abcdef"))
        XCTAssertNil(SupabaseConfiguration(url: url, publishableKey: "sb_secret_0123456789abcdef"))
        XCTAssertNil(SupabaseConfiguration(url: "http://abcdefgh.supabase.co", publishableKey: "sb_publishable_0123456789abcdef"))
        XCTAssertNil(SupabaseConfiguration(url: "", publishableKey: ""))
        // Unset build settings expand to empty strings.
        XCTAssertNil(SupabaseConfiguration(url: nil, publishableKey: nil))
        let serviceRole = "eyJhbGciOiJIUzI1NiJ9." + Data(#"{"role":"service_role"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "") + ".signature"
        XCTAssertNil(SupabaseConfiguration(url: url, publishableKey: serviceRole))
        let anon = "eyJhbGciOiJIUzI1NiJ9." + Data(#"{"role":"anon"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "") + ".signature"
        XCTAssertNotNil(SupabaseConfiguration(url: url, publishableKey: anon))
    }

    func testParsesSupabaseReplies() {
        let ok = Data(#"{"access_token":"a","refresh_token":"r","user":{"email":"demo@feel.test"}}"#.utf8)
        XCTAssertEqual(SupabaseAuthClient.parseSignIn(data: ok, status: 200, failed: false),
                       .success(AuthSessionTokens(accessToken: "a", refreshToken: "r", email: "demo@feel.test")))
        let wrong = Data(#"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#.utf8)
        XCTAssertEqual(SupabaseAuthClient.parseSignIn(data: wrong, status: 400, failed: false), .failure(.invalidCredentials))
        let unconfirmed = Data(#"{"code":400,"error_code":"email_not_confirmed"}"#.utf8)
        XCTAssertEqual(SupabaseAuthClient.parseSignIn(data: unconfirmed, status: 400, failed: false), .failure(.emailNotConfirmed))
        XCTAssertEqual(SupabaseAuthClient.parseSignIn(data: Data(), status: 429, failed: false), .failure(.rateLimited))
        XCTAssertEqual(SupabaseAuthClient.parseSignIn(data: nil, status: nil, failed: true), .failure(.offline))
        XCTAssertEqual(SupabaseAuthClient.parseSignIn(data: Data("{}".utf8), status: 200, failed: false), .failure(.unavailable))
        XCTAssertEqual(SupabaseAuthClient.parseSignIn(data: Data(), status: 500, failed: false), .failure(.unavailable))
    }

    func testParsesSupabaseSignUpReplies() {
        let session = Data(#"{"access_token":"a","refresh_token":"r","user":{"email":"new@feel.test"}}"#.utf8)
        XCTAssertEqual(SupabaseAuthClient.parseSignUp(data: session, status: 200, failed: false),
                       .success(AuthSessionTokens(accessToken: "a", refreshToken: "r", email: "new@feel.test")))
        let confirm = Data(#"{"id":"1","email":"new@feel.test","confirmation_sent_at":"2026-10-17T21:00:00Z"}"#.utf8)
        XCTAssertEqual(SupabaseAuthClient.parseSignUp(data: confirm, status: 200, failed: false), .success(nil))
        let cases: [(String, AuthError)] = [("user_already_exists", .accountExists), ("weak_password", .weakPassword),
                                            ("email_address_invalid", .invalidEmail), ("signup_disabled", .signUpDisabled),
                                            ("something_new", .unavailable)]
        for (code, error) in cases {
            let body = Data(#"{"code":422,"error_code":"\#(code)"}"#.utf8)
            XCTAssertEqual(SupabaseAuthClient.parseSignUp(data: body, status: 422, failed: false), .failure(error), code)
        }
        XCTAssertEqual(SupabaseAuthClient.parseSignUp(data: Data(), status: 429, failed: false), .failure(.rateLimited))
        XCTAssertEqual(SupabaseAuthClient.parseSignUp(data: nil, status: nil, failed: true), .failure(.offline))
        XCTAssertEqual(SupabaseAuthClient.parseSignUp(data: Data("[]".utf8), status: 200, failed: false), .failure(.unavailable))
    }

    func testSignUpWithoutEmailConfirmationSignsStraightIn() {
        let client = StubAuthClient()
        let auth = AuthModel(client: client, store: store)
        auth.signUp(email: " new@feel.test ", password: "secret")
        XCTAssertEqual(auth.state, .signingIn)
        XCTAssertEqual(client.signUps.first?.0, "new@feel.test")
        client.pendingSignUp?(.success(AuthSessionTokens(accessToken: "a", refreshToken: "r", email: "new@feel.test")))
        XCTAssertEqual(auth.state, .signedIn(email: "new@feel.test"))
        XCTAssertNotNil(store.load())
    }

    func testSignUpNeedingConfirmationStaysLockedWithNotice() {
        let client = StubAuthClient()
        let auth = AuthModel(client: client, store: store)
        var askedToSignIn = false
        auth.signUp(email: "new@feel.test", password: "secret") { askedToSignIn = true }
        client.pendingSignUp?(.success(nil))
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertFalse(auth.canUseApp)
        XCTAssertTrue(askedToSignIn)
        XCTAssertNotNil(auth.notice)
        XCTAssertNil(auth.errorMessage)
        XCTAssertNil(store.load())
    }

    func testFailedSignUpExplainsWhy() {
        let client = StubAuthClient()
        let auth = AuthModel(client: client, store: store)
        auth.signUp(email: "taken@feel.test", password: "secret")
        client.pendingSignUp?(.failure(.accountExists))
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertEqual(auth.errorMessage, AuthError.accountExists.message)
    }

    func testUnconfiguredBuildOpensWithoutSignIn() {
        let auth = AuthModel(client: nil, store: store)
        XCTAssertEqual(auth.state, .notConfigured)
        XCTAssertTrue(auth.canUseApp)
        XCTAssertNil(auth.signedInEmail)
    }

    func testSignInUnlocksAppAndSurvivesRelaunch() {
        let client = StubAuthClient()
        let auth = AuthModel(client: client, store: store)
        XCTAssertFalse(auth.canUseApp)
        auth.signIn(email: "  demo@feel.test ", password: "secret")
        XCTAssertEqual(auth.state, .signingIn)
        XCTAssertEqual(client.signIns.first?.0, "demo@feel.test")
        auth.signIn(email: "demo@feel.test", password: "secret")
        XCTAssertEqual(client.signIns.count, 1, "A second tap while signing in is ignored")
        client.pending?(.success(tokens))
        XCTAssertEqual(auth.state, .signedIn(email: "demo@feel.test"))
        XCTAssertTrue(auth.canUseApp)
        XCTAssertEqual(AuthModel(client: StubAuthClient(), store: store).state, .signedIn(email: "demo@feel.test"))
    }

    func testFailedSignInStaysLockedWithSpokenMessage() {
        let client = StubAuthClient()
        let auth = AuthModel(client: client, store: store)
        auth.signIn(email: "demo@feel.test", password: "wrong")
        client.pending?(.failure(.invalidCredentials))
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertFalse(auth.canUseApp)
        XCTAssertEqual(auth.errorMessage, AuthError.invalidCredentials.message)
        XCTAssertNil(store.load())
    }

    func testEmptyFieldsDoNotSubmit() {
        let client = StubAuthClient()
        let auth = AuthModel(client: client, store: store)
        auth.signIn(email: " ", password: "secret")
        auth.signIn(email: "demo@feel.test", password: "")
        XCTAssertTrue(client.signIns.isEmpty)
        XCTAssertEqual(auth.state, .signedOut)
    }

    func testSignOutLocksAppAndForgetsSession() throws {
        try store.save(tokens)
        let client = StubAuthClient()
        let auth = AuthModel(client: client, store: store)
        XCTAssertTrue(auth.canUseApp)
        auth.signOut()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertFalse(auth.canUseApp)
        XCTAssertEqual(client.signedOutTokens, ["access"])
        XCTAssertNil(store.load())
    }
}
