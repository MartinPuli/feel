import Foundation
import FeelCore

struct TargetInput: Decodable {
    var bearingDegrees: Double, distance: Double, timestamp: Double
    var confidence: Double?, label: String?
    var observation: TargetObservation { .init(bearingDegrees:bearingDegrees,distance:distance,timestamp:timestamp,confidence:confidence ?? 1,label:label ?? "target") }
}
struct PoseInput: Decodable {
    var position: [Double], right: [Double], up: [Double], back: [Double]
    func pose() throws -> CameraPose {
        func vector(_ values: [Double]) throws -> Vector3 {
            guard values.count==3 else { throw CommandError.range("pose vectors require three numbers") }
            return Vector3(values[0],values[1],values[2])
        }
        return try CameraPose(position:vector(position),right:vector(right),up:vector(up),back:vector(back))
    }
}
struct Command: Decodable {
    var op: String
    var seq: Int?, bands: [Int]?, highlight: Int?, hex: String?
    var now: Double?, frameTimestamp: Double?, tracking: Bool?, distances: [Double?]?, target: TargetInput?, floorCalibrated: Bool?
    var expectedHex: String?
    var session: String?, id: String?, name: String?, pose: PoseInput?
    var text:String?,language:VoiceLanguage?,`final`:Bool?,profile:AdaptiveProfile?
    var mapID:String?,anchorID:String?,mapDataBase64:String?,archive:PersistentMemoryArchive?,relocalizing:Bool?
}
struct Reply: Encodable {
    var valid: Bool
    var hex: String?, seq: Int?, bands: [UInt8]?, highlight: UInt8?, state: String?, error: String?
    var memory: SpatialMemorySnapshot?, memoryState: String?, distance: Double?, horizontalDistance: Double?, bearingDegrees: Double?, targetName: String?
    var intent:VoiceIntent?,archive:PersistentMemoryArchive?,restoreState:WorldMapRestoreState?
    init() { valid=true }
    init(memory: SpatialMemorySnapshot) { valid=true; self.memory=memory }
    init(packet: FeelPacket, state: String?=nil) { valid=true; hex=packet.hex; seq=Int(packet.sequence); bands=packet.bands; highlight=packet.highlight; self.state=state }
    init(error: String) { valid=false; self.error=error }
}
enum CommandError: Error { case missing(String), range(String), mismatch(String) }
var memoryManager=SpatialMemoryManager()
var adaptiveController=AdaptiveTactileController()
var restoreGate=WorldMapRestoreGate()
func execute(_ command: Command) throws -> Reply {
    func byte(_ value: Int?, _ field: String) throws -> UInt8 {
        guard let value else { throw CommandError.missing(field) }
        guard let result=UInt8(exactly:value) else { throw CommandError.range(field) }; return result
    }
    func required<T>(_ value: T?, _ name: String) throws -> T {
        guard let value else { throw CommandError.missing(name) }; return value
    }
    func memoryPose() throws -> MemoryPose {
        try MemoryPose(session:required(command.session,"session"),pose:required(command.pose,"pose").pose(),timestamp:required(command.frameTimestamp,"frameTimestamp"),tracking:required(command.tracking,"tracking"))
    }
    var reply: Reply
    switch command.op {
    case "decode":
        guard let hex=command.hex else { throw CommandError.missing("hex") }
        reply=Reply(packet:try FeelPacket(hex:hex))
    case "encode":
        guard let bands=command.bands else { throw CommandError.missing("bands") }
        reply=Reply(packet:try FeelPacket(sequence:byte(command.seq,"seq"),bands:bands.map { try byte($0,"band") },highlight:byte(command.highlight ?? 255,"highlight")))
    case "perceive":
        guard let now=command.now,let time=command.frameTimestamp,let tracking=command.tracking,let distances=command.distances else { throw CommandError.missing("perceive fields") }
        let output=TactileEncoder.encode(sequence:try byte(command.seq,"seq"),now:now,frameTimestamp:time,tracking:tracking,distances:distances,target:command.target?.observation,floorCalibrated:command.floorCalibrated ?? true)
        reply=Reply(packet:output.packet,state:output.state.rawValue)
    case "memoryBegin":
        try memoryManager.begin(session:required(command.session,"session")); restoreGate.cancel(); reply=Reply(memory:memoryManager.snapshot)
    case "memoryEnd":
        memoryManager.end(); restoreGate.cancel(); reply=Reply(memory:memoryManager.snapshot)
    case "memoryState": reply=Reply(memory:memoryManager.snapshot)
    case "memoryRemember":
        try memoryManager.remember(id:required(command.id,"id"),name:required(command.name,"name"),sample:memoryPose(),now:required(command.now,"now")); reply=Reply(memory:memoryManager.snapshot)
    case "memorySelect":
        try memoryManager.select(id:required(command.id,"id")); reply=Reply(memory:memoryManager.snapshot)
    case "memoryRename":
        try memoryManager.rename(id:required(command.id,"id"),name:required(command.name,"name")); reply=Reply(memory:memoryManager.snapshot)
    case "memoryDelete":
        try memoryManager.delete(id:required(command.id,"id")); reply=Reply(memory:memoryManager.snapshot)
    case "memoryRecall":
        try memoryManager.recall(id:command.id); reply=Reply(memory:memoryManager.snapshot)
    case "memorySetReturn":
        try memoryManager.setReturnPoint(sample:memoryPose(),now:required(command.now,"now")); reply=Reply(memory:memoryManager.snapshot)
    case "memoryReturn":
        try memoryManager.returnToStart(); reply=Reply(memory:memoryManager.snapshot)
    case "memoryStop":
        memoryManager.stopGuidance(); reply=Reply(memory:memoryManager.snapshot)
    case "memoryGuide":
        let result=try memoryManager.encode(sequence:byte(command.seq,"seq"),sample:memoryPose(),now:required(command.now,"now"),distances:required(command.distances,"distances"),floorCalibrated:command.floorCalibrated ?? true)
        reply=Reply(packet:result.output.packet,state:result.output.state.rawValue)
        reply.memory=memoryManager.snapshot; reply.memoryState=result.guidance.state.rawValue
        reply.distance=result.guidance.distance; reply.horizontalDistance=result.guidance.horizontalDistance; reply.bearingDegrees=result.guidance.bearingDegrees; reply.targetName=result.guidance.targetName
    case "voiceParse":
        reply=Reply(); reply.intent=try VoiceIntentParser.parse(text:required(command.text,"text"),language:required(command.language,"language"),isFinal:required(command.final,"final"))
    case "adaptive":
        let packet=try FeelPacket(sequence:byte(command.seq,"seq"),bands:required(command.bands,"bands").map { try byte($0,"band") },highlight:byte(command.highlight ?? 255,"highlight"))
        reply=Reply(packet:try adaptiveController.apply(packet:packet,profile:required(command.profile,"profile"),session:required(command.session,"session"),now:required(command.now,"now")))
    case "adaptiveReset": adaptiveController.reset(); reply=Reply()
    case "archiveExport":
        guard memoryManager.session != nil else { throw SpatialMemoryError.noSession }
        guard let data=Data(base64Encoded:try required(command.mapDataBase64,"mapDataBase64")) else { throw CommandError.range("mapDataBase64") }
        reply=Reply(); reply.archive=try PersistentMemoryArchive(mapID:required(command.mapID,"mapID"),anchorID:required(command.anchorID,"anchorID"),mapData:data,snapshot:memoryManager.snapshot)
    case "archiveImport":
        // Validate the entire proposed transition on copies before clearing active places.
        let archive=try required(command.archive,"archive"),session=try required(command.session,"session")
        var nextGate=WorldMapRestoreGate(),nextMemory=memoryManager
        try nextGate.begin(archive:archive,session:session,now:required(command.now,"now"))
        try nextMemory.begin(session:session)
        restoreGate=nextGate; memoryManager=nextMemory
        reply=Reply(memory:memoryManager.snapshot); reply.restoreState=restoreGate.state
    case "archiveObserve":
        let wasReady=restoreGate.state == .ready
        let state=try restoreGate.observe(session:required(command.session,"session"),mapID:required(command.mapID,"mapID"),anchorID:command.anchorID,now:required(command.now,"now"),sample:memoryPose(),relocalizing:required(command.relocalizing,"relocalizing"))
        if state == .ready,!wasReady,let archive=restoreGate.archive,let session=restoreGate.session { try memoryManager.restore(archive:archive,session:session) }
        if state == .failed { memoryManager.end() }
        reply=Reply(memory:memoryManager.snapshot); reply.restoreState=state
    case "archiveCancel":
        restoreGate.cancel(); memoryManager.end(); reply=Reply(memory:memoryManager.snapshot); reply.restoreState=restoreGate.state
    default: throw CommandError.missing("Unknown op: \(command.op)")
    }
    if let expected=command.expectedHex, expected.lowercased() != reply.hex { throw CommandError.mismatch("expected \(expected), got \(reply.hex ?? "nil")") }
    return reply
}
let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
func emit(_ reply: Reply) { var data=try! encoder.encode(reply); data.append(10); FileHandle.standardOutput.write(data) }
func run(_ data: Data) -> Bool {
    do {
        guard data.count<=PersistentMemoryArchive.maxJSONBytes else { throw CommandError.range("command exceeds 24 MiB") }
        emit(try execute(JSONDecoder().decode(Command.self,from:data))); return true
    }
    catch { emit(Reply(error:String(describing:error))); return false }
}
let args=Array(CommandLine.arguments.dropFirst())
if args.first == "stdio" {
    while let line=readLine() { _=run(Data(line.utf8)) }
} else if args.first == "replay",args.count == 2 {
    do {
        let commands=try JSONDecoder().decode([Command].self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        guard !commands.isEmpty else { throw CommandError.missing("Replay is empty") }
        for command in commands { emit(try execute(command)) }
    } catch { emit(Reply(error:String(describing:error))); exit(1) }
} else if args.first == "decode",args.count == 2 {
    if !run(try! JSONSerialization.data(withJSONObject:["op":"decode","hex":args[1]])) { exit(1) }
} else {
    FileHandle.standardError.write(Data("Usage: feel-replay stdio | replay fixtures.json | decode <18 hex digits>\nJSON ops: encode, decode, perceive, memory*. See docs/SPATIAL-MEMORY.md.\n".utf8)); exit(2)
}
