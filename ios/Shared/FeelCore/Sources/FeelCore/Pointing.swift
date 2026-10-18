import Foundation

/// Point-to-describe. The user holds the puck's back toward the camera (palm toward the phone,
/// thumb up) and points at a cell with the other hand. Printed QR codes on the back give the
/// puck's position in the image; a taped fingertip gives the cell; the answer describes the scene
/// cached from just before the hand came up. Geometry only: accuracy on a real hand is unmeasured.

/// A 2-D point: image pixels (x right, y down) or the puck-back sheet (mm, see PuckBackLayout).
public struct PlanePoint: Equatable, Codable, Sendable {
    public var x: Double, y: Double
    public init(_ x: Double, _ y: Double) { self.x=x; self.y=y }
    public var isFinite: Bool { x.isFinite && y.isFinite }
    public func distance(to p: PlanePoint) -> Double { hypot(x-p.x,y-p.y) }
}

/// Projective map between two planes. Row-major 3×3.
public struct Homography: Equatable, Sendable {
    public let m: [Double]
    public init?(_ m: [Double]) {
        guard m.count == 9, m.allSatisfy(\.isFinite), abs(Self.det(m))>1e-15 else { return nil }
        self.m=m
    }
    public func apply(_ p: PlanePoint) -> PlanePoint? {
        let w=m[6]*p.x+m[7]*p.y+m[8]
        guard p.isFinite, abs(w)>1e-12 else { return nil }
        let r=PlanePoint((m[0]*p.x+m[1]*p.y+m[2])/w,(m[3]*p.x+m[4]*p.y+m[5])/w)
        return r.isFinite ? r : nil
    }
    public var inverse: Homography? {
        let d=Self.det(m)
        let a=[m[4]*m[8]-m[5]*m[7], m[2]*m[7]-m[1]*m[8], m[1]*m[5]-m[2]*m[4],
               m[5]*m[6]-m[3]*m[8], m[0]*m[8]-m[2]*m[6], m[2]*m[3]-m[0]*m[5],
               m[3]*m[7]-m[4]*m[6], m[1]*m[6]-m[0]*m[7], m[0]*m[4]-m[1]*m[3]]
        return Homography(a.map { $0/d })
    }
    static func det(_ m: [Double]) -> Double { m[0]*(m[4]*m[8]-m[5]*m[7])-m[1]*(m[3]*m[8]-m[5]*m[6])+m[2]*(m[3]*m[7]-m[4]*m[6]) }
    public static func mul(_ a: [Double], _ b: [Double]) -> [Double] {
        (0..<9).map { i in let r=i/3,c=i%3; return a[r*3]*b[c]+a[r*3+1]*b[3+c]+a[r*3+2]*b[6+c] }
    }
    /// Least-squares fit (normalised DLT, h33 = 1) from at least 4 correspondences. Nil if degenerate.
    public static func fit(from: [PlanePoint], to: [PlanePoint]) -> Homography? {
        guard from.count == to.count, from.count >= 4, (from+to).allSatisfy(\.isFinite) else { return nil }
        func normaliser(_ p: [PlanePoint]) -> [Double]? {
            let cx=p.map(\.x).reduce(0,+)/Double(p.count), cy=p.map(\.y).reduce(0,+)/Double(p.count)
            let mean=p.map { hypot($0.x-cx,$0.y-cy) }.reduce(0,+)/Double(p.count)
            guard mean>1e-12 else { return nil }
            let s=2.0.squareRoot()/mean
            return [s,0,-s*cx, 0,s,-s*cy, 0,0,1]
        }
        guard let t1=normaliser(from),let t2=normaliser(to),let t2i=Homography(t2)?.inverse else { return nil }
        var ata=[Double](repeating:0,count:64), atb=[Double](repeating:0,count:8)
        for (p,q) in zip(from,to) {
            let x=t1[0]*p.x+t1[2], y=t1[4]*p.y+t1[5], X=t2[0]*q.x+t2[2], Y=t2[4]*q.y+t2[5]
            for (row,rhs) in [([x,y,1,0,0,0,-x*X,-y*X],X),([0,0,0,x,y,1,-x*Y,-y*Y],Y)] {
                for i in 0..<8 { atb[i]+=row[i]*rhs; for j in 0..<8 { ata[i*8+j]+=row[i]*row[j] } }
            }
        }
        guard let h=solve(ata,atb,8) else { return nil }
        let hn=h+[1]
        let full=mul(t2i.m,mul(hn,t1))
        guard abs(full[8])>1e-12 else { return Homography(full) }
        return Homography(full.map { $0/full[8] })
    }
    /// Gaussian elimination with partial pivoting; nil if singular.
    static func solve(_ a: [Double], _ b: [Double], _ n: Int) -> [Double]? {
        var a=a, b=b
        for col in 0..<n {
            guard let pivot=(col..<n).max(by: { abs(a[$0*n+col])<abs(a[$1*n+col]) }), abs(a[pivot*n+col])>1e-12 else { return nil }
            if pivot != col { for k in 0..<n { a.swapAt(col*n+k,pivot*n+k) }; b.swapAt(col,pivot) }
            for row in (col+1)..<n {
                let f=a[row*n+col]/a[col*n+col]
                if f == 0 { continue }
                for k in col..<n { a[row*n+k]-=f*a[col*n+k] }; b[row]-=f*b[col]
            }
        }
        var x=[Double](repeating:0,count:n)
        for row in stride(from:n-1,through:0,by:-1) {
            var s=b[row]; for k in (row+1)..<n { s-=a[row*n+k]*x[k] }
            x[row]=s/a[row*n+row]
        }
        return x.allSatisfy(\.isFinite) ? x : nil
    }
}

