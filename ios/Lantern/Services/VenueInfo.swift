import Foundation
import FeelCore

/// The reviewed venue pack: downloaded over HTTPS while connected, answered on the phone without internet.
/// A failed or invalid download keeps the previous pack. All calls and callbacks are on the main thread.
final class VenueInfo: ObservableObject {
    @Published private(set) var pack: VenuePack?
    @Published private(set) var status = ""
    private let store: VenuePackStore
    private let session: URLSession
    private let now: () -> Date

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VenuePack")
    }

    init(store: VenuePackStore = VenuePackStore(directory: VenueInfo.directory), session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.store = store; self.session = session; self.now = now
        pack = store.load()
        status = describe()
    }

    /// Every place with what FEEL would say about it now, for VoiceOver without the assistant.
    var overview: [String] {
        guard let pack else { return [] }
        return pack.entries.filter { $0.kind == .place }.map { "\($0.name): \(pack.answer($0.name, at: now()).spoken())" }
    }

    func download(from address: String, completion: (() -> Void)? = nil) {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host != nil else {
            status = "Use an HTTPS address for the venue pack."
            completion?(); return
        }
        status = "Downloading the venue pack…"
        session.dataTask(with: URLRequest(url: url, timeoutInterval: 30)) { [weak self] data, response, error in
            DispatchQueue.main.async {
                defer { completion?() }
                guard let self else { return }
                guard error == nil, let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    self.status = self.keeping("The download failed."); return
                }
                do {
                    self.pack = try self.store.install(data, now: self.now())
                    self.status = self.describe()
                } catch {
                    self.status = self.keeping("The download was not a valid, current venue pack.")
                }
            }
        }.resume()
    }

    func answer(_ question: String) -> [String: Any] {
        guard let pack else { return ["error": "No venue pack is downloaded on this phone."] }
        return ["answer": pack.answer(question, at: now()).spoken(), "venue": pack.venueName,
                "note": "Read the answer as given. It is reviewed venue information, not a camera reading, and never means a path is clear."]
    }

    func remove() {
        do { try store.remove(); pack = nil; status = describe() }
        catch { status = "Couldn't remove the venue pack. Try again." }
    }

    private func keeping(_ reason: String) -> String {
        pack.map { "\(reason) The previous pack for \($0.venueName) is kept." } ?? reason
    }

    private func describe() -> String {
        guard let pack else { return "No venue pack downloaded." }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "MMMM d"
        return now() < pack.expiresAt ? "\(pack.venueName): \(pack.entries.count) entries, trusted until \(day.string(from: pack.expiresAt))."
            : "\(pack.venueName): expired on \(day.string(from: pack.expiresAt)). Download a new pack."
    }
}
