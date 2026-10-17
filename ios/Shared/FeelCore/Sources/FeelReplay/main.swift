import Foundation
import FeelCore

struct TargetInput: Decodable {
    var bearingDegrees: Double, distance: Double, timestamp: Double
    var confidence: Double?, label: String?
    var observation: TargetObservation { .init(bearingDegrees:bearingDegrees,distance:distance,timestamp:timestamp,confidence:confidence ?? 1,label:label ?? "target") }
}
struct Command: Decodable {
    var op: String
    var seq: Int?, bands: [Int]?, highlight: Int?, hex: String?
    var now: Double?, frameTimestamp: Double?, tracking: Bool?, distances: [Double?]?, target: TargetInput?, floorCalibrated: Bool?
    var expectedHex: String?
}
struct Reply: Encodable {
    var valid: Bool
    var hex: String?, seq: Int?, bands: [UInt8]?, highlight: UInt8?, state: String?, error: String?
    init(packet: FeelPacket, state: String?=nil) { valid=true; hex=packet.hex; seq=Int(packet.sequence); bands=packet.bands; highlight=packet.highlight; self.state=state }
    init(error: String) { valid=false; self.error=error }
}
enum CommandError: Error { case missing(String), range(String), mismatch(String) }
func execute(_ command: Command) throws -> Reply {
    func byte(_ value: Int?, _ field: String) throws -> UInt8 {
        guard let value else { throw CommandError.missing(field) }
        guard let result=UInt8(exactly:value) else { throw CommandError.range(field) }; return result
    }
    let reply: Reply
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
    default: throw CommandError.missing("Unknown op: \(command.op)")
    }
    if let expected=command.expectedHex, expected.lowercased() != reply.hex { throw CommandError.mismatch("expected \(expected), got \(reply.hex ?? "nil")") }
    return reply
}
let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
func emit(_ reply: Reply) { var data=try! encoder.encode(reply); data.append(10); FileHandle.standardOutput.write(data) }
func run(_ data: Data) -> Bool {
    do { emit(try execute(JSONDecoder().decode(Command.self,from:data))); return true }
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
    FileHandle.standardError.write(Data("Usage: feel-replay stdio | replay fixtures.json | decode <18 hex digits>\nJSON ops: encode, decode, perceive. See ios/README.md.\n".utf8)); exit(2)
}
