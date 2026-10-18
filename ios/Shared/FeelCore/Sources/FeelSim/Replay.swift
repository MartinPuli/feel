import Foundation
import FeelCore

/// Replays recorded frames through the app's per-frame depth step and its 10 Hz transmit tick,
/// producing the exact packets the phone would send. Not modelled: point-to-describe freezing,
/// direction arrows, teammate (UWB) targets and BLE transport.
public struct ReplayOptions: Sendable {
    public var tickPeriod = 0.1
    /// First tick after the first frame; later ticks keep this phase.
    public var tickOffset = 0.05
    /// Frame timestamp → frame available to the tick (processing plus main-queue hop).
    public var deliveryLatency = 0.02
    /// Keep ticking this long after the last frame, to show staleness handling.
    public var tail = 0.5
    public init() {}
}

public struct ReplayTick: Encodable, Equatable, Sendable {
    public struct Target: Encodable, Equatable, Sendable { public let label: String, bearing: Double, distance: Double }
    public let t: Double
    public let seq: Int
    public let hex: String
    public let bands: [UInt8]
    public let highlight: UInt8
    public let state: String
    /// Timestamp of the frame this tick used, nil before the first frame arrives.
    public let frame: Double?
    public let distances: [Double?]
    public let targetColumns: [Int]?
    public let target: Target?
}

public enum SessionReplayer {
    struct Processed { let frame: RecordedFrame; let tracking: Bool; let distances: [Double?]; let target: TargetObservation? }

    /// ARPerception.session(_:didUpdate:) without the Vision and floor-map side effects.
    static func process(_ frame: RecordedFrame) -> Processed {
        guard frame.trackingNormal, DepthFrameProcessor.mountValid(frame.pose), let depth=frame.depth else {
            return Processed(frame:frame,tracking:false,distances:Array(repeating:nil,count:7),target:nil)
        }
        let result=DepthFrameProcessor.process(depth,pose:frame.pose,floorY:frame.floorY)
        return Processed(frame:frame,tracking:true,distances:result.distances,target:frame.target?.observation(pose:frame.pose,now:frame.timestamp))
    }

    public static func run(_ frames: [RecordedFrame], options: ReplayOptions = .init()) -> [ReplayTick] {
        let frames=frames.sorted { $0.timestamp<$1.timestamp }
        guard let first=frames.first, let last=frames.last else { return [] }
        var ticks:[ReplayTick]=[]
        var sequence: UInt8=0
        var next=0
        var current: Processed?
        var rhythm=TapRhythm()   // the phone's presence taps (LanternModel applies the same), so a replay shows what the puck would do
        var k=0
        while true {
            let now=first.timestamp+options.tickOffset+Double(k)*options.tickPeriod; k += 1
            if now>last.timestamp+options.tail+1e-9 { break }
            while next<frames.count, frames[next].timestamp+options.deliveryLatency<=now+1e-9 { current=process(frames[next]); next += 1 }
            sequence &+= 1
            // LanternModel.tick(), live mode, no pointing or arrows; TapRhythm applied as the model applies it.
            guard let frame=current else {
                rhythm.reset()
                let packet=FeelPacket.neutral(sequence:sequence)
                ticks.append(ReplayTick(t:now,seq:Int(sequence),hex:packet.hex,bands:packet.bands,highlight:packet.highlight,state:GuidanceState.staleDepth.rawValue,
                                        frame:nil,distances:Array(repeating:nil,count:7),targetColumns:nil,target:nil))
                continue
            }
            let output=rhythm.apply(to:TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:frame.frame.timestamp,tracking:frame.tracking,distances:frame.distances,
                                                             target:frame.target,floorCalibrated:frame.frame.floorY != nil))
            let target=frame.target.flatMap { $0.valid(at:now) && output.state == .live ? ReplayTick.Target(label:$0.label,bearing:$0.bearingDegrees,distance:$0.distance) : nil }
            ticks.append(ReplayTick(t:now,seq:Int(sequence),hex:output.packet.hex,bands:output.packet.bands,highlight:output.packet.highlight,state:output.state.rawValue,
                                    frame:frame.frame.timestamp,distances:frame.distances,targetColumns:output.targetColumns.map { Array($0) },target:target))
        }
        return ticks
    }
}