/// One pin position: protocol column 0 (user's left) … 6, band 1 (wrist) … 4 (fingers).
public struct PuckCell: Hashable, Codable, Sendable, CustomStringConvertible {
    public let column: Int, band: UInt8
    public init(column: Int, band: UInt8) { self.column=column; self.band=band }
    public var description: String { "C\(column) B\(band)" }
}

/// The printed back sheet (cad/production/markers/make_back_sheet.py), production chassis per CAD.md.
/// Sheet coordinates in mm, seen from the back with the finger end up: u = −x_puck (so column 0,
/// the user's left, is on the right), v = y_puck (0 = servo horn plane, + toward the fingers).
public enum PuckBackLayout {
    public static let columnPitch = 12.0, rowPitch = 13.0, firstRowV = 14.5
    /// The sheet: the chassis bottom flat, minus the wrist strip with the zip-tie slots.
    public static let sheetMinU = -41.25, sheetMaxU = 41.25, sheetMinV = -21.0, sheetMaxV = 59.0
    /// Three QR codes (1 mm modules, 21 mm symbols) in the wrist third, top edge toward the fingers.
    public static let codeSize = 21.0, codeCenterV = -6.0
    public static let codes: [(payload: String, centerU: Double)] = [("FEEL:WL",25),("FEEL:WC",0),("FEEL:WR",-25)]
    /// Where the fingertip marker is searched: on the sheet, clear of the codes and the sheet edge.
    public static let searchMinU = -40.5, searchMaxU = 40.5, searchMinV = 8.0, searchMaxV = 58.5

    /// Symbol corners in Vision's order: top-left, top-right, bottom-right, bottom-left (top = finger end).
    public static func corners(of payload: String) -> [PlanePoint]? {
        guard let code=codes.first(where: { $0.payload == payload }) else { return nil }
        let h=codeSize/2, u=code.centerU, v=codeCenterV
        return [PlanePoint(u-h,v+h),PlanePoint(u+h,v+h),PlanePoint(u+h,v-h),PlanePoint(u-h,v-h)]
    }
    public static func center(of cell: PuckCell) -> PlanePoint {
        PlanePoint(-Double(cell.column-3)*columnPitch, firstRowV+Double(Int(cell.band)-1)*rowPitch)
    }
    public static func cell(at p: PlanePoint) -> PuckCell? {
        guard p.isFinite else { return nil }
        let x = -p.x
        let c=Int(floor((x+3.5*columnPitch)/columnPitch)), r=Int(floor((p.y-(firstRowV-rowPitch/2))/rowPitch))
        guard PuckLayout.activeColumns.contains(c), (0..<4).contains(r) else { return nil }
        return PuckCell(column:c,band:UInt8(r+1))
    }
    /// Column under a sheet u coordinate, ignoring the row.
    public static func column(atU u: Double) -> Int? {
        guard u.isFinite else { return nil }
        let c=Int(floor((-u+3.5*columnPitch)/columnPitch))
        return PuckLayout.activeColumns.contains(c) ? c : nil
    }
    /// Distance in mm from the point to the nearest edge of its cell (0 = on a boundary).
    public static func edgeMargin(at p: PlanePoint) -> Double? {
        guard let cell=cell(at:p) else { return nil }
        let c=center(of:cell)
        return min(columnPitch/2-abs(p.x-c.x),rowPitch/2-abs(p.y-c.y))
    }
}

