import Foundation
import Combine

protocol ChalkCommandTransporting {
    func interpret(_ request: ChalkRequest, endpoint: String, token: String) async throws -> ChalkResponse
    func feedback(traceId: String, sessionId: String, correct: Bool, correctedPlaceId: String?,
                  endpoint: String, token: String) async throws -> ChalkFeedbackResponse
    func deleteSession(_ sessionId: String, endpoint: String, token: String) async throws
}
extension ChalkTransport: ChalkCommandTransporting {}

struct ChalkCommandSnapshot {
    let sessionId: String
    let context: ChalkContext
}

/// Main-queue coordinator. Cloud outputs select symbolic app actions only.
/// The app must cancel on Stop, world reset, tracking loss and background entry.
final class ChalkCommandCoordinator: ObservableObject {
    @Published var endpoint: String {
        didSet {
            guard endpoint != oldValue else { return }
            defaults.set(endpoint, forKey: Self.endpointKey)
            cancel(reason: "Service changed."); clearFeedback()
        }
    }
    @Published var sharingEnabled: Bool {
        didSet {
            defaults.set(sharingEnabled, forKey: Self.sharingKey)
            if !sharingEnabled { cancel(reason: "Cloud commands are off.") }
        }
    }
    @Published var retentionEnabled: Bool {
        didSet {
            defaults.set(retentionEnabled, forKey: Self.retentionKey)
            if retentionEnabled != oldValue { cancel(reason: "Retention preference changed.") }
        }
    }
    @Published private(set) var status = "Cloud commands are off. Local controls remain available."
    @Published private(set) var isBusy = false
    @Published private(set) var hasToken: Bool
    @Published private(set) var canGiveFeedback = false
    @Published private(set) var correctionPlaces: [ChalkPlace] = []
    @Published private(set) var historySessionCount = 0
    var captureContext: () -> ChalkCommandSnapshot? = { nil }
    var applyDecision: (ChalkDecision) -> String = { _ in "No action handler is configured." }

    private struct FeedbackTarget {
        let response: ChalkResponse
        let request: ChalkRequest
        let endpoint: String
    }
    private static let endpointKey = "feel.chalk.commands.endpoint"
    private static let sharingKey = "feel.chalk.commands.sharing"
    private static let retentionKey = "feel.chalk.commands.retention"
    private static let historyKey = "feel.chalk.commands.sessions"
    private let defaults: UserDefaults
    private let transport: ChalkCommandTransporting
    private let readToken: () -> String
    private let writeToken: (String) -> Bool
    private let now: () -> TimeInterval
    private let freshness: TimeInterval
    private var task: Task<Void, Never>?
    private var timeout: DispatchWorkItem?
    private var generation = 0
    private var last: FeedbackTarget?
    private var history: [String: [String]]

    init(transport: ChalkCommandTransporting = ChalkTransport(), defaults: UserDefaults = .standard,
         readToken: @escaping () -> String = ChalkTokenStore.read,
         writeToken: @escaping (String) -> Bool = ChalkTokenStore.write,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         freshness: TimeInterval = 4) {
        self.transport = transport; self.defaults = defaults
        self.readToken = readToken; self.writeToken = writeToken; self.now = now
        self.freshness = freshness
        endpoint = defaults.string(forKey: Self.endpointKey) ?? ""
        sharingEnabled = defaults.bool(forKey: Self.sharingKey)
        retentionEnabled = defaults.bool(forKey: Self.retentionKey)
        hasToken = !readToken().isEmpty
        history = defaults.dictionary(forKey: Self.historyKey) as? [String: [String]] ?? [:]
        historySessionCount = history[endpoint]?.count ?? 0
        if sharingEnabled { status = "Cloud commands are enabled. Requests share text and saved place names." }
    }

    deinit { task?.cancel(); timeout?.cancel() }

