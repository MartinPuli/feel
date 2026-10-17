import Foundation

/// One downloaded venue pack on disk. A download is fully validated before it atomically replaces the
/// current file, so a failed, expired or older download leaves the previous pack in place.
public final class VenuePackStore {
    private let file: URL

    public init(directory: URL) { file=directory.appendingPathComponent("venue-pack.json") }

    public func load() -> VenuePack? {
        (try? Data(contentsOf:file)).flatMap { try? VenuePack.decode($0) }
    }

    @discardableResult
    public func install(_ data: Data, now: Date) throws -> VenuePack {
        let pack=try VenuePack.decode(data)
        guard now<pack.expiresAt else { throw VenuePackError.invalid("the download has already expired") }
        if let current=load(),current.venueId == pack.venueId,current.generatedAt>pack.generatedAt {
            throw VenuePackError.invalid("the download is older than the current pack")
        }
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:file,options:.atomic)
        return pack
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        try FileManager.default.removeItem(at:file)
    }
}
