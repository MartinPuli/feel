import Foundation
import FeelCore

/// A finite, offline phrase grammar, not a trained language model. It produces
/// the existing symbolic intents and never writes packets or servo values.
enum LocalCommandInterpreter {
    static func parse(_ text: String, language: VoiceLanguage) throws -> VoiceIntent {
        // Validate the original input before normalization; never hide controls or
        // truncate text. Specific paraphrases take precedence over generic names.
        guard !text.isEmpty,text.unicodeScalars.count <= 160,
              !text.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
              }) else { throw VoiceIntentError.invalidText }
        let words=text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var phrase=words.joined(separator:" ")
        if normalized(phrase).hasPrefix(language == .en ? "please " : "por favor ") {
            phrase=words.dropFirst(language == .en ? 1 : 2).joined(separator:" ")
        }
        // Only one final sentence mark is accepted. Names retain accents and case.
        if phrase.last == "." || phrase.last == "!" || phrase.last == "?" { phrase.removeLast() }
        let key=normalized(phrase)
        let exact:[String:VoiceIntent] = language == .en ? [
            "stop":.stop,"stop guidance":.stop,"stop now":.stop,
            "go back":.returnToPoint,"take me back":.returnToPoint,
            "return to my starting point":.returnToPoint,
            "show my places":.listPlaces,"what places have i saved":.listPlaces
        ] : [
            "para":.stop,"detenete":.stop,"detente":.stop,"para ahora":.stop,
            "volve":.returnToPoint,"llevame de vuelta":.returnToPoint,
            "volver al punto de partida":.returnToPoint,
            "mostrame mis lugares":.listPlaces,"muestra mis lugares":.listPlaces
        ]
        if let intent=exact[key] { return intent }
        let patterns:[(String,String)] = language == .en ? [
            ("remember this place as ","remember "),("save this place as ","remember "),
            ("take me to ","recall "),("go back to ","recall "),("go to ","recall "),
            ("help me find ","find ")
        ] : [
            ("guarda este lugar como ","recuerda "),("guarda este sitio como ","recuerda "),
            ("llevame a ","recupera "),("volve a ","recupera "),("vuelve a ","recupera "),
            ("ayudame a buscar ","busca ")
        ]
        guard !patterns.contains(where: { key == $0.0.trimmingCharacters(in:.whitespaces) }) else {
            throw VoiceIntentError.invalidName
        }
        for (prefix,canonical) in patterns where key.hasPrefix(prefix) {
            let prefixWords=prefix.split(separator:" ").count
            let remainder=phrase.split(separator:" ").dropFirst(prefixWords).joined(separator:" ")
            // Extra clauses are ambiguous; never silently save or recall them.
            let tokens=normalized(remainder).split(separator:" ")
            if tokens.contains(where: { ["and","or","then","also","y","o","luego","despues"].contains(String($0)) }) {
                throw VoiceIntentError.compositeCommand
            }
            return try VoiceIntentParser.parse(text:canonical+remainder,language:language,isFinal:true)
        }
        return try VoiceIntentParser.parse(text:phrase,language:language,isFinal:true)
    }

    static func normalized(_ text:String) -> String {
        text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))
    }

    static func isConnectivityFailure(_ error:Error) -> Bool {
        guard let error=error as? URLError else { return false }
        return [.notConnectedToInternet,.networkConnectionLost,.timedOut,.cannotFindHost,
                .cannotConnectToHost,.dnsLookupFailed,.internationalRoamingOff,.dataNotAllowed].contains(error.code)
    }
}
