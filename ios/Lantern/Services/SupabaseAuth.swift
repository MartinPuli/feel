import Foundation

/// Supabase project settings, copied into Info.plist from `ios/Config/Supabase.local.xcconfig`
/// (written by `ios/scripts/supabase_config.sh`). The publishable key is meant to ship in apps;
/// a secret or service-role key is refused so it can never be embedded by mistake.
struct SupabaseConfiguration: Equatable {
    let url: URL
    let publishableKey: String

    init?(url string: String?, publishableKey key: String?) {
        guard let string = string?.trimmingCharacters(in: .whitespaces),
              let url = URL(string: string), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let key = key?.trimmingCharacters(in: .whitespaces), key.count >= 20,
              !key.contains(where: { $0.isWhitespace }), !key.hasPrefix("sb_secret_"),
              !Self.isServiceRoleJWT(key) else { return nil }
        self.url = url; self.publishableKey = key
    }

    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfiguration? {
        Self(url: bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
             publishableKey: bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String)
    }

    /// Legacy keys are JWTs; the service-role one bypasses Row Level Security.
    private static func isServiceRoleJWT(_ key: String) -> Bool {
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return claims["role"] as? String == "service_role"
    }
}

struct AuthSessionTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let email: String
}

enum AuthError: Error, Equatable {
    case invalidCredentials, emailNotConfirmed, rateLimited, offline, unavailable
    case accountExists, weakPassword, invalidEmail, signUpDisabled

    /// Plain sentences: VoiceOver reads them aloud as they appear.
    var message: String {
        switch self {
        case .invalidCredentials: return "That email or password didn't match. Check them and try again."
        case .emailNotConfirmed: return "This account isn't confirmed yet. Confirm the email, then try again."
        case .rateLimited: return "Too many sign-in attempts. Wait a minute, then try again."
        case .offline: return "Couldn't reach the sign-in service. Check the internet connection and try again."
        case .unavailable: return "Sign-in isn't working right now. Try again in a moment."
        case .accountExists: return "An account with that email already exists. Switch to Sign in."
        case .weakPassword: return "That password is too short or too simple. Use at least 6 characters."
        case .invalidEmail: return "That doesn't look like an email address. Check it and try again."
        case .signUpDisabled: return "New accounts are turned off for this FEEL project."
        }
    }
}

protocol AuthClient: AnyObject {
    func signIn(email: String, password: String, completion: @escaping (Result<AuthSessionTokens, AuthError>) -> Void)
    /// Success with nil means the account exists but must confirm its email before signing in.
    func signUp(email: String, password: String, completion: @escaping (Result<AuthSessionTokens?, AuthError>) -> Void)
    func signOut(accessToken: String)
}

/// Supabase Auth email + password over its REST API. Completion runs on the main queue.
/// Redirects are refused so a password cannot travel to another host.
final class SupabaseAuthClient: NSObject, AuthClient, URLSessionTaskDelegate {
    private let configuration: SupabaseConfiguration
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    init(configuration: SupabaseConfiguration) { self.configuration = configuration }