/// Is the puck held in the pose that means "I'm asking"? Back toward the camera, roughly face-on,
/// fingers pointing sideways in the image (thumb up), close enough to read.
public struct PointingGateResult: Equatable, Codable, Sendable {
    public let faceOn: Bool, upright: Bool, closeEnough: Bool
    public var ok: Bool { faceOn && upright && closeEnough }
    public var reason: String {
        if ok { return "ready" }
        return [faceOn ? nil : "tilted", upright ? nil : "rotate thumb up", closeEnough ? nil : "too far"].compactMap { $0 }.joined(separator:", ")
    }
}
public enum PointingGate {
    public static var maxSideRatio = 1.3
    public static var rotationToleranceDegrees = 35.0
    public static var minWidthFraction = 0.12
    /// `sheetToImage` maps sheet mm to image pixels (x right, y down).
    public static func evaluate(_ sheetToImage: Homography, imageWidth: Double) -> PointingGateResult? {
        let L=PuckBackLayout.self
        guard imageWidth>0,
              let a=sheetToImage.apply(PlanePoint(L.sheetMinU,L.sheetMinV)), let b=sheetToImage.apply(PlanePoint(L.sheetMaxU,L.sheetMinV)),
              let c=sheetToImage.apply(PlanePoint(L.sheetMaxU,L.sheetMaxV)), let d=sheetToImage.apply(PlanePoint(L.sheetMinU,L.sheetMaxV)),
              let wrist=sheetToImage.apply(PlanePoint(0,L.sheetMinV)), let fingers=sheetToImage.apply(PlanePoint(0,L.sheetMaxV)) else { return nil }
        let bottom=a.distance(to:b), top=d.distance(to:c), left=a.distance(to:d), right=b.distance(to:c)
        guard min(bottom,top,left,right)>0 else { return nil }
        // A printed sheet seen from the front can't be mirrored; a mirrored fit is a bad fit.
        let cross=(b.x-a.x)*(d.y-a.y)-(b.y-a.y)*(d.x-a.x)
        let faceOn=cross<0 && max(bottom,top)/min(bottom,top) <= maxSideRatio && max(left,right)/min(left,right) <= maxSideRatio
        let angle=atan2(-(fingers.y-wrist.y),fingers.x-wrist.x)*180 / .pi
        let upright=abs(angle) <= rotationToleranceDegrees || abs(angle) >= 180-rotationToleranceDegrees
        let closeEnough=(bottom+top)/2 >= minWidthFraction*imageWidth
        return .init(faceOn:faceOn,upright:upright,closeEnough:closeEnough)
    }
}

/// Fingertip marker: a short band of black, blue or green tape around each pointing fingertip.
/// Index black and middle blue keeps two fingers apart even when they touch.
public enum FingertipMarker {
    public static var minArea = 20, maxArea = 900   // samples at 1 mm spacing ≈ mm²
    public enum Color: Equatable, Sendable { case dark, colored }
    /// Rejects white paper, grey print, skin and red/orange/yellow (skin-like hues).
    public static func color(r: Double, g: Double, b: Double) -> Color? {
        let luma=0.299*r+0.587*g+0.114*b
        if luma<0.2 { return .dark }
        let hi=max(r,g,b), lo=min(r,g,b)
        guard hi>=0.2, (hi-lo)/hi>=0.45 else { return nil }
        let hue: Double
        if hi == r { hue=60*(((g-b)/(hi-lo)).truncatingRemainder(dividingBy:6)) }
        else if hi == g { hue=60*((b-r)/(hi-lo)+2) } else { hue=60*((r-g)/(hi-lo)+4) }
        let h=hue<0 ? hue+360 : hue
        return h>=90 && h<=270 ? .colored : nil
    }
    public static func isMarker(r: Double, g: Double, b: Double) -> Bool { color(r:r,g:g,b:b) != nil }

