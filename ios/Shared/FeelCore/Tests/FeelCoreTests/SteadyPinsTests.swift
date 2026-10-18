import XCTest
@testable import FeelCore

// MARK: Sector filter

final class SectorFilterTests: XCTestCase {
    private let empty=[Double?](repeating:nil,count:7)
    private func col(_ d: Double?) -> [Double?] { var r=empty; r[3]=d; return r }
    private func bands(_ d: [Double?]) -> [UInt8] { d.map { $0.map { TactileGeometry.band(distance:$0) } ?? 0 } }
    /// Centre-column band after each frame, frames 100 ms apart.
    private func run(_ frames: [[Double?]]) -> [UInt8] {
        var f=SectorFilter()
        return frames.enumerated().map { bands(f.update($0.element,frameTimestamp:Double($0.offset)*0.1))[3] }
    }

    func testNearerBandShowsAfterTwoFrames() { XCTAssertEqual(run([col(2),col(2),col(2)]),[0,3,3]) }
    func testUnderNinetyCentimetresShowsAtOnce() { XCTAssertEqual(run([col(0.7)]),[1]) }
    func testCloserBandAlsoNeedsTwoFrames() { XCTAssertEqual(run([col(3),col(3),col(1.2),col(1.2),col(1.2)]),[0,4,4,2,2]) }
    func testFartherBandNeedsFourFramesAndMargin() {
        // 1.65 m is inside the 10 cm margin past the 1.6 m boundary: still band 2, however long it lasts.
        XCTAssertTrue(run([col(1.5),col(1.5)]+Array(repeating:col(1.65),count:8)).dropFirst().allSatisfy { $0==2 })
        XCTAssertEqual(run([col(1.5),col(1.5)]+Array(repeating:col(1.8),count:6)),[0,2,2,2,2,3,3,3])
    }
    func testUnknownHoldsThenClears() { XCTAssertEqual(run([col(1.0),col(1.0)]+Array(repeating:col(nil),count:5)),[0,2,2,2,2,0,0]) }
    func testWalkingBobDoesNotFlutter() {
        // Range oscillating 1.55–1.68 m at 2 Hz across the 1.6 m boundary, as walking bob does.
        let frames=(0..<40).map { i in col(1.615+0.065*sin(Double(i)*0.1*2 * .pi*2)) }
        let raw=frames.map { bands($0)[3] }
        XCTAssertGreaterThan(zip(raw,raw.dropFirst()).filter { $0 != $1 }.count,5,"the raw bands flutter")
        XCTAssertEqual(Set(run(frames).dropFirst(10)).count,1,"the shown band settles")
    }
    func testDistancesPassThroughOnlyWithinTheShownBand() {
        var f=SectorFilter()
        _=f.update(col(2.0),frameTimestamp:0); _=f.update(col(2.0),frameTimestamp:0.1)
        XCTAssertEqual(f.update(col(2.3),frameTimestamp:0.2)[3],2.3,"same band: the latest range")
        _=f.update(col(1.5),frameTimestamp:0.3); _=f.update(col(1.5),frameTimestamp:0.4); _=f.update(col(1.5),frameTimestamp:0.5)
        XCTAssertEqual(f.update(col(1.65),frameTimestamp:0.6)[3],1.5,"a range in the margin would encode the next band, so the shown range stays")
    }
    func testRepeatedFrameAddsNoEvidence() {
        var f=SectorFilter()
        for _ in 0..<3 { _=f.update(col(2),frameTimestamp:1) }
        XCTAssertEqual(bands(f.current)[3],0)
        XCTAssertEqual(bands(f.update(col(2),frameTimestamp:1.1))[3],3)
    }
    func testInvalidInputIgnoredAndResetForgets() {
        var f=SectorFilter()
        _=f.update(col(2),frameTimestamp:0); _=f.update(col(2),frameTimestamp:0.1)
        XCTAssertEqual(bands(f.update([],frameTimestamp:0.2))[3],3)
        XCTAssertEqual(bands(f.update(col(2),frameTimestamp:.nan))[3],3)
        f.reset(); XCTAssertEqual(f.current,empty)
    }
}

// MARK: Path wave

final class PathWaveTests: XCTestCase {
    private func dots(_ f: [UInt8]) -> String { f.map { $0==0 ? "." : String($0) }.joined() }
    private func hint(_ bearing: Double, at t: Double, distance: Double = 3, status: RouteHint.Status = .route) -> RouteHint {
        RouteHint(timestamp:t,status:status,bearingDegrees:bearing,targetDistance:distance,routeLength:distance,label:"door")
    }
    private func base(_ bands: [UInt8] = [0,0,0,0,0,0,0], highlight: UInt8 = 255) -> EncoderOutput {
        EncoderOutput(packet:try! FeelPacket(sequence:9,bands:bands,highlight:highlight),state:.live,targetColumns:nil)
    }
    /// Facing samples 100 ms apart from `t0`, turning at `rate` degrees per second for `seconds`.
    private func turn(_ w: inout PathWave, from t0: Double = 0, rate: Double = 60, seconds: Double = 1, start yaw: Double = 0) {
        for k in 0...Int((seconds*10).rounded()) { let dt=Double(k)*0.1; w.observe(yawDegrees:yaw+rate*dt,at:t0+dt) }
    }
    private func frames(_ w: inout PathWave, from t0: Double, count: Int, bearing: Double = 30, base: EncoderOutput? = nil) -> [String] {
        (0..<count).map { k in let t=t0+Double(k)*0.1; return dots(w.apply(to:base ?? self.base(),hint:hint(bearing,at:t),now:t).packet.bands) }
    }

