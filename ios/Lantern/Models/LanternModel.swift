import Foundation
import Combine
import AVFoundation
import UIKit
import FeelCore

/// UI and 10Hz transmission coordinator. All state is confined to the main queue.
final class LanternModel:ObservableObject {
    enum RunMode:String { case stopped="STOPPED",live="LIVE",simulation="SIMULATION" }
    @Published private(set) var mode:RunMode = .stopped
    @Published private(set) var packet=FeelPacket.neutral(sequence:0)
    @Published private(set) var guidanceState:GuidanceState = .stopped
    @Published private(set) var status="Choose Live sensing or Simulation"
    @Published private(set) var detectorStatus="Loading detector"
    @Published private(set) var detectorAvailable=false
    @Published private(set) var targetDescription="No target selected"
    @Published private(set) var calibrated=false
    @Published var cameraHeight=1.2
    @Published var finder:FinderMode = .none { didSet { finderEpoch += 1; perception.setFinder(finder,epoch:finderEpoch); frame=nil; targetDescription="Searching: \(finder.rawValue)" } }
    let perception=ARPerception()
    let puck=BluetoothPuck()
    let peer=NearbyPeerService(role:.seeker)
    private var frame:PerceptionFrame?
    private var timer:Timer?
    private var sequence:UInt8=0
    private var simulatedAt:TimeInterval=0
    private var startGeneration=0
    private var finderEpoch=0
    init() {
        peer.arSession=perception.session
        perception.onFrame={ [weak self] frame in guard let self,self.mode == .live,frame.epoch==self.startGeneration,frame.finderEpoch==self.finderEpoch else { return }; self.frame=frame; self.calibrated=frame.floorY != nil }
        perception.onInvalidated={ [weak self] epoch in guard let self,epoch==self.startGeneration else { return }; self.frame=nil; self.calibrated=false; self.tick() }
        perception.onStatus={ [weak self] text in guard let self,self.mode == .live else { return }; self.status=text }
        perception.onModelStatus={ [weak self] text,available in self?.detectorStatus=text; self?.detectorAvailable=available }
    }
    func startLive() {
        stop(); startGeneration += 1; let generation=startGeneration
        func begin() {
            guard self.startGeneration==generation else { return }
            self.mode = .live
            guard self.perception.start(epoch:generation) else { self.mode = .stopped; self.status="Live sensing requires a LiDAR device. Simulation is available."; return }
            self.perception.setFinder(self.finder,epoch:self.finderEpoch); self.status="Starting live perception"; self.beginTimer()
        }
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video) { granted in DispatchQueue.main.async {
                guard self.startGeneration==generation else { return }
                if granted { begin() } else { self.status="Camera permission denied. Enable it in Settings to use Live." }
            } }
        default: status="Camera permission denied. Enable it in Settings to use Live."
        }
    }
    func startSimulation() {
        stop(); mode = .simulation; simulatedAt=ProcessInfo.processInfo.systemUptime
        status="SIMULATION — synthetic scene, no simulated BLE movement"; calibrated=false; beginTimer()
    }
    func calibrate() { guard mode == .live else { return }; perception.calibrate(cameraHeight:cameraHeight) }
    func stop() {
        startGeneration += 1; timer?.invalidate(); timer=nil; frame=nil; calibrated=false
        perception.stop(); peer.stop(); mode = .stopped; guidanceState = .stopped
        sequence &+= 1; packet = .neutral(sequence:sequence); puck.send(packet)
        status="Stopped — neutral command sent if connected"; targetDescription="No guidance"
        UIApplication.shared.isIdleTimerDisabled=false
    }
    private func beginTimer() {
        UIApplication.shared.isIdleTimerDisabled=true
        let timer=Timer(timeInterval:0.1,repeats:true) { [weak self] _ in self?.tick() }
        self.timer=timer; RunLoop.main.add(timer,forMode:.common); tick()
    }
    private func tick() {
        let now=ProcessInfo.processInfo.systemUptime; sequence &+= 1
        if mode == .simulation {
            let phase=(now-simulatedAt).truncatingRemainder(dividingBy:12)
            let tracking=phase<8 || phase>=10
            let target=TargetObservation(bearingDegrees:sin(phase/2)*40,distance:1.3,timestamp:now,label:"SIMULATED target")
            let output=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:now,tracking:tracking,distances:[0.7,1.1,nil,2,3.5,nil,nil],target:target)
            packet=output.packet; guidanceState=output.state == .live ? .simulation : output.state
            targetDescription=tracking ? "SIMULATED target sweeping left to right" : "SIMULATED tracking loss — all pins neutral"
            return
        }
        guard mode == .live,let frame else {
            packet = .neutral(sequence:sequence); guidanceState = mode == .live ? .staleDepth : .stopped
            if mode == .live { puck.send(packet) }; return
        }
        let target=finder == .teammate ? peer.currentTarget(pose:frame.pose,now:now) : frame.target
        let output=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:frame.timestamp,tracking:frame.tracking,distances:frame.distances,target:target,floorCalibrated:frame.floorY != nil)
        packet=output.packet; guidanceState=output.state; puck.send(packet)
        if let target,target.valid(at:now),output.state == .live {
            targetDescription=String(format:"%@ · %.1f m · %.0f°",target.label,target.distance,target.bearingDegrees)
        } else { targetDescription=finder == .none ? "Obstacle sensing" : "Target unavailable — no directional highlight" }
    }
}