    @discardableResult func saveToken(_ value: String) -> Bool {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.isEmpty || (token.utf8.count >= 32 && token.utf8.count <= 4096 &&
              token.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 })) else {
            status = "Use the app access token provided by the FEEL service."; return false
        }
        guard writeToken(token) else { status = "Could not save the access token securely."; return false }
        cancel(reason: token.isEmpty ? "Access token removed." : "Access token saved.")
        clearFeedback(); hasToken = !token.isEmpty
        return true
    }

    /// Invalidate immediately even when a transport ignores task cancellation.
    func cancel(reason: String = "Canceled.") {
        generation += 1
        task?.cancel(); task = nil
        timeout?.cancel(); timeout = nil
        isBusy = false; status = reason
        historySessionCount = history[endpoint]?.count ?? 0
    }

    func submit(_ utterance: String, language: String = "en") {
        cancel(); clearFeedback()
        let phrase = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, phrase.unicodeScalars.count <= 2_000,
              !phrase.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            status = "Use a short request without line breaks."; return
        }
        // Emergency Stop never depends on configuration, consent, a server or a camera.
        var immediate = phrase.lowercased()
        if let last = immediate.last, ".!?".contains(last) { immediate.removeLast() }
        if ["stop", "stop now", "stop guidance", "para", "pará", "para ahora", "detener", "detente", "detenete"].contains(immediate) {
            status = applyDecision(ChalkDecision(action: .stop, placeId: nil, name: nil, message: "Stopped."))
            return
        }
        guard sharingEnabled else { status = "Enable cloud sharing before sending a request."; return }
        guard configured else { status = ChalkError.configuration.localizedDescription; return }
        guard let snapshot = captureContext(), !snapshot.sessionId.isEmpty else {
            status = "Start a camera session before using saved-place commands."; return
        }
        let service = endpoint, token = readToken(), started = now(), attempt = generation
        var sessions = history[service] ?? []
        guard sessions.contains(snapshot.sessionId) || sessions.count < 100 else {
            status = "Delete saved command history before starting another cloud session."; return
        }
        if !sessions.contains(snapshot.sessionId) { sessions.append(snapshot.sessionId) }
        history[service] = sessions; persistHistory()
        let request = ChalkRequest(requestId: UUID().uuidString, sessionId: snapshot.sessionId,
                                   utterance: phrase, language: language, context: snapshot.context, consent: retentionEnabled)
        isBusy = true; status = "Interpreting your request."
        scheduleTimeout(after: freshness, attempt: attempt, message: "The reply took too long. No action was applied.")
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await self.transport.interpret(request, endpoint: service, token: token)
                guard self.accepts(attempt), !Task.isCancelled else { return }
                try response.validate(for: request)
                guard self.now() - started >= 0, self.now() - started <= self.freshness,
                      self.sharingEnabled, self.endpoint == service, self.readToken() == token,
                      let current = self.captureContext(), current.sessionId == snapshot.sessionId,
                      current.context == snapshot.context else {
                    self.finish(attempt, message: "The session changed or the reply expired. No action was applied."); return
                }
                // Clear busy state before the local action, which can synchronously call cancel.
                self.finish(attempt, message: "Request received.")
                self.last = FeedbackTarget(response: response, request: request, endpoint: service)
                self.canGiveFeedback = true
                self.correctionPlaces = request.consent ? request.context.places : []
                self.status = self.applyDecision(response.decision)
            } catch {
                self.finish(attempt, message: "Cloud commands are unavailable. Use local commands or try again.")
            }
        }
    }

    func submitFeedback(correct: Bool, correctedPlaceId: String? = nil) {
        guard !isBusy, canGiveFeedback, let target = last else { return }
        guard correctedPlaceId == nil || (!correct && target.request.consent &&
              target.request.context.places.contains(where: { $0.id == correctedPlaceId })) else {
            status = "Choose a place from the original shared request."; return
        }
        guard endpoint == target.endpoint, configured else { status = "Restore the original service configuration."; return }
        cancel(); let attempt = generation, token = readToken()
        isBusy = true; status = "Saving feedback."
        scheduleTimeout(after: 10, attempt: attempt, message: "Feedback confirmation timed out. It may already be saved.")
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await self.transport.feedback(traceId: target.response.traceId,
                    sessionId: target.request.sessionId, correct: correct, correctedPlaceId: correctedPlaceId,
                    endpoint: target.endpoint, token: token)
                guard self.accepts(attempt), !Task.isCancelled else { return }
                guard response.recorded, !response.actionExecuted else { throw ChalkError.invalidResponse }
                self.canGiveFeedback = false
                self.finish(attempt, message: response.aliasSaved ? "Correction saved for this session. No action was taken." : "Feedback saved.")
            } catch { self.finish(attempt, message: "Could not confirm feedback. It may already be saved.") }
        }
    }

    /// Delete sessions this device submitted to the configured service, including prior launches.
    func deleteHistory() {
        cancel(); clearFeedback()
        guard configured else { status = ChalkError.configuration.localizedDescription; return }
        let service = endpoint, token = readToken(), attempt = generation
        let sessions = history[service] ?? []
        guard !sessions.isEmpty else { status = "No saved command sessions on this device."; return }
        isBusy = true; status = "Deleting command history."
        scheduleTimeout(after: 20, attempt: attempt, message: "Deletion is incomplete. Try again to finish remaining sessions.")
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for session in sessions {
                    try Task.checkCancellation()
                    try await self.transport.deleteSession(session, endpoint: service, token: token)
                    guard self.accepts(attempt), !Task.isCancelled else { return }
                    self.history[service]?.removeAll { $0 == session }; self.persistHistory()
                }
                self.finish(attempt, message: "Deletion completed for this device's saved command sessions.")
            } catch { self.finish(attempt, message: "Deletion is incomplete. Try again to finish remaining sessions.") }
        }
    }

    private var configured: Bool {
        guard let parts = URLComponents(string: endpoint) else { return false }
        return parts.scheme == "https" && !(parts.host ?? "").isEmpty && parts.user == nil &&
            parts.password == nil && parts.query == nil && parts.fragment == nil &&
            (parts.path.isEmpty || parts.path == "/") && !readToken().isEmpty
    }
    private func accepts(_ attempt: Int) -> Bool { generation == attempt && isBusy }
    private func finish(_ attempt: Int, message: String) {
        guard accepts(attempt) else { return }
        timeout?.cancel(); timeout = nil; task = nil
        isBusy = false; status = message
    }
    private func scheduleTimeout(after seconds: TimeInterval, attempt: Int, message: String) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.accepts(attempt) else { return }
            self.cancel(reason: message)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
    private func clearFeedback() { last = nil; canGiveFeedback = false; correctionPlaces = [] }
    private func persistHistory() {
        defaults.set(history, forKey: Self.historyKey)
        historySessionCount = history[endpoint]?.count ?? 0
    }
}
