import Foundation
import CoreFoundation
import FeelCore

/// Only these commands can cross the model-to-device boundary.
enum VoiceCommand: Equatable {
    case startCamera, stop, pauseAssistant, status, scanPucks, listPucks, openSettings
    case find(FinderMode)
    case calibrate(Double)
    case connectPuck(UUID)

    static func decode(name: String, arguments: String) throws -> VoiceCommand {
        guard arguments.utf8.count <= 2048,
              let data = arguments.data(using: .utf8),
              let args = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw InvalidCommand() }
        func noArguments(_ command: VoiceCommand) throws -> VoiceCommand {
            guard args.isEmpty else { throw InvalidCommand() }
            return command
        }
        switch name {
        case "start_camera": return try noArguments(.startCamera)
        case "stop": return try noArguments(.stop)
        case "pause_assistant": return try noArguments(.pauseAssistant)
        case "get_status": return try noArguments(.status)
        case "scan_pucks": return try noArguments(.scanPucks)
        case "list_pucks": return try noArguments(.listPucks)
        case "open_settings": return try noArguments(.openSettings)
        case "find_target":
            let modes: [String: FinderMode] = ["obstacles": .none, "door": .door, "exit": .exit, "chair": .chair, "person": .person, "teammate": .teammate]
            guard args.count == 1, let value = args["target"] as? String, let mode = modes[value] else { throw InvalidCommand() }
            return .find(mode)
        case "calibrate_floor":
            guard args.count == 1, let height = args["measured_height_meters"] as? NSNumber,
                  CFGetTypeID(height) != CFBooleanGetTypeID(), height.doubleValue.isFinite,
                  (0.6...2.1).contains(height.doubleValue) else { throw InvalidCommand() }
            return .calibrate(height.doubleValue)
        case "connect_puck":
            guard args.count == 1, let value = args["device_id"] as? String,
                  let id = UUID(uuidString: value) else { throw InvalidCommand() }
            return .connectPuck(id)
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
            tool("pause_assistant", "Stop microphone capture and spoken responses only when the user explicitly asks to pause the assistant or stop listening. The camera is unchanged."),
            tool("get_status", "Read fresh sensing, calibration, target and connection state. ALWAYS call before describing surroundings. Never reuse old readings."),
            tool("find_target", "Select the target the user asks for. This does not confirm a detection or start the camera.", properties: ["target": ["type": "string", "enum": ["obstacles", "door", "exit", "chair", "person", "teammate"]]]),
            tool("calibrate_floor", "Calibrate only after the user supplies a measured lens height in meters and confirms the phone is mounted upright with rear camera forward and top edge to their left. Never guess height.", properties: ["measured_height_meters": ["type": "number", "minimum": 0.6, "maximum": 2.1]]),
            tool("scan_pucks", "Begin Bluetooth discovery when the user asks to connect. Wait briefly, then list_pucks. Do not select a device yourself."),
            tool("list_pucks", "List currently discovered puck IDs and names. Ask the user which one to connect, even if there is only one."),
            tool("connect_puck", "Connect ONLY the device explicitly selected by the user from list_pucks. Use the exact returned ID.", properties: ["device_id": ["type": "string"]]),
            tool("open_settings", "Open the existing settings panel for manual setup, including teammate consent.")
        ]
    }

    static let instructions = """
    You are FEEL, the voice interface to a camera and tactile puck prototype.
    Speak naturally in the user's language. Keep each answer short enough to hear while using the camera.
    Use the provided tools for app actions. Never claim an action succeeded before reading its result.
    Before any statement about the current scene, call get_status. You cannot see camera images.
    Describe only observations returned by the tools. Unknown, stale and neutral are never evidence that a path is clear.
    Do not give walking directions, promise safe passage, identify unobserved objects or invent distances.
    A door candidate is only a rectangle candidate, not a confirmed door or safe opening.
    Simulation is synthetic and must always be called simulation. Ask for a measured height before calibration.
    Never start the camera, calibrate, or connect hardware without the user's request. Explicitly ask which discovered puck to connect.
    If the user says stop, call stop immediately. Keep listening afterward. Do not ask for confirmation.
    If they ask you to stop listening or pause the assistant, call pause_assistant.
    If a target is unavailable, say you haven't found it. Offer supported target choices when the request is unsupported.
    You may understand natural conversation, but keep app state and hardware actions within these tools.
    """
}
