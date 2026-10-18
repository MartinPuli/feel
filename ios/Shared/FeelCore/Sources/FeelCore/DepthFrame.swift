import Foundation

/// One LiDAR depth map in native sensor orientation (origin top-left), with intrinsics
/// already scaled to the depth map's resolution. Depth is metres along the optical axis.
public struct DepthFrame: Equatable, Sendable {
    public let width: Int, height: Int
    public let depths: [Float]
    /// ARKit confidence: 0 low, 1 medium, 2 high. Only 1 and 2 are ever used.
    public let confidence: [UInt8]
    public let intrinsics: CameraIntrinsics
    public init?(width: Int, height: Int, depths: [Float], confidence: [UInt8], intrinsics: CameraIntrinsics) {
        guard width>0, height>0, depths.count == width*height, confidence.count == width*height else { return nil }
        self.width=width; self.height=height; self.depths=depths; self.confidence=confidence; self.intrinsics=intrinsics
    }
    /// Median of usable depths in a 5×5 window, as used to place a detection box.
    public func medianDepth(x: Double, y: Double) -> Double? {
        guard x.isFinite,y.isFinite,x>=0,y>=0,x<Double(width),y<Double(height) else { return nil }
        var values:[Double]=[]
        for yy in max(0,Int(y)-2)...min(height-1,Int(y)+2) {
            for xx in max(0,Int(x)-2)...min(width-1,Int(x)+2) {
                let i=yy*width+xx,value=Double(depths[i])
                if confidence[i]>=1,confidence[i]<=2,value.isFinite,value>0,value<=4 { values.append(value) }
            }
        }
        guard values.count>=3 else { return nil }; values.sort(); return values[values.count/2]
    }
}

/// The per-frame depth step shared by the app and offline replay: depth map → six sector ranges plus one reserved wire slot
/// plus the sparse world points that feed the floor map.
public enum DepthFrameProcessor {
    public struct Result: Equatable, Sendable { public let distances: [Double?]; public let mapPoints: [Vector3] }
    /// Phone mounted landscape-left, upright, facing forward.
    public static func mountValid(_ pose: CameraPose) -> Bool { pose.isValid && pose.up.y>0.7 && abs(pose.right.y)<0.35 }
    public static func process(_ map: DepthFrame, pose: CameraPose, floorY: Double?) -> Result {
        let k=map.intrinsics
        var samples:[DepthSample]=[]; samples.reserveCapacity(map.width*map.height/9)
        var mapPoints:[Vector3]=[]; mapPoints.reserveCapacity(map.width*map.height/36)
        for y in stride(from:0,to:map.height,by:3) {
            for x in stride(from:0,to:map.width,by:3) {
                let i=y*map.width+x
                if let point=k.unproject(x:Double(x),y:Double(y),depth:Double(map.depths[i])) {
                    samples.append(.init(cameraPoint:point,confidence:map.confidence[i]))
                    // Every sixth pixel feeds the floor map; low-confidence depth never does.
                    if x%6==0, y%6==0, map.confidence[i]>=1, map.confidence[i]<=2 { mapPoints.append(pose.worldPoint(camera:point)) }
                }
            }
        }
        return Result(distances:DepthProjector.sectors(samples:samples,pose:pose,floorY:floorY),mapPoints:mapPoints)
    }
}

/// One processed AR frame as the phone saw it, for offline replay. `target` is the detector's
/// cached result at that moment; the detector itself is not re-run offline.
public struct RecordedFrame: Equatable, Sendable {
    public var timestamp: Double
    public var trackingNormal: Bool
    public var pose: CameraPose
    public var floorY: Double?
    public var target: CapturedTarget?
    public var depth: DepthFrame?
    public init(timestamp: Double, trackingNormal: Bool, pose: CameraPose, floorY: Double?, target: CapturedTarget?=nil, depth: DepthFrame?) {
        self.timestamp=timestamp; self.trackingNormal=trackingNormal; self.pose=pose; self.floorY=floorY; self.target=target; self.depth=depth
    }
}

public struct RecordingInfo: Codable, Equatable, Sendable {
    public var version: Int
    /// "iphone" or "synthetic".
    public var source: String
    public var createdAt: String
    public var cameraHeight: Double?
    public var note: String?
    public init(source: String, createdAt: String, cameraHeight: Double?=nil, note: String?=nil) {
        version=SessionRecording.version; self.source=source; self.createdAt=createdAt; self.cameraHeight=cameraHeight; self.note=note
    }
}