    func signIn(email: String, password: String, completion: @escaping (Result<AuthSessionTokens, AuthError>) -> Void) {
        guard let body = try? JSONEncoder().encode(["email": email, "password": password]) else {
            completion(.failure(.unavailable)); return
        }
        var request = request(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")])
        request.httpBody = body
        session.dataTask(with: request) { data, response, error in
            let result = Self.parseSignIn(data: data, status: (response as? HTTPURLResponse)?.statusCode, failed: error != nil)
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    func signUp(email: String, password: String, completion: @escaping (Result<AuthSessionTokens?, AuthError>) -> Void) {
        guard let body = try? JSONEncoder().encode(["email": email, "password": password]) else {
            completion(.failure(.unavailable)); return
        }
        var request = request(path: "auth/v1/signup", query: [])
        request.httpBody = body
        session.dataTask(with: request) { data, response, error in
            let result = Self.parseSignUp(data: data, status: (response as? HTTPURLResponse)?.statusCode, failed: error != nil)
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// Best effort: the phone forgets its session whether or not the server answers.
    func signOut(accessToken: String) {
        var request = request(path: "auth/v1/logout", query: [URLQueryItem(name: "scope", value: "local")])
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: request).resume()
    }

    static func parseSignIn(data: Data?, status: Int?, failed: Bool) -> Result<AuthSessionTokens, AuthError> {
        if failed { return .failure(.offline) }
        guard let status, let data, data.count < 65_536 else { return .failure(.unavailable) }
        if status == 200 {
            guard let reply = try? JSONDecoder().decode(TokenReply.self, from: data),
                  !reply.access_token.isEmpty, !reply.refresh_token.isEmpty else { return .failure(.unavailable) }
            return .success(AuthSessionTokens(accessToken: reply.access_token, refreshToken: reply.refresh_token,
                                              email: reply.user?.email ?? ""))
        }
        if status == 429 { return .failure(.rateLimited) }
        if status == 400 || status == 401 {
            let code = (try? JSONDecoder().decode(ErrorReply.self, from: data))?.error_code
            return .failure(code == "email_not_confirmed" ? .emailNotConfirmed : .invalidCredentials)
        }
        return .failure(.unavailable)
    }

    /// With "Confirm email" on, Supabase answers 200 without a session (also for an existing
    /// address, so it cannot be used to discover accounts); with it off, the new session is returned.
    static func parseSignUp(data: Data?, status: Int?, failed: Bool) -> Result<AuthSessionTokens?, AuthError> {
        if failed { return .failure(.offline) }
        guard let status, let data, data.count < 65_536 else { return .failure(.unavailable) }
        if status == 200 {
            if case .success(let tokens) = parseSignIn(data: data, status: 200, failed: false) { return .success(tokens) }
            guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return .failure(.unavailable) }
            return .success(nil)
        }
        if status == 429 { return .failure(.rateLimited) }
        switch (try? JSONDecoder().decode(ErrorReply.self, from: data))?.error_code {
        case "user_already_exists", "email_exists": return .failure(.accountExists)
        case "weak_password": return .failure(.weakPassword)
        case "email_address_invalid", "validation_failed": return .failure(.invalidEmail)
        case "signup_disabled", "email_provider_disabled": return .failure(.signUpDisabled)
        default: return .failure(.unavailable)
        }
    }

    private func request(path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: configuration.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    private struct TokenReply: Decodable {
        let access_token: String
        let refresh_token: String
        let user: User?
        struct User: Decodable { let email: String? }
    }
    private struct ErrorReply: Decodable { let error_code: String? }
}

/// Whether this phone may use FEEL. Signing in (or creating an account) once unlocks the whole app until Sign out.
/// Builds without Supabase settings, and UI tests, open the app as before.
final class AuthModel: ObservableObject {
    enum State: Equatable { case notConfigured, signedOut, signingIn, signedIn(email: String) }

    @Published private(set) var state: State
    @Published private(set) var errorMessage: String?
    /// A non-error result to read aloud, such as "check your email".
    @Published private(set) var notice: String?
    private let client: AuthClient?
    private let store: KeychainStore<AuthSessionTokens>

    init(client: AuthClient?, store: KeychainStore<AuthSessionTokens>) {
        self.client = client; self.store = store
        if client == nil { state = .notConfigured }
        else if let saved = store.load() { state = .signedIn(email: saved.email) }
        else { state = .signedOut }
    }

    static func forLaunch() -> AuthModel {
        let store = KeychainStore<AuthSessionTokens>(service: "org.feel.hackharvard.auth", account: "supabase-session")
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let client = uiTesting ? nil : SupabaseConfiguration.fromBundle().map(SupabaseAuthClient.init)
        return AuthModel(client: client, store: store)
    }

    var canUseApp: Bool {
        switch state { case .notConfigured, .signedIn: return true; case .signedOut, .signingIn: return false }
    }
    var signedInEmail: String? { if case .signedIn(let email) = state { return email } else { return nil } }

    func signIn(email: String, password: String) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, state == .signedOut, !email.isEmpty, !password.isEmpty else { return }
        state = .signingIn; errorMessage = nil; notice = nil
        client.signIn(email: email, password: password) { [weak self] result in
            guard let self, self.state == .signingIn else { return }
            switch result {
            case .success(let tokens): self.finish(tokens, email: email)
            case .failure(let error): self.fail(error)
            }
        }
    }

    /// Creates an account. With "Confirm email" off it signs straight in; otherwise `needsConfirmation` runs.
    func signUp(email: String, password: String, needsConfirmation: @escaping () -> Void = {}) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, state == .signedOut, !email.isEmpty, !password.isEmpty else { return }
        state = .signingIn; errorMessage = nil; notice = nil
        client.signUp(email: email, password: password) { [weak self] result in
            guard let self, self.state == .signingIn else { return }
            switch result {
            case .success(.some(let tokens)): self.finish(tokens, email: email)
            case .success(.none):
                self.state = .signedOut
                self.notice = "Account created. Open the confirmation email sent to \(email), then sign in here."
                needsConfirmation()
            case .failure(let error): self.fail(error)
            }
        }
    }

    private func finish(_ tokens: AuthSessionTokens, email: String) {
        // Keychain can refuse a write; the person is still signed in for this launch.
        try? store.save(tokens)
        state = .signedIn(email: tokens.email.isEmpty ? email : tokens.email)
    }

    private func fail(_ error: AuthError) {
        errorMessage = error.message
        state = .signedOut
    }

    func clearMessages() { errorMessage = nil; notice = nil }

    func signOut() {
        guard let client, signedInEmail != nil else { return }
        if let saved = store.load() { client.signOut(accessToken: saved.accessToken) }
        store.clear()
        errorMessage = nil; notice = nil
        state = .signedOut
    }
}