    /// A connected patch of one tape colour, in sheet mm.
    public struct Blob: Equatable, Sendable {
        public let centroid: PlanePoint, area: Int, color: Color
        /// Lengths of an equivalent uniform rectangle along and across its main axis, and that axis.
        public let majorLength: Double, minorLength: Double, axis: PlanePoint
    }
    /// Same-colour 4-connected blobs within [minArea, maxArea], largest first. Sample (i, j) of the
    /// `width`×`height` grid is at sheet point (minU + i·step, minV + j·step).
    public static func blobs(_ colors: [Color?], width: Int, height: Int, minU: Double, minV: Double, step: Double) -> [Blob] {
        guard width>0, height>0, colors.count == width*height else { return [] }
        var seen=[Bool](repeating:false,count:colors.count), found: [Blob] = []
        for start in colors.indices {
            guard let color=colors[start], !seen[start] else { continue }
            var blob=[start], k=0; seen[start]=true
            while k<blob.count {
                let i=blob[k]; k+=1
                let x=i%width, y=i/width
                for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx>=0 && ny>=0 && nx<width && ny<height {
                    let n=ny*width+nx
                    if colors[n] == color && !seen[n] { seen[n]=true; blob.append(n) }
                }
            }
            guard blob.count>=minArea, blob.count<=maxArea else { continue }
            let pts=blob.map { PlanePoint(minU+step*Double($0%width),minV+step*Double($0/width)) }
            let n=Double(pts.count), mx=pts.map(\.x).reduce(0,+)/n, my=pts.map(\.y).reduce(0,+)/n
            let sxx=pts.map { ($0.x-mx)*($0.x-mx) }.reduce(0,+)/n, syy=pts.map { ($0.y-my)*($0.y-my) }.reduce(0,+)/n
            let sxy=pts.map { ($0.x-mx)*($0.y-my) }.reduce(0,+)/n
            let mid=(sxx+syy)/2, spread=(((sxx-syy)/2)*((sxx-syy)/2)+sxy*sxy).squareRoot()
            let theta=0.5*atan2(2*sxy,sxx-syy)
            found.append(Blob(centroid:PlanePoint(mx,my),area:blob.count,color:color,majorLength:(12*(mid+spread)).squareRoot(),
                              minorLength:(12*max(0,mid-spread)).squareRoot(),axis:PlanePoint(cos(theta),sin(theta))))
        }
        return found.sorted { $0.area>$1.area }
    }
    /// Centroid of the largest 4-connected marker blob on a `width`×`height` grid whose sample (i, j)
    /// is at sheet point (minU + i·step, minV + j·step). Nil if the blob is missing, tiny or huge.
    public static func locate(_ mask: [Bool], width: Int, height: Int, minU: Double, minV: Double, step: Double) -> PlanePoint? {
        guard width>0, height>0, mask.count == width*height else { return nil }
        var seen=[Bool](repeating:false,count:mask.count), best: [Int] = []
        for start in mask.indices where mask[start] && !seen[start] {
            var blob=[start], k=0; seen[start]=true
            while k<blob.count {
                let i=blob[k]; k+=1
                let x=i%width, y=i/width
                for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx>=0 && ny>=0 && nx<width && ny<height {
                    let n=ny*width+nx
                    if mask[n] && !seen[n] { seen[n]=true; blob.append(n) }
                }
            }
            if blob.count>best.count { best=blob }
        }
        guard best.count>=minArea, best.count<=maxArea else { return nil }
        let n=Double(best.count)
        return PlanePoint(minU+step*best.map { Double($0%width) }.reduce(0,+)/n, minV+step*best.map { Double($0/width) }.reduce(0,+)/n)
    }
}