/// `.feelrec` file: "FEELREC1", then records of [u32 LE header length][JSON header][u32 LE payload length][payload].
/// The first record is the RecordingInfo. A frame payload is width×height little-endian Float32 depths,
/// then width×height confidence bytes; it is empty when the frame had no usable depth.
public enum SessionRecording {
    public static let version = 1
    public static let magic = Data("FEELREC1".utf8)
    public enum Failure: Error, Equatable { case badMagic, truncated, badHeader(String), badPayload }

    struct TargetHeader: Codable { var position: Vector3, timestamp: Double, confidence: Double, label: String, halfWidthMeters: Double }
    struct FrameHeader: Codable {
        var t: Double, tracking: Bool, pose: CameraPose, floorY: Double?, target: TargetHeader?
        var width: Int?, height: Int?, intrinsics: CameraIntrinsics?
    }

    public static func start(_ info: RecordingInfo) throws -> Data { var data=magic; append(&data,header:try encoder.encode(info),payload:Data()); return data }

    public static func encode(_ frame: RecordedFrame) throws -> Data {
        let target=frame.target.map { TargetHeader(position:$0.position,timestamp:$0.timestamp,confidence:$0.confidence,label:$0.label,halfWidthMeters:$0.halfWidthMeters) }
        let header=FrameHeader(t:frame.timestamp,tracking:frame.trackingNormal,pose:frame.pose,floorY:frame.floorY,target:target,
                               width:frame.depth?.width,height:frame.depth?.height,intrinsics:frame.depth?.intrinsics)
        var payload=Data()
        if let depth=frame.depth {
            payload.reserveCapacity(depth.depths.count*5)
            for value in depth.depths { withUnsafeBytes(of:value.bitPattern.littleEndian) { payload.append(contentsOf:$0) } }
            payload.append(contentsOf:depth.confidence)
        }
        var data=Data(); append(&data,header:try encoder.encode(header),payload:payload); return data
    }

    public static func decode(_ data: Data) throws -> (info: RecordingInfo, frames: [RecordedFrame]) {
        let bytes=[UInt8](data)
        guard bytes.count>=magic.count, Data(bytes[0..<magic.count])==magic else { throw Failure.badMagic }
        var offset=magic.count
        func block() throws -> ArraySlice<UInt8> {
            guard offset+4<=bytes.count else { throw Failure.truncated }
            let length=Int(UInt32(bytes[offset]) | UInt32(bytes[offset+1])<<8 | UInt32(bytes[offset+2])<<16 | UInt32(bytes[offset+3])<<24)
            offset += 4
            guard offset+length<=bytes.count else { throw Failure.truncated }
            defer { offset += length }; return bytes[offset..<offset+length]
        }
        let decoder=JSONDecoder()
        let info: RecordingInfo
        do { info=try decoder.decode(RecordingInfo.self,from:Data(try block())); _=try block() }
        catch let error as Failure { throw error } catch { throw Failure.badHeader(String(describing:error)) }
        var frames:[RecordedFrame]=[]
        while offset<bytes.count {
            let header: FrameHeader
            do { header=try decoder.decode(FrameHeader.self,from:Data(try block())) }
            catch let error as Failure { throw error } catch { throw Failure.badHeader(String(describing:error)) }
            let payload=try block()
            var depth: DepthFrame?
            if let width=header.width, let height=header.height, let k=header.intrinsics {
                let count=width*height
                guard count>0, payload.count==count*5 else { throw Failure.badPayload }
                let base=payload.startIndex
                var values=[Float](repeating:0,count:count)
                for i in 0..<count {
                    let j=base+i*4
                    values[i]=Float(bitPattern:UInt32(payload[j]) | UInt32(payload[j+1])<<8 | UInt32(payload[j+2])<<16 | UInt32(payload[j+3])<<24)
                }
                depth=DepthFrame(width:width,height:height,depths:values,confidence:Array(payload[(base+count*4)...]),intrinsics:k)
                guard depth != nil else { throw Failure.badPayload }
            } else if !payload.isEmpty { throw Failure.badPayload }
            let target=header.target.map { CapturedTarget(position:$0.position,timestamp:$0.timestamp,confidence:$0.confidence,label:$0.label,halfWidthMeters:$0.halfWidthMeters) }
            frames.append(RecordedFrame(timestamp:header.t,trackingNormal:header.tracking,pose:header.pose,floorY:header.floorY,target:target,depth:depth))
        }
        return (info,frames)
    }

    private static let encoder: JSONEncoder = { let e=JSONEncoder(); e.outputFormatting=[.sortedKeys]; return e }()
    private static func append(_ data: inout Data, header: Data, payload: Data) {
        for block in [header,payload] {
            withUnsafeBytes(of:UInt32(block.count).littleEndian) { data.append(contentsOf:$0) }
            data.append(block)
        }
    }
}
