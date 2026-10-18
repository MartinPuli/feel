import Foundation
import Darwin
import ARKit
import FeelCore

/// One local map, with an atomic envelope tying its marker to its bookmark snapshot.
/// Call on a serial I/O queue. This store never starts AR or activates a bookmark.
final class WorldMapStore {
    static func anchorName(mapID:String)->String { "FEEL.map." + mapID }
    private let url:URL
    init(url:URL?=nil) {
        self.url=url ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("FEEL",isDirectory:true).appendingPathComponent("saved-world.json")
    }
    func save(_ archive:PersistentMemoryArchive) throws {
        let staged=try stage(archive)
        defer { try? FileManager.default.removeItem(at:staged) }
        try commit(staged)
    }
    /// Serialize off the main/AR queues. The final rename can then be guarded by a cancellation permit.
    func stage(_ archive:PersistentMemoryArchive) throws -> URL {
        let directory=url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
        var excluded=directory; var resource=URLResourceValues(); resource.isExcludedFromBackup=true
        try excluded.setResourceValues(resource)
        let data=try archive.encoded()
        guard data.count<=PersistentMemoryArchive.maxJSONBytes else { throw PersistentMemoryError.invalidArchive("encoded map too large") }
        let staged=directory.appendingPathComponent(".saved-world-"+UUID().uuidString+".pending")
        try data.write(to:staged,options:[.atomic,.completeFileProtection])
        return staged
    }
    /// Same-directory rename is the only commit operation, replacing the old envelope atomically.
    func commit(_ staged:URL) throws {
        guard staged.deletingLastPathComponent().standardizedFileURL==url.deletingLastPathComponent().standardizedFileURL,
              staged.lastPathComponent.hasPrefix(".saved-world-"),staged.pathExtension=="pending" else {
            throw PersistentMemoryError.invalidArchive("invalid staged map location")
        }
        let result=staged.withUnsafeFileSystemRepresentation { source in
            url.withUnsafeFileSystemRepresentation { destination -> Int32 in
                guard let source,let destination else { return -1 }
                return Darwin.rename(source,destination)
            }
        }
        guard result==0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
    }
    func load() throws -> (archive:PersistentMemoryArchive,map:ARWorldMap) {
        let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
        guard let size=attributes[.size] as? NSNumber,size.intValue<=PersistentMemoryArchive.maxJSONBytes else { throw PersistentMemoryError.invalidArchive("file exceeds 24 MiB") }
        let archive=try PersistentMemoryArchive.decode(Data(contentsOf:url))
        let map=try Self.decodeMap(archive)
        return (archive,map)
    }
    static func decodeMap(_ archive:PersistentMemoryArchive) throws -> ARWorldMap {
        guard let map=try NSKeyedUnarchiver.unarchivedObject(ofClass:ARWorldMap.self,from:archive.mapData) else { throw PersistentMemoryError.invalidArchive("ARWorldMap missing") }
        let markers=map.anchors.filter { $0.name==anchorName(mapID:archive.mapID) }
        guard markers.count==1,markers[0].identifier.uuidString==archive.anchorID else { throw PersistentMemoryError.invalidArchive("map marker does not match bookmarks") }
        return map
    }
    func delete() throws {
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
        // Remove a staging file left by a terminated save as part of the user's delete request.
        let directory=url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath:directory.path) {
            for file in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
            where file.lastPathComponent.hasPrefix(".saved-world-") && file.pathExtension=="pending" {
                try FileManager.default.removeItem(at:file)
            }
        }
    }
}