/// One finger describes a cell; two fingers laid along a column ask for a route that way.
public enum FingerReading: Equatable, Sendable {
    case none, one(PlanePoint), two(PlanePoint, PlanePoint)
}
public enum FingerCounter {
    /// Two separate taped tips are about a finger's width apart.
    public static var pairDistance = 8.0...40.0
    /// Two same-colour fingers pressed together merge into one long blob; a single band is roundish.
    public static var mergedMinLength = 22.0, mergedMinAspect = 1.6
    public static func read(_ blobs: [FingertipMarker.Blob]) -> FingerReading {
        guard let a=blobs.first else { return .none }
        if blobs.count>=2, pairDistance.contains(a.centroid.distance(to:blobs[1].centroid)) { return .two(a.centroid,blobs[1].centroid) }
        if a.majorLength>=mergedMinLength, a.minorLength>0, a.majorLength/a.minorLength>=mergedMinAspect {
            let half=(a.majorLength-a.minorLength)/2
            return .two(PlanePoint(a.centroid.x+a.axis.x*half,a.centroid.y+a.axis.y*half),PlanePoint(a.centroid.x-a.axis.x*half,a.centroid.y-a.axis.y*half))
        }
        return .one(a.centroid)
    }
}

public enum FingertipMethod: String, Codable, Sendable { case marker, handPose }
/// One analysed camera frame.
public struct PointingObservation: Equatable, Sendable {
    public let timestamp: Double
    public let codesSeen: Int
    public let gate: PointingGateResult?
    /// Fingertip on the sheet, mm.
    public let fingertip: PlanePoint?
    /// The second fingertip when two fingers point.
    public let secondTip: PlanePoint?
    public let method: FingertipMethod?
    public init(timestamp: Double, codesSeen: Int, gate: PointingGateResult?, fingertip: PlanePoint?, method: FingertipMethod?, secondTip: PlanePoint? = nil) {
        self.timestamp=timestamp; self.codesSeen=codesSeen; self.gate=gate; self.fingertip=fingertip; self.method=method
        self.secondTip=fingertip == nil ? nil : secondTip
    }
    public var fingers: Int { fingertip == nil ? 0 : secondTip == nil ? 1 : 2 }
    /// One finger: the cell under it.
    public var cell: PuckCell? { secondTip == nil ? fingertip.flatMap(PuckBackLayout.cell(at:)) : nil }
    /// Most sideways offset (mm) two fingertips may have and still mark one column.
    public static var columnAlignment = 7.0
    /// Two fingers laid along one column: that column. Nil when they straddle columns.
    public var routeColumn: Int? {
        guard let a=fingertip, let b=secondTip, abs(a.x-b.x)<=Self.columnAlignment else { return nil }
        return PuckBackLayout.column(atU:(a.x+b.x)/2)
    }
}

/// What the pins showed at one moment, enough to re-encode it.
public struct CachedScene: Equatable, Sendable {
    public let timestamp: Double, pose: CameraPose, tracking: Bool, distances: [Double?], target: TargetObservation?
    public init(timestamp: Double, pose: CameraPose, tracking: Bool, distances: [Double?], target: TargetObservation?) {
        self.timestamp=timestamp; self.pose=pose; self.tracking=tracking; self.distances=distances; self.target=target
    }
    /// Nearest reading in any column, nil if none.
    public var nearest: Double? { distances.compactMap { $0 }.filter { $0.isFinite && $0>0 }.min() }
}
public struct SceneCache: Sendable {
    public var duration = 4.0
    public private(set) var entries: [CachedScene] = []
    public init() {}
    public mutating func append(_ scene: CachedScene) {
        guard scene.timestamp.isFinite, scene.timestamp>(entries.last?.timestamp ?? -.infinity) else { return }
        entries.append(scene)
        entries.removeAll { $0.timestamp<scene.timestamp-duration }
    }
    public mutating func removeAll() { entries.removeAll() }
    /// The newest tracked scene before the hand came up. Prefers one at least `leadIn` before the
    /// codes were first seen with nothing nearer than `handClearance` (an arm in front of the
    /// camera reads as very near); otherwise falls back to one `fallbackLeadIn` before.
    public func reference(firstSeen: Double, leadIn: Double, fallbackLeadIn: Double, handClearance: Double) -> CachedScene? {
        let tracked=entries.filter(\.tracking)
        if let clean=tracked.last(where: { $0.timestamp<=firstSeen-leadIn && ($0.nearest ?? .infinity)>=handClearance }) { return clean }
        return tracked.last(where: { $0.timestamp<=firstSeen-fallbackLeadIn })
    }
}

public enum PointingEvent: Equatable, Sendable {
    /// Gesture held: pins now show the cached scene.
    case armed
    case described(PuckCell, String)
    case refused(String)
    /// Two fingers held on a column: a route goal was set, with what to say.
    case routeSet(PointingRoute, String)
    /// The cached scene got too old to describe.
    case expired
    /// The puck was lowered; carries the route to start, if one was set.
    case released(PointingRoute?)
}