    func testNoWaveWithoutATurn() {
        var w=PathWave()
        turn(&w,rate:5,seconds:2)   // slow drift
        XCTAssertEqual(w.apply(to:base(),hint:hint(30,at:2),now:2),base()); XCTAssertFalse(w.isActive)
    }
    func testTurnSweepsFromCentreToRouteColumnAndRepeats() {
        var w=PathWave(); turn(&w)
        // 30° → slot 6 (six sectors in slots 1...6): centre, 4, 5, 6; the end pin holds, a rest, then again.
        XCTAssertEqual(frames(&w,from:1,count:12),["...4...","...44..","....44.",".....44","......4","......4","......4",".......",".......",".......",".......","...4..."])
        XCTAssertEqual(w.column,6); XCTAssertTrue(w.isActive)
    }
    func testBeyondTheFieldRunsToTheEdge() {
        var w=PathWave(); turn(&w)
        // The edge is physical slot 1; reserved wire slot 0 never rises.
        XCTAssertEqual(frames(&w,from:1,count:5,bearing:-120),["...4...","..44...",".44....",".4.....",".4....."])
        XCTAssertEqual(w.column,1)
    }
    func testStraightRouteOrArrivalHasNoWave() {
        var w=PathWave(); turn(&w)
        XCTAssertEqual(w.apply(to:base(),hint:hint(10,at:1),now:1),base())
        XCTAssertEqual(w.apply(to:base(),hint:hint(60,at:1,distance:0.8),now:1),base())
        XCTAssertEqual(w.apply(to:base(),hint:hint(60,at:1,status:.blocked),now:1),base())
        XCTAssertEqual(w.apply(to:base(),hint:nil,now:1),base())
        XCTAssertFalse(w.isActive)
    }
    func testObstaclePinsKeepTheirBandSoTheWaveEndsInTheGap() {
        var w=PathWave(); turn(&w)
        // A wall in band 3 with a one-column gap at column 5, the route through it.
        let wall=base([3,3,3,3,3,0,3])
        let shown=frames(&w,from:1,count:4,base:wall)
        XCTAssertEqual(shown,["33333.3","33333.3","3333343","3333343"],"the centre and column 4 keep the wall; the dot appears in the gap")
    }
    func testNearObstacleAndHighlightPreserved() {
        var w=PathWave(); turn(&w)
        let near=base([0,0,1,0,0,0,0])
        XCTAssertEqual(w.apply(to:near,hint:hint(30,at:1),now:1),near,"anything within 0.9 m holds the wave back")
        let tapping=base([0,0,0,0,0,2,0],highlight:5)
        let out=w.apply(to:tapping,hint:hint(30,at:1.1),now:1.1)
        XCTAssertEqual(out.packet.highlight,5); XCTAssertEqual(out.packet.sequence,9); XCTAssertEqual(dots(out.packet.bands),"...4.2.")
    }
    func testStopsAfterTheTurnEnds() {
        var w=PathWave(); turn(&w)   // last facing sample at t = 1.0
        XCTAssertNotEqual(w.apply(to:base(),hint:hint(30,at:2.4),now:2.4),base())
        XCTAssertEqual(w.apply(to:base(),hint:hint(30,at:2.6),now:2.6),base()); XCTAssertFalse(w.isActive)
    }
    func testStaleHintHasNoWave() {
        var w=PathWave(); turn(&w)
        XCTAssertEqual(w.apply(to:base(),hint:hint(30,at:0),now:1.5),base())
    }
    func testFacingWrapsAtOneEightyAndNonLiveStops() {
        var w=PathWave()
        for (k,yaw) in [170.0,176,-178,-172,-166,-160].enumerated() { w.observe(yawDegrees:yaw,at:Double(k)*0.1) }
        XCTAssertNotEqual(w.apply(to:base(),hint:hint(30,at:0.5),now:0.5),base())
        let lost=EncoderOutput(packet:.neutral(sequence:1),state:.trackingLost)
        XCTAssertEqual(w.apply(to:lost,hint:hint(30,at:0.6),now:0.6),lost); XCTAssertFalse(w.isActive)
    }
    func testAllWaveFramesAreWireLegal() throws {
        var w=PathWave(); turn(&w,seconds:3)
        for k in 0..<30 { let t=Double(k)*0.1; _=try FeelPacket(bytes:w.apply(to:base([0,2,0,0,3,0,0]),hint:hint(-40,at:t),now:t).packet.bytes) }
    }
}
