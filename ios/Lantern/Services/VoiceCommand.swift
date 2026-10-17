import Foundation
import CoreFoundation
import FeelCore

/// Only these commands can cross the model-to-device boundary.
enum VoiceCommand: Equatable {
    case startCamera, stop, pauseAssistant, status, scanPucks, listPucks, openSettings
    case find(FinderMode)
    case whereIs(String)
    case calibrate(Double)
    case connectPuck(UUID)
    case setSpokenOutput(Bool), setProactiveUpdates(Bool), setControlsExpanded(Bool)
    case startSimulation, disconnectPuck, closePanel, scanTeammates, listTeammates, stopFindingTeammate
    case openSystemSettings, forgetVoiceConnection
    case setCameraHeight(Double)
    case openPanel(String), findTeammate(String)

    static func decode(name: String, arguments: String) throws -> VoiceCommand {
        guard arguments.utf8.count <= 2048,
              let data = arguments.data(using: .utf8),
              let args = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw InvalidCommand() }
        func noArguments(_ command: VoiceCommand) throws -> VoiceCommand {
            guard args.isEmpty else { throw InvalidCommand() }
            return command
        }
        func boolean(_ key: String) throws -> Bool {
            guard args.count == 1, let value = args[key] as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID() else { throw InvalidCommand() }
            return value.boolValue
        }
        func measuredHeight() throws -> Double {
            guard args.count == 1, let height = args["measured_height_meters"] as? NSNumber,
                  CFGetTypeID(height) != CFBooleanGetTypeID(), height.doubleValue.isFinite,
                  (0.6...2.1).contains(height.doubleValue) else { throw InvalidCommand() }
            return height.doubleValue
        }
        switch name {
        case "start_camera": return try noArguments(.startCamera)
        case "stop": return try noArguments(.stop)
        case "pause_assistant": return try noArguments(.pauseAssistant)
        case "get_status": return try noArguments(.status)
        case "scan_pucks": return try noArguments(.scanPucks)
        case "list_pucks": return try noArguments(.listPucks)
        case "open_settings": return try noArguments(.openSettings)
        case "set_spoken_output": return .setSpokenOutput(try boolean("enabled"))
        case "set_proactive_updates": return .setProactiveUpdates(try boolean("enabled"))
        case "set_controls_expanded": return .setControlsExpanded(try boolean("expanded"))
        case "start_simulation": return try noArguments(.startSimulation)
        case "disconnect_puck": return try noArguments(.disconnectPuck)
        case "close_panel": return try noArguments(.closePanel)
        case "scan_teammates": return try noArguments(.scanTeammates)
        case "list_teammates": return try noArguments(.listTeammates)
        case "stop_finding_teammate": return try noArguments(.stopFindingTeammate)
        case "open_system_settings": return try noArguments(.openSystemSettings)
        case "forget_voice_connection":
            guard try boolean("confirmed") else { throw InvalidCommand() }
            return .forgetVoiceConnection
        case "set_camera_height": return .setCameraHeight(try measuredHeight())
        case "open_panel":
            guard args.count == 1, let panel = args["panel"] as? String,
                  ["settings", "connection", "assistant"].contains(panel) else { throw InvalidCommand() }
            return .openPanel(panel)
        case "find_teammate":
            guard args.count == 1, let id = args["device_id"] as? String,
                  !id.isEmpty, id.utf8.count <= 128,
                  id.utf8.allSatisfy({ (33...126).contains($0) }) else { throw InvalidCommand() }
            return .findTeammate(id)
        case "find_target":
            let modes: [String: FinderMode] = ["obstacles": .none, "door": .door, "exit": .exit, "chair": .chair, "person": .person, "teammate": .teammate]
            guard args.count == 1, let value = args["target"] as? String, let mode = modes[value] else { throw InvalidCommand() }
            return .find(mode)
        case "calibrate_floor":
            return .calibrate(try measuredHeight())
        case "connect_puck":
            guard args.count == 1, let value = args["device_id"] as? String,
                  let id = UUID(uuidString: value) else { throw InvalidCommand() }
            return .connectPuck(id)
        case "where_is":
            guard args.count == 1, let raw = args["thing"] as? String else { throw InvalidCommand() }
            let thing = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...60).contains(thing.count),
                  !thing.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }) else { throw InvalidCommand() }
            return .whereIs(thing)
        default: throw InvalidCommand()
        }
    }

    struct InvalidCommand: Error {}

    static var tools: [[String: Any]] {
        func tool(_ name: String, _ description: String, properties: [String: Any] = [:]) -> [String: Any] {
            ["type": "function", "name": name, "description": description,
             "parameters": ["type": "object", "properties": properties,
                            "required": properties.keys.sorted(), "additionalProperties": false]]
        }
        return [
            tool("start_camera", "Start the camera only when the user asks. Report pending permission or failure honestly."),
            tool("stop", "Immediately stop camera and tactile output when the user says stop. Keep listening for their next request. No confirmation needed."),
            tool("pause_assistant", "Stop microphone capture only when the user explicitly asks to pause the assistant or stop listening. Resuming then requires touching the app. For silence or mute, use set_spoken_output instead. The camera is unchanged."),
            tool("set_spoken_output", "Enable or mute FEEL's voice. Silence yourself, mute, be quiet, or silenciate means enabled=false. Speak again or unmute means enabled=true. Muting preserves listening and app control, and needs no spoken confirmation.", properties: ["enabled": ["type": "boolean"]]),
            tool("set_proactive_updates", "Enable or disable unsolicited app status announcements. Disabling them still permits spoken replies to the user's requests.", properties: ["enabled": ["type": "boolean"]]),
            tool("get_status", "Read fresh sensing, calibration, target and connection state. ALWAYS call before describing surroundings. Never reuse old readings."),
            tool("find_target", "Select the target the user asks for. This does not confirm a detection or start the camera.", properties: ["target": ["type": "string", "enum": ["obstacles", "door", "exit", "chair", "person", "teammate"]]]),
            tool("where_is", "Find one thing the user names that is not in find_target's list, such as the registration desk, a water fountain or the stairs. Takes one camera photo and points the pins at it when found. Confirm once; the result arrives a few seconds later as an observation. Call get_status to check progress.", properties: ["thing": ["type": "string", "minLength": 1, "maxLength": 60]]),
            tool("calibrate_floor", "Calibrate only after the user supplies a measured lens height in meters and confirms the phone is mounted upright with rear camera forward and top edge to their left. Never guess height.", properties: ["measured_height_meters": ["type": "number", "minimum": 0.6, "maximum": 2.1]]),
            tool("set_camera_height", "Set the measured camera lens height without calibrating. Ask the user for their measurement in meters; never infer it from their body height.", properties: ["measured_height_meters": ["type": "number", "minimum": 0.6, "maximum": 2.1]]),
            tool("start_simulation", "Start the synthetic demo only when requested. Always identify it as simulation, never live sensing."),
            tool("scan_pucks", "Begin Bluetooth discovery when the user asks to connect. Wait briefly, then list_pucks. Do not select a device yourself."),
            tool("list_pucks", "List currently discovered puck IDs and names. Ask the user which one to connect, even if there is only one."),
            tool("connect_puck", "Connect ONLY the device explicitly selected by the user from list_pucks. Use the exact returned ID.", properties: ["device_id": ["type": "string"]]),
            tool("disconnect_puck", "Disconnect the current tactile puck when requested."),
            tool("scan_teammates", "Discover nearby Beacon phones when requested. This does not invite or select any phone. Wait briefly, then list_teammates."),
            tool("list_teammates", "List discovered Beacon phones and opaque IDs. Ask which phone the user wants, even when only one appears. Never read the IDs aloud."),
            tool("find_teammate", "Request pairing ONLY with the Beacon phone explicitly selected by the user from list_teammates, using its exact returned ID. The other phone must accept; do not claim connected or located until tools confirm it.", properties: ["device_id": ["type": "string", "minLength": 1, "maxLength": 128]]),
            tool("stop_finding_teammate", "Stop teammate discovery and ranging when requested. Do not stop unrelated camera sensing."),
            tool("open_settings", "Open the existing settings panel for manual setup."),
            tool("open_panel", "Open the requested floating panel over the camera.", properties: ["panel": ["type": "string", "enum": ["settings", "connection", "assistant"]]]),
            tool("close_panel", "Close the current floating panel when requested."),
            tool("open_system_settings", "Open FEEL's iPhone Settings page when requested. The user must change permissions there manually; never claim permission was granted."),
            tool("forget_voice_connection", "Remove saved voice setup ONLY after explaining that the assistant will stop and need setup again, and the user explicitly confirms. Say that explanation before calling; the connection ends immediately. Never request or read credentials aloud.", properties: ["confirmed": ["type": "boolean", "enum": [true]]]),
            tool("set_controls_expanded", "Show or hide the camera's lower drawer containing tactile dots and camera controls.", properties: ["expanded": ["type": "boolean"]])
        ]
    }

    static let instructions = """
    ## Role & Persona
    You are FEEL, a practical personal assistant for a blind person using a camera and tactile puck.
    Treat the user as an adult. Be helpful without being chatty or patronizing.

    ## Objective
    Let the user control the app and hear useful, current observations without looking at the screen.

    ## Conversation Flow
    Use the provided tools for actions. Wait for their results before confirming anything.
    Call get_status before describing the scene. You do not receive camera images.
    For a thing not in find_target's list, call where_is with a short description; it uses one camera photo, and the result comes later as an observation.
    Say stop: call stop immediately, then keep listening. Say pause assistant or stop listening: call pause_assistant.
    Say silence yourself, mute, be quiet, or silenciate: call set_spoken_output with enabled=false. Keep listening and executing requested actions while muted.
    Say speak again or unmute: call set_spoken_output with enabled=true. Muting voice is different from pausing microphone capture.
    Say stop automatic updates: call set_proactive_updates with enabled=false while continuing to answer direct questions.
    For missing information, ask one short question and wait. Do not repeat a completed action.

    ## Guardrails & Escalation
    Describe only observations returned by tools. Use spoken_observation when provided; keep its past tense because speech follows the camera sample.
    Unknown, stale and neutral never mean a clear path.
    Do not give walking directions, promise safe passage, identify unobserved objects or invent distances.
    A rectangle candidate is only a possible door, never a confirmed door or safe opening.
    A where_is result is a model's reading of one photo, never a confirmed object.
    Always call synthetic results simulation. Ask for a measured height before floor calibration.
    Start the camera, calibrate and connect hardware only when requested. Ask which discovered puck to connect.
    Discovering teammate phones never authorizes an invitation. List them, ask the user to choose, then request that exact phone and wait for its owner's consent.
    If a tool reports pending permission, a request or a failure, preserve that uncertainty.
    Do not invent abilities or suggest unsupported actions. Never read device IDs or internal status tokens aloud.

    ## Voice & Communication Style
    Reply in the user's language. Give the result first, usually in one sentence of 3 to 12 words.
    Use a second sentence only for a necessary next step or a requested explanation.
    Prefer ordinary spoken words and contractions. No introductions, filler, lists or repeated offers to help.
    Never begin with Certainly, Absolutely, Great question, or As an AI. Do not repeat the user's request.
    For an action, confirm once and finish. For an observation, name the object, approximate distance and relative side.
    Say meters and left, right or ahead instead of reading units, degrees or coordinates from the UI.
    Examples after confirmed tool results: Camera stopped. / Searching for a chair. / I haven't found it yet.
    Examples for recovery: The puck disconnected. / Microphone access is off. / What's the measured camera height?
    These are wording examples, not facts to reuse. Preserve uncertainty and simulation labels even when brief.
    """
}