public struct PointingController: Sendable {
    public enum Phase: Equatable, Sendable { case idle, armed(CachedScene), expired, refused }
    public var armSeconds = 0.5, releaseSeconds = 0.6, dwellSeconds = 0.4
    /// Two fingers must hold a column a little longer, so the switch from one finger doesn't route.
    public var twoFingerSeconds = 0.6
    /// The user chose 2–3 s; matches the app's 3 s rule for spoken scene descriptions.
    public var maxReferenceAge = 3.0
    public var maxHeadingChangeDegrees = 10.0
    public var leadIn = 0.3, fallbackLeadIn = 0.8, handClearance = 0.45
    /// A tracked pose older than this can't confirm the user hasn't turned.
    public var poseMaxAge = 1.0
    public private(set) var phase: Phase = .idle
    public private(set) var cache = SceneCache()
    public private(set) var lastObservation: PointingObservation?
    private var firstSeen: Double?, lastCodes: Double?, gateSince: Double?, lastGateOK: Double?
    private var dwellCell: PuckCell?, dwellSince: Double?, lastDescribed: PuckCell?
    private var routeColumn: Int?, routeSince: Double?, lastRouted: Int?
    /// Route set during this gesture, handed over when the puck is lowered.
    public private(set) var pendingRoute: PointingRoute?
    private var trackedPose: (pose: CameraPose, time: Double)?
    public init() {}
    public var isActive: Bool { phase != .idle }

    public mutating func reset() {
        phase = .idle; cache.removeAll(); lastObservation=nil; clearGesture(); trackedPose=nil
    }
    private mutating func clearGesture() {
        firstSeen=nil; lastCodes=nil; gateSince=nil; lastGateOK=nil; dwellCell=nil; dwellSince=nil; lastDescribed=nil
        routeColumn=nil; routeSince=nil; lastRouted=nil; pendingRoute=nil
    }
    /// Feed every live perception frame (10 Hz).
    public mutating func record(_ scene: CachedScene) {
        cache.append(scene)
        if scene.tracking, scene.pose.isValid { trackedPose=(scene.pose,scene.timestamp) }
    }
    public static func headingChange(from a: CameraPose, to b: CameraPose) -> Double? {
        // Forward is -back; compare on the horizontal plane (world y up).
        let ax = -a.back.x, az = -a.back.z, bx = -b.back.x, bz = -b.back.z
        guard hypot(ax,az)>1e-6, hypot(bx,bz)>1e-6 else { return nil }
        var d=(atan2(bx,-bz)-atan2(ax,-az))*180 / .pi
        while d>180 { d-=360 }; while d < -180 { d+=360 }
        return abs(d)
    }
    private func turnedOrUnknown(since scene: CachedScene, now: Double) -> String? {
        guard let tracked=trackedPose, now-tracked.time<=poseMaxAge else { return "Tracking lost, so I can't tell if you've turned." }
        guard let change=Self.headingChange(from:scene.pose,to:tracked.pose), change<=maxHeadingChangeDegrees else { return "You've turned since then. Lower the puck and try again." }
        return nil
    }

