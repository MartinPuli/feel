import Foundation
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
        let directory=url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
        var excluded=directory; var resource=URLResourceValues(); resource.isExcludedFromBackup=true
        try excluded.setResourceValues(resource)
        let data=try archive.encoded()
        guard data.count<=PersistentMemoryArchive.maxJSONBytes else { throw PersistentMemoryError.invalidArchive("encoded map too large") }
        try data.write(to:url,options:[.atomic,.completeFileProtection])
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
    }
}
