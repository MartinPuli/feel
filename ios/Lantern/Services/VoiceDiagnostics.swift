import Foundation

/// Bounded development diagnostics. Never record audio, transcripts, credentials or provider messages.
enum VoiceDiagnostics {
    static func record(_ event: String, detail: String = "") {
        #if DEBUG
        guard let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = folder.appendingPathComponent("feel-voice-diagnostics.json")
        var records = ((try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode([[String: String]].self, from: $0)
        } ?? [])
        records.append(["time": ISO8601DateFormatter().string(from: Date()),
                        "event": event, "detail": String(detail.prefix(160))])
        if let data = try? JSONEncoder().encode(Array(records.suffix(20))) {
            try? data.write(to: url, options: .atomic)
        }
        #endif
    }

    static func providerCode(_ event: [String: Any]) -> String {
        let error = event["error"] as? [String: Any]
        guard let code = error?["code"] as? String, code.count <= 64,
              code.allSatisfy({ $0.isASCII && ($0.isLowercase || $0 == "_") }) else { return "unknown" }
        return code
    }
}