    /// Feed every analysed camera frame. `describe` turns a cell and the cached scene into speech;
    /// `targetName` is how to say the selected target in a route confirmation.
    public mutating func update(_ o: PointingObservation, targetName: String? = nil, describe: (PuckCell, CachedScene) -> String) -> [PointingEvent] {
        let now=o.timestamp
        guard now.isFinite else { return [] }
        lastObservation=o
        var events: [PointingEvent] = []
        if o.codesSeen>0 { if firstSeen == nil || now-(lastCodes ?? now)>releaseSeconds { firstSeen=now }; lastCodes=now }
        if o.gate?.ok == true { lastGateOK=now; if gateSince == nil { gateSince=now } } else { gateSince=nil }
        events+=tick(now:now)
        switch phase {
        case .idle:
            guard let since=gateSince, now-since>=armSeconds-1e-9, let first=firstSeen else { break }
            guard let scene=cache.reference(firstSeen:first,leadIn:leadIn,fallbackLeadIn:fallbackLeadIn,handClearance:handClearance),
                  now-scene.timestamp<=maxReferenceAge else {
                phase = .refused; events.append(.refused("No recent scene from before your hand came up. Lower the puck and try again.")); break
            }
            if let reason=turnedOrUnknown(since:scene,now:now) { phase = .refused; events.append(.refused(reason)); break }
            phase = .armed(scene); events.append(.armed)
        case .armed(let scene):
            if o.fingers == 2 {
                dwellCell=nil; dwellSince=nil
                guard let column=o.routeColumn else { routeColumn=nil; routeSince=nil; break }
                if column != routeColumn { routeColumn=column; routeSince=now; break }
                guard let since=routeSince, now-since>=twoFingerSeconds-1e-9, column != lastRouted else { break }
                if let reason=turnedOrUnknown(since:scene,now:now) { phase = .refused; events.append(.refused(reason)); break }
                lastRouted=column
                switch PointingRouter.plan(column:column,scene:scene,targetName:targetName) {
                case .route(let route, let spoken): pendingRoute=route; events.append(.routeSet(route,spoken))
                case .refused(let reason): events.append(.refused(reason))
                }
                break
            }
            routeColumn=nil; routeSince=nil
            guard let cell=o.cell else { dwellCell=nil; dwellSince=nil; break }
            if cell != dwellCell { dwellCell=cell; dwellSince=now; break }
            guard let since=dwellSince, now-since>=dwellSeconds-1e-9, cell != lastDescribed else { break }
            if let reason=turnedOrUnknown(since:scene,now:now) { phase = .refused; events.append(.refused(reason)); break }
            lastDescribed=cell; events.append(.described(cell,describe(cell,scene)))
        case .expired, .refused: break
        }
        return events
    }
    /// Time-based transitions; also call from the 10 Hz loop so a stalled detector can't hold a freeze.
    public mutating func tick(now: Double) -> [PointingEvent] {
        guard phase != .idle || gateSince != nil || firstSeen != nil else { return [] }
        if let last=lastGateOK, now-last>releaseSeconds {
            let wasActive=phase != .idle, route=pendingRoute
            phase = .idle; clearGesture()
            return wasActive ? [.released(route)] : []
        }
        if lastGateOK == nil, let last=lastCodes, now-last>releaseSeconds { clearGesture() }
        if case .armed(let scene)=phase, now-scene.timestamp>maxReferenceAge { phase = .expired; return [.expired] }
        return []
    }
    /// What the pins should show while pointing: the cached scene while armed, neutral after it
    /// expires or is refused (the arm in front of the camera would otherwise read as obstacles).
    public func frozenOutput(sequence: UInt8) -> EncoderOutput? {
        switch phase {
        case .idle: return nil
        case .armed(let s):
            return TactileEncoder.encode(sequence:sequence,now:s.timestamp,frameTimestamp:s.timestamp,tracking:true,distances:s.distances,target:s.target)
        case .expired, .refused: return .init(packet:.neutral(sequence:sequence),state:.stopped)
        }
    }
}

/// Speech for one cell of the cached scene. Never claims a clear path.
public enum PointingDescriber {
    public static let directions = ["Unused","Far left","Left","Slightly left","Slightly right","Right","Far right"]
    static func meters(_ d: Double) -> String {
        let r=(d*10).rounded()/10
        let text=r == r.rounded() ? String(format:"%.0f",locale:Locale(identifier:"en_US_POSIX"),r) : String(format:"%.1f",locale:Locale(identifier:"en_US_POSIX"),r)
        return "\(text) \(r == 1 ? "meter" : "meters")"
    }
    /// `targetName` is how to say the selected target ("possible door"); nil uses its label.
    public static func describe(_ cell: PuckCell, in scene: CachedScene, targetName: String? = nil) -> String {
        guard PuckLayout.activeColumns.contains(cell.column), scene.distances.count == 7 else { return "Point at one of the pins." }
        let c=cell.column
        var parts: [String] = []
        var shown: UInt8=0
        if let t=scene.target, t.valid(at:scene.timestamp), let span=t.columns, span.contains(c) {
            parts.append("\(targetName ?? t.label), \(meters(t.distance))")
            shown=TactileGeometry.band(distance:t.distance)
        }
        if let d=scene.distances[c], TactileGeometry.band(distance:d)>0 {
            parts.append("Nearest reading \(meters(d))")
            let b=TactileGeometry.band(distance:d); shown=shown == 0 ? b : min(shown,b)
        } else if parts.isEmpty {
            parts.append("Nothing measured within 4 meters. Not confirmed clear")
        }
        var text="\(directions[c]): "+parts.joined(separator:". ")+"."
        if shown>0, shown != cell.band { text+=shown<cell.band ? " The raised pin is closer than where you're pointing." : " The raised pin is farther than where you're pointing." }
        return text
    }
}

