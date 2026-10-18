import Foundation
import CoreFoundation
import FeelCore

/// Only these commands can cross the model-to-device boundary.
enum VoiceCommand: Equatable {
    case startCamera, stop, pauseAssistant, status, scanPucks, listPucks, openSettings, foundIt, describeAhead
    case find(FinderMode)
    /// `photo` asks for the camera even when room memory remembers the thing.
    case whereIs(String, photo: Bool = false)
    /// Lead the user to a remembered place along the route, one progress point at a time.
    case leadMe(String)
    /// Where the user last confirmed an object, from their find history on Chalk; always a past sighting.
    case lastSeen(String)
    case venueInfo(String)
    case calibrate(Double)
    case connectPuck(UUID)
    case setSpokenOutput(Bool), setProactiveUpdates(Bool), setControlsExpanded(Bool)
    case startSimulation, disconnectPuck, closePanel, scanTeammates, listTeammates, stopFindingTeammate
    case openSystemSettings, forgetVoiceConnection
    case setCameraHeight(Double)
    case openPanel(String), findTeammate(String)
    /// 1-based option from the app's "which one?" question.
    case chooseTarget(Int)
    case setDirectionArrows(Bool), startDirections, stopDirections, simulateDirectionSign
    case startRecording(Bool), stopRecording, setRecordingVideo(Bool)

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
        func text(_ key: String, limit: Int, others: Int = 0) throws -> String {
            guard args.count == 1 + others, let raw = args[key] as? String else { throw InvalidCommand() }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...limit).contains(value.count),
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }) else { throw InvalidCommand() }
            return value
        }
        func measuredHeight() throws -> Double {
            guard args.count == 1, let height = args["measured_height_meters"] as? NSNumber,
                  CFGetTypeID(height) != CFBooleanGetTypeID(), height.doubleValue.isFinite,
                  (0.6...2.1).contains(height.doubleValue) else { throw InvalidCommand() }
            return height.doubleValue
        }
        switch name {
        case "set_direction_arrows": return .setDirectionArrows(try boolean("enabled"))
        case "start_directions": return try noArguments(.startDirections)
        case "stop_directions": return try noArguments(.stopDirections)
        case "simulate_direction_sign": return try noArguments(.simulateDirectionSign)
        case "start_recording": return .startRecording(try boolean("include_video"))
        case "stop_recording": return try noArguments(.stopRecording)
        case "set_recording_video": return .setRecordingVideo(try boolean("enabled"))
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
        case "choose_target":
            guard args.count == 1, let option = args["option"] as? NSNumber, CFGetTypeID(option) != CFBooleanGetTypeID(),
                  option.doubleValue == option.doubleValue.rounded(), (1...4).contains(option.intValue) else { throw InvalidCommand() }
            return .chooseTarget(option.intValue)
        case "connect_puck":
            guard args.count == 1, let value = args["device_id"] as? String,
                  let id = UUID(uuidString: value) else { throw InvalidCommand() }
            return .connectPuck(id)
        case "where_is":
            let photo = try args["photo"].map { value -> Bool in
                guard let flag = value as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else { throw InvalidCommand() }
                return flag.boolValue
            } ?? false
            return .whereIs(try text("thing", limit: 60, others: args["photo"] == nil ? 0 : 1), photo: photo)
        case "found_it": return try noArguments(.foundIt)
        case "describe_ahead": return try noArguments(.describeAhead)
        case "lead_me": return .leadMe(try text("label", limit: 60))
        case "last_seen": return .lastSeen(try text("object", limit: 60))
        case "venue_info": return .venueInfo(try text("question", limit: 200))
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
            tool("set_direction_arrows", "Enable or disable tactile direction arrows when requested. Enabling does not start guidance or prove a safe route.", properties: ["enabled": ["type": "boolean"]]),
            tool("start_directions", "Start tactile arrows toward the currently selected target when requested, without requiring a hand sign. Select the requested target first if needed. Requires live sensing and arrows enabled. Report the returned pending or unavailable state; never promise safe passage."),
            tool("stop_directions", "Stop tactile direction arrows while leaving camera obstacle sensing running. For an unqualified stop, use stop instead."),
            tool("simulate_direction_sign", "Play a synthetic direction cue only in an already running simulation. Identify it as simulation; no hardware movement."),
            tool("start_recording", "Start a local depth recording only when requested. Ask whether to include camera video if unspecified; include_video must reflect the user's explicit choice for this recording. No microphone audio is recorded. Files stay on the phone. Report pending startup honestly.", properties: ["include_video": ["type": "boolean"]]),
            tool("stop_recording", "Stop the current local recording when requested, leaving camera sensing active."),
            tool("set_recording_video", "Choose whether the next local recording includes camera video. Requires the user's explicit choice; cannot change an active recording. Does not start recording.", properties: ["enabled": ["type": "boolean"]]),
            tool("start_camera", "Start the camera only when the user asks. Report pending permission or failure honestly."),
            tool("stop", "Immediately stop camera and tactile output when the user says stop. Keep listening for their next request. No confirmation needed."),
            tool("pause_assistant", "Stop microphone capture only when the user explicitly asks to pause the assistant or stop listening. Resuming then requires touching the app. For silence or mute, use set_spoken_output instead. The camera is unchanged."),
            tool("set_spoken_output", "Enable or mute FEEL's voice. Silence yourself, mute, be quiet, or silenciate means enabled=false. Speak again or unmute means enabled=true. Muting preserves listening and app control, and needs no spoken confirmation.", properties: ["enabled": ["type": "boolean"]]),
            tool("set_proactive_updates", "Enable or disable unsolicited app status announcements. Disabling them still permits spoken replies to the user's requests.", properties: ["enabled": ["type": "boolean"]]),
            tool("get_status", "Read fresh sensing, calibration, target and connection state. ALWAYS call before describing surroundings. Never reuse old readings."),
            tool("find_target", "Select the target the user asks for. This does not confirm a detection or start the camera.", properties: ["target": ["type": "string", "enum": ["obstacles", "door", "exit", "chair", "person", "teammate"]]]),
            tool("where_is", "Find one thing the user names that is not in find_target's list, such as the registration desk, a water fountain or the stairs. When this room's printed FEEL tag has been seen and the thing was found here on an earlier visit, the pins point to that remembered place at once and the result says so (remembered=true): read its status as given. Otherwise it takes one camera photo and points the pins at it when found; confirm once, the result arrives a few seconds later as an observation. photo=true only when the user asks to check again with the camera, for example by saying photo.", properties: ["thing": ["type": "string", "minLength": 1, "maxLength": 60], "photo": ["type": "boolean"]]),
            tool("found_it", "The user says they found the Where-is target (found it, got it, here it is). Ends the pointing, saves the find to the user's history (for where did I last see it) and, when this room's printed FEEL tag has been seen, remembers the place for next time. Report the returned status; never claim it was remembered unless the result says so."),
            tool("describe_ahead", "The user asks what is in front of them, what you see, or what is there: one camera photo is described in one short sentence, nearest things first. Call it every time the question is asked; each call takes a new photo and the app speaks the result."),
            tool("lead_me", "Lead the user to a place remembered in this room (one stored by found_it or an arrival) when they ask to be led or taken there. The pins point to the next point of the way, about every 6 meters, and the app says next point and you're there. Needs this room's printed FEEL tag seen this session and a remembered label; otherwise the result is an error and where_is is the way to look with the camera. Read the returned status as given: a past sighting and a suggested direction, never a clear or safe path.", properties: ["label": ["type": "string", "minLength": 1, "maxLength": 60]]),
            tool("last_seen", "The user asks where they last saw, left or found an object (where did I last see my keys). Looks the object up in the user's own find history, the finds saved by found_it, through FEEL's shared memory on Chalk. The answer is a past record, spoken by the app itself a few seconds later and also returned in get_status.room_memory.last_seen: read it as given, in the past tense, and never say the object is still there. Needs a sign-in and the memory setup; otherwise the result is an error to report plainly.", properties: ["object": ["type": "string", "minLength": 1, "maxLength": 60]]),
            tool("venue_info", "Answer a question about this venue, such as an entrance, restroom or accessibility notice, from the reviewed venue pack downloaded on the phone. Works without internet. Read the returned answer as given, including its source date; never add details or call a path clear.", properties: ["question": ["type": "string", "minLength": 1, "maxLength": 200]]),
            tool("calibrate_floor", "Manual override for automatic floor calibration. Use only after the user supplies a measured lens height in meters and confirms the phone is mounted upright with rear camera forward and top edge to their left. Never guess height.", properties: ["measured_height_meters": ["type": "number", "minimum": 0.6, "maximum": 2.1]]),
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
            tool("set_controls_expanded", "Show or hide the camera's lower drawer containing tactile dots and camera controls.", properties: ["expanded": ["type": "boolean"]]),
            tool("choose_target", "Only after you asked 'I see N ... Which one?': call with the option number the user picked, matching their words (left, right, ahead, nearer, farther, or a number) to the options you listed. If unclear, ask once more.", properties: ["option": ["type": "integer", "minimum": 1, "maximum": 4]])
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
    Asked what is in front, around, nearby, or what you see: call describe_ahead EVERY time, even seconds after the last one, because the user has moved; it takes a new photo. Say only "Looking." and stop; the app speaks the description itself. Never repeat an earlier description, never answer from status fields, never say an obstacle is ahead, and never call a side clear: the pins show obstacles.
    For a thing not in find_target's list, call where_is with a short description and photo=false; it uses one camera photo, and the result comes later as an observation. Without Chalk setup or a connection it uses the phone's own detector, which knows exits, doors, people, chairs and common objects.
    If where_is returns remembered=true, the pins already point to a place found on an earlier visit: say its status as given, in the past tense, and nothing about the present. If the user then says photo, call where_is again with the same thing and photo=true. When the user says they found it, call found_it and report its status.
    When the user asks to be led or taken to a place (lead me to the exit, take me to the desk), call lead_me with that label. On an error, say the place is not remembered here and offer where_is. Never call the way clear.
    When the user asks where they last saw, left or found something (where did I last see my keys), call last_seen with the object. Say only "Checking." and stop; the app speaks the record itself. It is a past record from the user's own find history: never say the object is still there. On an error, say the history is not available and why, in one sentence.
    For questions about the venue itself, such as entrances, restrooms or accessibility notices, call venue_info and read its answer as given. If no pack is downloaded or the answer says it can't be confirmed, say so; never fill the gap yourself.
    Say stop: call stop immediately, then keep listening. Say pause assistant or stop listening: call pause_assistant.
    Say silence yourself, mute, be quiet, or silenciate: call set_spoken_output with enabled=false. Keep listening and executing requested actions while muted.
    Say speak again or unmute: call set_spoken_output with enabled=true. Muting voice is different from pausing microphone capture.
    Say stop automatic updates: call set_proactive_updates with enabled=false while continuing to answer direct questions.
    For tactile directions, use start_directions after selecting the target. The user need not make a hand sign. Directions never establish a safe walking route.
    For recording, ask whether to include camera video when unspecified, then pass that explicit choice to start_recording. Never enable recording proactively.
    For missing information, ask one short question and wait. Do not repeat a completed action.
    When you have just asked which of several targets to guide to, wait for the answer and call choose_target. Don't add anything after it; the app confirms with a sound.

    ## Guardrails & Escalation
    Describe only observations returned by tools. Use spoken_observation when provided; keep its past tense because speech follows the camera sample.
    Unknown, stale and neutral never mean a clear path.
    open_side in get_status says which side has more room than straight ahead while something is within 1.6 meters ahead. Repeat it as relative room, never as clear or safe.
    Do not give walking directions, promise safe passage, identify unobserved objects or invent distances.
    A rectangle candidate is only a possible door, never a confirmed door or safe opening.
    A where_is result is a model's reading of one photo, never a confirmed object. A remembered place is where the thing was on an earlier visit, never where it is now.
    Always call synthetic results simulation. Floor calibration starts automatically with the camera and waits for a stable detected floor. Never claim it succeeded without get_status confirming calibrated. Ask for a measured height only when using the manual calibrate_floor override.
    Start the camera, manually override calibration and connect hardware only when requested. Ask which discovered puck to connect.
    Discovering teammate phones never authorizes an invitation. List them, ask the user to choose, then request that exact phone and wait for its owner's consent.
    If a tool reports pending permission, a request or a failure, preserve that uncertainty.
    Do not invent abilities or suggest unsupported actions. Never read device IDs or internal status tokens aloud.

    ## Voice & Communication Style
    Reply in the user's language. One sentence, 3 to 10 words, result first. Never two sentences unless asked to explain.
    Speak briskly; no pauses for effect, no trailing offers.
    Prefer ordinary spoken words and contractions. No introductions, filler, lists or repeated offers to help.
    Never begin with Certainly, Absolutely, Great question, or As an AI. Do not repeat the user's request.
    For an action, confirm once and finish. For an observation, name the object, approximate distance and relative side.
    Say meters and left, right or ahead instead of reading units, degrees or coordinates from the UI.
    Examples after confirmed tool results: Camera stopped. / Searching for a chair. / I haven't found it yet.
    Examples for recovery: The puck disconnected. / Microphone access is off. / What's the measured camera height?
    These are wording examples, not facts to reuse. Preserve uncertainty and simulation labels even when brief.
    """
}
