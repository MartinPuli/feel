import Foundation
import Combine
import ARKit
import FeelCore

struct CapturedWorldMap {
    let data:Data
    let mapID:String
    let anchorID:String
}

struct SavedMapObservation {
    let epoch:Int
    let worldEpoch:Int
    let mapID:String
    let anchorID:String?
    let pose:CameraPose
    let timestamp:TimeInterval
    let tracking:Bool
    let relocalizing:Bool
}

/// The lock covers only the atomic file rename. Cancellation never waits for encoding or a large disk write.
final class SavedMapWritePermit {
    private let lock=NSLock()
    private var cancelled=false
    func cancel() { lock.lock(); cancelled=true; lock.unlock() }
    func commit(_ body:() throws -> Void) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        try body(); return true
    }
}

/// Main-queue coordinator. Only an explicit restore starts AR; only the verified gate installs
/// places. The callback must install them inactive, requiring a separate Recall action.
final class SavedWorldMaps:ObservableObject {
    @Published private(set) var isBusy=false
    @Published private(set) var isRestoring=false
    @Published private(set) var message="Maps stay on this iPhone."
    var capture:((Int,@escaping (Result<CapturedWorldMap,Error>)->Void)->Void)?
    /// The owner stops current guidance and starts a fresh AR world with the supplied map.
    /// Do not call cancel() inside this callback; world-ended events from the old world are ignored.
    var onRestoreRequested:((ARWorldMap,String)->Bool)?
    var onRestored:((PersistentMemoryArchive,Int)->Void)?
    private let store:WorldMapStore
    private let now:()->TimeInterval
    private let io=DispatchQueue(label:"feel.saved-world-maps",qos:.utility)
    private var request=UUID()
    private var pending:PersistentMemoryArchive?
    private var savingWorld:Int?
    private var savePermit:SavedMapWritePermit?
    private var restoreBegan:TimeInterval?
    private var activeWorld:(epoch:Int,world:Int)?
    private var gate=WorldMapRestoreGate()
    private var deadline:DispatchWorkItem?

    init(store:WorldMapStore=WorldMapStore(),now:@escaping ()->TimeInterval={ ProcessInfo.processInfo.systemUptime }) {
        self.store=store; self.now=now
    }
    deinit { deadline?.cancel() }

    func save(snapshot:SpatialMemorySnapshot,worldEpoch:Int) {
        guard !isBusy else { return }
        guard snapshot.session != nil,!snapshot.bookmarks.isEmpty || snapshot.returnPoint != nil,let capture else {
            message="Remember a place in the live camera session first."; return
        }
        cancel(); savingWorld=worldEpoch; isBusy=true; message="Saving this room…"
        let token=request,permit=SavedMapWritePermit(); savePermit=permit
        armDeadline(token:token,seconds:20)
        capture(worldEpoch) { [weak self] result in
            guard let self,self.request==token else { return }
            switch result {
            case .failure:
                self.finish("Map unavailable. Move slowly around this room and try again.")
            case .success(let captured):
                self.io.async {
                    let result=Result {
                        let archive=try PersistentMemoryArchive(mapID:captured.mapID,anchorID:captured.anchorID,mapData:captured.data,snapshot:snapshot)
                        // The same secure marker check used on load also guards a corrupt capture.
                        _=try WorldMapStore.decodeMap(archive)
                        let staged=try self.store.stage(archive)
                        defer { try? FileManager.default.removeItem(at:staged) }
                        return try permit.commit { try self.store.commit(staged) }
                    }
                    DispatchQueue.main.async {
                        guard self.request==token else { return }
                        self.finish((try? result.get()) == true ? "Room and places saved on this iPhone." : "Could not save this room.")
                    }
                }
            }
        }
    }

