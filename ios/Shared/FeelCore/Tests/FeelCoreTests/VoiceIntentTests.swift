import XCTest
@testable import FeelCore

final class VoiceIntentTests: XCTestCase {
    private func parse(_ text: String, _ language: VoiceLanguage = .en, final: Bool = true) throws -> VoiceIntent {
        try VoiceIntentParser.parse(text: text, language: language, isFinal: final)
    }

    func testMuteIsOutputOnlyAndRequiresOneFinalCommand() throws {
        XCTAssertEqual(try parse("mute"), .setSpokenOutput(false))
        XCTAssertEqual(try parse("unmute"), .setSpokenOutput(true))
        XCTAssertEqual(try parse("silenciar", .es), .setSpokenOutput(false))
        XCTAssertEqual(try parse("activar voz", .es), .setSpokenOutput(true))
        for text in ["mute", "unmute"] {
            XCTAssertThrowsError(try parse(text, final: false))
            XCTAssertThrowsError(try parse(text + " and stop"))
            XCTAssertThrowsError(try parse("remember Desk and " + text))
            XCTAssertThrowsError(try parse(text, .es))
        }
        XCTAssertThrowsError(try parse("silenciar"))
        XCTAssertThrowsError(try parse("recuerda Mesa y activar voz", .es))
        for enabled in [true, false] {
            let data = try JSONEncoder().encode(VoiceIntent.setSpokenOutput(enabled))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["action"] as? String, "setSpokenOutput")
            XCTAssertEqual(object["enabled"] as? Bool, enabled)
        }
    }

    func testEveryEnglishCommandAndMode() throws {
        XCTAssertEqual(try parse("remember Desk"), .remember("Desk"))
        XCTAssertEqual(try parse("recall Desk"), .recall("Desk"))
        XCTAssertEqual(try parse("return"), .returnToPoint)
        XCTAssertEqual(try parse("stop"), .stop)
        XCTAssertEqual(try parse("list places"), .listPlaces)
        for mode in VoiceFindMode.allCases {
            XCTAssertEqual(try parse("find \(mode.rawValue)"), .find(mode))
        }
    }

    func testEverySpanishCommandAndAccentedMode() throws {
        XCTAssertEqual(try parse("recuerda Mi Café", .es), .remember("Mi Café"))
        XCTAssertEqual(try parse("recupera Mi Café", .es), .recall("Mi Café"))
        XCTAssertEqual(try parse("vuelve", .es), .returnToPoint)
        XCTAssertEqual(try parse("para", .es), .stop)
        XCTAssertEqual(try parse("lista lugares", .es), .listPlaces)
        let words: [(String, VoiceFindMode)] = [("obstáculos", .obstacles), ("puerta", .door),
            ("salida", .exit), ("silla", .chair), ("persona", .person), ("compañero", .teammate), ("código", .barcode)]
        for (word, mode) in words {
            XCTAssertEqual(try parse("BUSCA \(word.uppercased())", .es), .find(mode))
            XCTAssertEqual(try parse("busca \(word.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES")))", .es), .find(mode))
        }
    }

    func testLanguageIsExplicitAndCommandsAreNotTranslatedImplicitly() {
        for text in ["recuerda Mesa", "vuelve", "busca puerta", "lista lugares"] {
            XCTAssertThrowsError(try parse(text, .en))
        }
        for text in ["remember Desk", "return", "find door", "list places"] {
            XCTAssertThrowsError(try parse(text, .es))
        }
    }

    func testCaseWhitespaceAndNamesRemainIntact() throws {
        XCTAssertEqual(try parse("  ReMeMbEr   Mi  Café  "), .remember("Mi  Café"))
        XCTAssertEqual(try parse("\u{00a0}RECALL\u{00a0}Étage 2\u{00a0}"), .recall("Étage 2"))
        XCTAssertEqual(try parse("  LIST   PLACES  "), .listPlaces)
        for name in ["O'Neil's Room", "East-wing", "Door 🚪", "Bus stop", "Bread and Butter", "Mesa y silla"] {
            XCTAssertEqual(try parse("remember \(name)"), .remember(name))
        }
    }

    func testNeverAcceptsPartialTranscriptsIncludingStop() {
        for text in ["stop", "return", "remember Desk", "find person", "", "para"] {
            XCTAssertThrowsError(try parse(text, final: false)) { error in
                XCTAssertEqual(error as? VoiceIntentError, .unfinishedTranscript)
            }
        }
    }

    func testUnknownPrefixesSuffixesAndPerceptionProseAreRejected() {
        for text in ["please stop", "stop now", "return Desk", "find", "find chairs", "find chair please",
                     "list", "list place", "find door exit", "I see a door", "EXIT", "stop.",
                     "remembered Desk", "recallable Desk", "return and stop"] {
            XCTAssertThrowsError(try parse(text), text)
        }
    }

    func testCompositeCommandsCannotBeSilentlyAbsorbedIntoNames() {
        for text in ["remember Desk and stop", "recall Desk then find chair", "remember A and then recall B",
                     "remember A also return", "remember A; stop", "remember A, stop", "remember A | stop",
                     "remember A & stop", "remember A. Stop", "remember A/stop", "recall A: return"] {
            XCTAssertThrowsError(try parse(text), text)
        }
        for text in ["recuerda Mesa y para", "recupera Mesa luego busca silla", "recuerda A después vuelve",
                     "recuerda Mesa y recuerda Silla"] {
            XCTAssertThrowsError(try parse(text, .es), text)
        }
    }

    func testNameLengthBoundsAreCheckedAfterTrimming() throws {
        XCTAssertEqual(try parse("remember A"), .remember("A"))
        let forty = String(repeating: "é", count: 40)
        XCTAssertEqual(try parse("remember \(forty)  "), .remember(forty))
        for text in ["remember", "remember   ", "recall", "recall   ", "remember " + String(repeating: "x", count: 41)] {
            XCTAssertThrowsError(try parse(text), text)
        }
    }

    func testInputLimitAndCombiningMarkBoundCannotBeBypassed() throws {
        XCTAssertEqual(try parse(String(repeating: " ", count: 156) + "stop"), .stop)
        for text in [String(repeating: " ", count: 157) + "stop", "remember A" + String(repeating: "\u{0301}", count: 160)] {
            XCTAssertThrowsError(try parse(text)) { error in
                XCTAssertEqual(error as? VoiceIntentError, .invalidText)
            }
        }
    }

    func testAllControlsAndLineSeparatorsAreRejectedBeforeTrimming() {
        for scalar in ["\0", "\t", "\r", "\n", "\u{007f}", "\u{0085}", "\u{2028}", "\u{2029}", "\u{202e}"] {
            XCTAssertThrowsError(try parse("remember A\(scalar)B")) { error in
                XCTAssertEqual(error as? VoiceIntentError, .invalidText)
            }
            XCTAssertThrowsError(try parse("stop\(scalar)"))
        }
        XCTAssertThrowsError(try parse(""))
        XCTAssertThrowsError(try parse("    "))
    }

    func testIntentEncodingHasStableActionAndArgumentFields() throws {
        let pairs: [(VoiceIntent, [String: String])] = [
            (.remember("Desk"), ["action": "remember", "name": "Desk"]),
            (.recall("Mi Café"), ["action": "recall", "name": "Mi Café"]),
            (.returnToPoint, ["action": "return"]), (.stop, ["action": "stop"]),
            (.listPlaces, ["action": "listPlaces"]), (.find(.barcode), ["action": "find", "mode": "barcode"])
        ]
        for (intent, expected) in pairs {
            let actual = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(intent))
            XCTAssertEqual(actual, expected)
        }
    }
}