/// A route goal picked by two fingers on a column, anchored in the world so it stays right
/// after the user turns or walks.
public struct PointingRoute: Equatable, Sendable {
    public let column: Int
    /// World position (AR frame) to route to.
    public let goal: Vector3
    public let distance: Double
    public let label: String
    /// True when the goal is the selected target; false when it stops short of an obstacle reading.
    public let toTarget: Bool
    /// Too close to route to: tap this column instead (silently), raising `band` if its pin is down.
    public var highlightOnly = false
    public var band: UInt8 = 0
}
public enum PointingRouter {
    public enum Plan: Equatable, Sendable { case route(PointingRoute, String), refused(String) }
    /// Stop this far short of an obstacle reading. A goal must lie beyond the guide's arrival
    /// distance plus `minMargin`, or the route would "arrive" as soon as it starts.
    public static var standOff = 0.5, minMargin = 0.3
    static var minGoal: Double { DirectionCue.arriveMeters+minMargin }
    public static func bearing(ofColumn c: Int) -> Double { PuckLayout.bearing(ofColumn: c) }
    /// A point `distance` metres away along `bearing` (degrees, + right) on the horizontal plane.
    public static func worldPoint(bearing: Double, distance: Double, pose: CameraPose) -> Vector3? {
        let f=Vector3(-pose.back.x,0,-pose.back.z), r=Vector3(pose.right.x,0,pose.right.z)
        let fl=f.dot(f).squareRoot(), rl=r.dot(r).squareRoot()
        guard pose.isValid, fl>1e-6, rl>1e-6, bearing.isFinite, distance.isFinite, distance>0 else { return nil }
        let b=bearing * .pi/180
        return pose.position+f*(cos(b)/fl)*distance+r*(sin(b)/rl)*distance
    }
    /// Where two fingers on `column` of the cached scene should route to, or why nowhere.
    public static func plan(column c: Int, scene: CachedScene, targetName: String?) -> Plan {
        guard PuckLayout.activeColumns.contains(c), scene.distances.count == 7 else { return .refused("Lay two fingers along one column.") }
        let way=PointingDescriber.directions[c].lowercased()
        if let t=scene.target, t.valid(at:scene.timestamp), let span=t.columns, span.contains(c),
           let goal=worldPoint(bearing:t.bearingDegrees,distance:t.distance,pose:scene.pose) {
            let name=targetName ?? t.label
            var route=PointingRoute(column:c,goal:goal,distance:t.distance,label:name,toTarget:true)
            // Too close to route to: tap the column instead, no speech.
            guard t.distance>minGoal else { route.highlightOnly=true; route.band=TactileGeometry.band(distance:t.distance); return .route(route,"") }
            return .route(route,"Route set to \(name.lowercased()), \(way), \(PointingDescriber.meters(t.distance)). Lower the puck to start.")
        }
        guard let d=scene.distances[c], TactileGeometry.band(distance:d)>0 else {
            return .refused("Nothing measured that way, so there's no destination. Pick a column with a raised pin.")
        }
        let reach=d-standOff
        if reach<=minGoal, let at=worldPoint(bearing:bearing(ofColumn:c),distance:d,pose:scene.pose) {
            var route=PointingRoute(column:c,goal:at,distance:d,label:"\(way) obstacle",toTarget:false)
            route.highlightOnly=true; route.band=TactileGeometry.band(distance:d)
            return .route(route,"")
        }
        guard let goal=worldPoint(bearing:bearing(ofColumn:c),distance:reach,pose:scene.pose) else { return .refused("I can't place that direction.") }
        let route=PointingRoute(column:c,goal:goal,distance:reach,label:"\(way) obstacle",toTarget:false)
        return .route(route,"Route set \(way), about \(PointingDescriber.meters(reach)), stopping short of what's there. Lower the puck to start.")
    }
}