    func restore() {
        guard !isBusy else { return }
        cancel(); isBusy=true; message="Loading saved room…"
        let token=request
        armDeadline(token:token,seconds:60)
        io.async {
            let result=Result { try self.store.load() }
            DispatchQueue.main.async {
                guard self.request==token else { return }
                switch result {
                case .failure: self.finish("No usable saved room. Save a room first.")
                case .success(let loaded):
                    self.prepareRestore(loaded.archive)
                    guard self.onRestoreRequested?(loaded.map,loaded.archive.mapID) == true else {
                        self.finish("Live camera could not start for this room."); return
                    }
                }
            }
        }
    }

    /// Internal seam for deterministic gate tests; the public restore path first securely decodes the map.
    func prepareRestore(_ archive:PersistentMemoryArchive) {
        pending=archive; activeWorld=nil; gate.cancel(); restoreBegan=now()
        isBusy=true; isRestoring=true; message="Look around the saved room to match it. Guidance is paused."
        armDeadline(token:request,seconds:60)
    }
    func worldStarted(epoch:Int,worldEpoch:Int,mapID:String?) {
        if let savingWorld,savingWorld != worldEpoch { finish("Map save stopped because the camera world changed.") }
        guard let archive=pending else { return }
        guard activeWorld == nil,mapID==archive.mapID else {
            finish("Room restore stopped because the camera world changed."); return
        }
        activeWorld=(epoch,worldEpoch)
        do { try gate.begin(archive:archive,session:Self.sessionID(worldEpoch),now:now()) }
        catch { finish("Room restore could not start.") }
    }
    func worldEnded(epoch:Int,worldEpoch:Int) {
        if savingWorld==worldEpoch { finish("Map save stopped because the camera world changed."); return }
        guard let world=activeWorld,world.epoch==epoch,world.world==worldEpoch else { return }
        finish("Room restore stopped. Start it again when the camera is ready.")
    }
    func observe(_ observation:SavedMapObservation) {
        guard let world=activeWorld,let archive=pending,
              observation.epoch==world.epoch,observation.worldEpoch==world.world else { return }
        checkDeadline()
        guard isRestoring else { return }
        let session=Self.sessionID(world.world)
        let sample=MemoryPose(session:session,pose:observation.pose,timestamp:observation.timestamp,tracking:observation.tracking)
        switch gate.observe(session:session,mapID:observation.mapID,anchorID:observation.anchorID,now:now(),sample:sample,relocalizing:observation.relocalizing) {
        case .ready:
            finish("Room matched. Choose a place to recall.")
            onRestored?(archive,world.world)
        case .failed: finish("Room could not be matched. Try again in the saved room.")
        default: break
        }
    }
    func checkDeadline() {
        guard isRestoring,let began=restoreBegan else { return }
        let time=now()
        if !time.isFinite || time<began || time-began>60 || gate.checkDeadline(now:time) == .failed {
            finish("Room could not be matched. Try again in the saved room.")
        }
    }
    func delete() {
        cancel(); isBusy=true; message="Deleting saved room…"
        let token=request
        io.async {
            let result=Result { try self.store.delete() }
            DispatchQueue.main.async {
                guard self.request==token else { return }
                self.finish((try? result.get()) != nil ? "Saved room deleted." : "Could not delete the saved room.")
            }
        }
    }
    func cancel() {
        savePermit?.cancel(); savePermit=nil
        request=UUID(); deadline?.cancel(); deadline=nil; gate.cancel(); pending=nil
        activeWorld=nil; savingWorld=nil; restoreBegan=nil; isBusy=false; isRestoring=false
    }
    private func finish(_ text:String) { cancel(); message=text }
    private static func sessionID(_ world:Int)->String { "saved-world-\(world)" }
    private func armDeadline(token:UUID,seconds:TimeInterval) {
        deadline?.cancel()
        let item=DispatchWorkItem { [weak self] in
            guard let self,self.request==token,self.isBusy else { return }
            self.finish(self.isRestoring ? "Room could not be matched. Try again in the saved room." : "Map request timed out. Try again.")
        }
        deadline=item; DispatchQueue.main.asyncAfter(deadline:.now()+seconds,execute:item)
    }
}
