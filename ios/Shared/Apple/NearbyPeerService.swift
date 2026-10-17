import Foundation
import UIKit
import Combine
import NearbyInteraction
import MultipeerConnectivity
import ARKit
import FeelCore

/// User-approved one-to-one token exchange over encrypted Multipeer Connectivity.
/// Main queue owns state. Advertisers never silently accept a nearby person.
final class NearbyPeerService: NSObject, ObservableObject, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate, MCSessionDelegate, NISessionDelegate {
    enum Role { case seeker, beacon }
    @Published private(set) var status="Nearby Interaction stopped"
    @Published private(set) var peers:[MCPeerID]=[]
    @Published private(set) var invitationName:String?
    @Published private(set) var target:TargetObservation?
    @Published private(set) var distance:Float?
    @Published private(set) var connectedName:String?
    var arSession:ARSession?
    private let role:Role
    private let localPeer=MCPeerID(displayName:String(UIDevice.current.name.prefix(50)))
    private var network:MCSession!
    private var browser:MCNearbyServiceBrowser?
    private var advertiser:MCNearbyServiceAdvertiser?
    private var nearby:NISession?
    private var selected:MCPeerID?
    private var remoteToken:NIDiscoveryToken?
    private var worldTarget:CapturedTarget?
    private var invitation:((Bool,MCSession?)->Void)?
    @Published private(set) var running=false
    private var rangingActive=false
    private var rangingSuspended=false
    init(role:Role) { self.role=role; super.init() }
    func start() {
        stop()
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else { status="Ultra Wideband unavailable on this device"; return }
        running=true
        nearby=NISession(); nearby?.delegate=self; nearby?.delegateQueue = .main
        network=MCSession(peer:localPeer,securityIdentity:nil,encryptionPreference:.required); network.delegate=self
        if role == .seeker {
            let b=MCNearbyServiceBrowser(peer:localPeer,serviceType:"feel-beacon"); browser=b; b.delegate=self; b.startBrowsingForPeers(); status="Choose your teammate's Beacon phone"
        } else {
            let a=MCNearbyServiceAdvertiser(peer:localPeer,discoveryInfo:["feel":"v1"],serviceType:"feel-beacon"); advertiser=a; a.delegate=self; a.startAdvertisingPeer(); status="Ready. Waiting for a Lantern request"
        }
    }
    func stop() {
        running=false; rangingActive=false; rangingSuspended=false; invitation?(false,nil); invitation=nil; invitationName=nil
        browser?.stopBrowsingForPeers(); advertiser?.stopAdvertisingPeer(); browser=nil; advertiser=nil
        network?.disconnect(); network=nil; nearby?.invalidate(); nearby=nil; selected=nil; remoteToken=nil
        peers=[]; target=nil; worldTarget=nil; distance=nil; connectedName=nil; status="Nearby Interaction stopped"
    }
    func invite(_ peer:MCPeerID) {
        guard running,role == .seeker,selected==nil else { return }
        selected=peer; browser?.invitePeer(peer,to:network,withContext:Data("FEEL-v1".utf8),timeout:20); status="Waiting for \(peer.displayName) to accept"
    }
    func acceptInvitation(_ accept:Bool) {
        let callback=invitation; invitation=nil; invitationName=nil
        callback?(accept,accept ? network : nil)
        if !accept { selected=nil; status="Request declined" }
    }
    private func sendToken() {
        guard let token=nearby?.discoveryToken,let peer=selected,network?.connectedPeers.contains(peer)==true else { return }
        do { try network.send(NSKeyedArchiver.archivedData(withRootObject:token,requiringSecureCoding:true),toPeers:[peer],with:.reliable) }
        catch { status="Token exchange failed: \(error.localizedDescription)" }
    }
    private func runRanging() {
        guard running,!rangingSuspended,let peer=selected,network?.connectedPeers.contains(peer)==true,let token=remoteToken,let nearby else { return }
        let config=NINearbyPeerConfiguration(peerToken:token)
        if let arSession { config.isCameraAssistanceEnabled=true; nearby.setARSession(arSession) }
        rangingActive=true; nearby.run(config); status="Ranging. Keep both apps foreground"
    }
    func browser(_ browser:MCNearbyServiceBrowser,foundPeer peerID:MCPeerID,withDiscoveryInfo info:[String:String]?) {
        DispatchQueue.main.async { guard browser === self.browser,self.running,info?["feel"]=="v1" else { return }; if !self.peers.contains(peerID) { self.peers.append(peerID) } }
    }
    func browser(_ browser:MCNearbyServiceBrowser,lostPeer peerID:MCPeerID) { DispatchQueue.main.async { guard browser === self.browser else { return }; self.peers.removeAll {$0==peerID} } }
    func browser(_ browser:MCNearbyServiceBrowser,didNotStartBrowsingForPeers error:Error) { DispatchQueue.main.async { if browser === self.browser { self.status="Local network access failed: \(error.localizedDescription)" } } }
    func advertiser(_ advertiser:MCNearbyServiceAdvertiser,didReceiveInvitationFromPeer peerID:MCPeerID,withContext context:Data?,invitationHandler:@escaping(Bool,MCSession?)->Void) {
        DispatchQueue.main.async {
            guard advertiser === self.advertiser,self.running,self.selected==nil,context==Data("FEEL-v1".utf8) else { invitationHandler(false,nil); return }
            self.selected=peerID; self.invitation=invitationHandler; self.invitationName=peerID.displayName; self.status="Connection request from \(peerID.displayName)"
        }
    }
    func advertiser(_ advertiser:MCNearbyServiceAdvertiser,didNotStartAdvertisingPeer error:Error) { DispatchQueue.main.async { if advertiser === self.advertiser { self.status="Advertising failed: \(error.localizedDescription)" } } }
    func session(_ session:MCSession,peer peerID:MCPeerID,didChange state:MCSessionState) {
        DispatchQueue.main.async {
            guard session === self.network,peerID==self.selected else { return }
            if state == .connected { self.connectedName=peerID.displayName; self.sendToken() }
            else if state == .notConnected {
                self.target=nil; self.worldTarget=nil; self.distance=nil; self.connectedName=nil; self.remoteToken=nil; self.selected=nil
                self.rangingActive=false; self.replaceRangingSession(); self.status="Peer disconnected. Select again"
            }
        }
    }
    func session(_ session:MCSession,didReceive data:Data,fromPeer peerID:MCPeerID) {
        DispatchQueue.main.async {
            guard self.running,session === self.network,peerID==self.selected,session.connectedPeers.contains(peerID),data.count<=8192 else { return }
            do {
                guard let token=try NSKeyedUnarchiver.unarchivedObject(ofClass:NIDiscoveryToken.self,from:data) else { return }
                self.remoteToken=token; self.runRanging()
            } catch { self.status="Invalid Nearby Interaction token" }
        }
    }
    func session(_ session:MCSession,didReceive stream:InputStream,withName streamName:String,fromPeer peerID:MCPeerID) { stream.close() }
    func session(_ session:MCSession,didStartReceivingResourceWithName resourceName:String,fromPeer peerID:MCPeerID,with progress:Progress) { progress.cancel() }
    func session(_ session:MCSession,didFinishReceivingResourceWithName resourceName:String,fromPeer peerID:MCPeerID,at localURL:URL?,withError error:Error?) {}
    func session(_ session:NISession,didUpdate nearbyObjects:[NINearbyObject]) {
        guard running,rangingActive,!rangingSuspended,session === nearby,let token=remoteToken,let object=nearbyObjects.first(where:{$0.discoveryToken==token}) else { return }
        distance=object.distance; target=nil; worldTarget=nil
        // Use Apple's shared AR world transform to avoid guessing portrait/landscape NI axes.
        guard let arSession,let frame=arSession.currentFrame,case .normal=frame.camera.trackingState,
              ProcessInfo.processInfo.systemUptime-frame.timestamp<=0.25,
              let transform=session.worldTransform(for:object) else {
            status=object.distance == nil ? "Peer range unavailable" : (role == .beacon ? "Distance available. Your teammate's phone determines direction." : "Range available; waiting for a reliable AR direction")
            return
        }
        let relative=simd_inverse(frame.camera.transform)*transform.columns.3
        guard let angle=TactileGeometry.bearing(x:Double(relative.x),z:Double(relative.z)) else { status="Teammate is outside forward view"; return }
        let horizontalDistance=hypot(Double(relative.x),Double(relative.z))
        let observation=TargetObservation(bearingDegrees:angle,distance:horizontalDistance,timestamp:ProcessInfo.processInfo.systemUptime,label:connectedName ?? "Teammate")
        if observation.valid(at:ProcessInfo.processInfo.systemUptime) {
            let p=transform.columns.3
            worldTarget=CapturedTarget(position:Vector3(Double(p.x),Double(p.y),Double(p.z)),timestamp:observation.timestamp,label:observation.label)
            target=observation; status="Teammate direction available" }
        else { status="Teammate outside tactile range or view" }
    }
    func currentTarget(pose:CameraPose,now:Double)->TargetObservation? {
        guard running,rangingActive,!rangingSuspended else { return nil }
        return worldTarget?.observation(pose:pose,now:now)
    }
    private func clearRanging() { rangingActive=false; target=nil; worldTarget=nil; distance=nil }
    /// Rotate the local discovery token when resuming. Delayed callbacks from the
    /// old NISession cannot enter the new context because every delegate checks identity.
    private func replaceRangingSession() {
        guard running else { return }
        clearRanging()
        // Suspension belongs to the replaced NISession. A fresh instance must not
        // inherit it when an MC disconnect arrives before suspension-ended.
        rangingSuspended=false
        let previous=nearby; nearby=nil; previous?.delegate=nil; previous?.invalidate()
        let replacement=NISession(); replacement.delegate=self; replacement.delegateQueue = .main; nearby=replacement
        sendToken(); runRanging()
    }
    func sessionWasSuspended(_ session:NISession) {
        guard running,session === nearby else { return }
        rangingSuspended=true; clearRanging(); status="Nearby Interaction suspended"
    }
    func sessionSuspensionEnded(_ session:NISession) {
        guard running,rangingSuspended,session === nearby else { return }
        rangingSuspended=false; replaceRangingSession()
    }
    func session(_ session:NISession,didInvalidateWith error:Error) {
        guard session === nearby else { return }
        clearRanging(); remoteToken=nil; nearby=nil; rangingSuspended=false
        status="Nearby Interaction failed; stop and restart: \(error.localizedDescription)"
    }
    func session(_ session:NISession,didRemove nearbyObjects:[NINearbyObject],reason:NINearbyObject.RemovalReason) {
        guard running,session === nearby,let token=remoteToken,nearbyObjects.contains(where:{$0.discoveryToken==token}) else { return }
        clearRanging(); status="Peer ranging lost"
        if reason != .timeout { remoteToken=nil }
        replaceRangingSession()
    }
}
