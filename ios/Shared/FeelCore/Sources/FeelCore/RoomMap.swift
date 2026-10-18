import Foundation

/// Room structure memory: the floor plan the route planner learned on an earlier visit, kept in the levelled frame
/// of a printed FEEL tag (RoomFrame.levelled) so it comes back once the tag is recognized again. A map is a grid of
/// cells, each unknown, free or blocked, in tag-floor coordinates: x right along the tag, y out of the tag into the
/// room, metres, with the same cell size as FloorGrid. The origin is the corner of the cell with the smallest
/// indices and sits on the cell lattice (rounded to the nanometre, so the same corner is always the same number).
/// Cells are run-length encoded over the row-major array, +x within a row and rows in +y: <count><state> with u, f
/// and b; the canonical encoding uses maximal runs.
///
/// Visits merge by a per-cell vote (`merge`), so walls persist and moved furniture does not. chalk/feel_chalk/room_map.py
/// does the same for the shared memory on Chalk; protocol/room-map-v1.json is the vector both must reproduce.
/// A map only seeds the planner before the camera has seen the room (FloorGrid.setPrior): what the camera classifies
/// this session always overrides it, and the pins never read it.
public struct RoomMap: Equatable, Sendable {
    public static let schema = 1
    /// Cells per side, cells in all (a 50 m × 50 m room at 10 cm, the planner's own window bound) and the largest cell.
    public static let maxSide = 2000
    public static let maxCells = 250_000
    public static let maxCellSize = 1.0
    /// Rooms are tens of metres: an origin farther than this from the tag is a bad frame, not a memory (like RoomAnchor.reach).
    public static let reach = 100.0

    public let cellSize: Double
    public let originX: Double, originY: Double
    public let width: Int, height: Int
    /// Row-major, `width * height` states.
    public let cells: [FloorGrid.State]

    public init?(cellSize: Double, originX: Double, originY: Double, width: Int, height: Int, cells: [FloorGrid.State]) {
        guard cellSize.isFinite, cellSize>0, cellSize<=Self.maxCellSize,
              width>=1, height>=1, width<=Self.maxSide, height<=Self.maxSide, width*height<=Self.maxCells, cells.count==width*height,
              let ix=Self.latticeIndex(originX,cellSize), let iy=Self.latticeIndex(originY,cellSize) else { return nil }
        self.cellSize=cellSize; self.originX=Self.origin(ix,cellSize); self.originY=Self.origin(iy,cellSize)
        self.width=width; self.height=height; self.cells=cells
    }
    /// From the encoded cells, as stored on the phone and in the room_maps table.
    public init?(cellSize: Double, originX: Double, originY: Double, width: Int, height: Int, encoded: String) {
        guard width>=1, height>=1, width<=Self.maxSide, height<=Self.maxSide, width*height<=Self.maxCells,
              let states=Self.decode(encoded,count:width*height) else { return nil }
        self.init(cellSize:cellSize,originX:originX,originY:originY,width:width,height:height,cells:states)
    }

    static func latticeIndex(_ origin: Double,_ cellSize: Double) -> Int? {
        guard origin.isFinite, abs(origin)<=reach else { return nil }
        let exact=origin/cellSize, index=exact.rounded()
        guard abs(exact-index)<=1e-6 else { return nil }
        return Int(index)
    }
    /// A lattice corner rounded to the nanometre; room_map.py rounds the same way.
    static func origin(_ index: Int,_ cellSize: Double) -> Double { (Double(index)*cellSize*1e9).rounded()/1e9 }

    public var minIX: Int { Int((originX/cellSize).rounded()) }
    public var minIY: Int { Int((originY/cellSize).rounded()) }
    public var encoded: String { Self.encode(cells) }
    public var observedCount: Int { cells.reduce(0) { $0+($1 == .unknown ? 0 : 1) } }
    public var blockedCount: Int { cells.reduce(0) { $0+($1 == .blocked ? 1 : 0) } }
    /// The cell at lattice indices (ix, iy); outside the map is unknown.
    public func state(ix: Int, iy: Int) -> FloorGrid.State {
        let x=ix-minIX, y=iy-minIY
        guard x>=0, x<width, y>=0, y<height else { return .unknown }
        return cells[y*width+x]
    }

    // MARK: Encoding

    static func letter(_ state: FloorGrid.State) -> String {
        switch state { case .unknown: return "u"; case .free: return "f"; case .blocked: return "b" }
    }
    /// Canonical run-length encoding of a row-major sequence of states.
    public static func encode(_ states: [FloorGrid.State]) -> String {
        var text="", current: FloorGrid.State?, length=0
        for state in states {
            if state == current { length += 1 }
            else { if let current { text += "\(length)\(letter(current))" }; current=state; length=1 }
        }
        if let current { text += "\(length)\(letter(current))" }
        return text
    }
    /// The states behind an encoding of exactly `count` cells, or nil for anything malformed.
    public static func decode(_ text: String, count: Int) -> [FloorGrid.State]? {
        guard count>=0 else { return nil }
        var states: [FloorGrid.State]=[]; states.reserveCapacity(count)
        var digits=""
        for character in text {
            if character.isASCII, character.isNumber {
                if digits.isEmpty, character == "0" { return nil }
                digits.append(character); continue
            }
            guard let run=Int(digits), run>0 else { return nil }
            let state: FloorGrid.State
            switch character { case "u": state = .unknown; case "f": state = .free; case "b": state = .blocked; default: return nil }
            guard states.count+run<=count else { return nil }
            states.append(contentsOf:repeatElement(state,count:run)); digits=""
        }
        guard digits.isEmpty, states.count==count else { return nil }
        return states
    }

    // MARK: Merging visits

    /// The structural map of several visits: one vote per visit per cell, covering every cell any of them observed.
    /// A cell is blocked when at least half of the visits that observed it saw it blocked (a tie goes to blocked: a
    /// missed wall costs more than a spurious one, which the live camera overrides), free otherwise, unknown when no
    /// visit observed it. Nil without visits, when their cell sizes differ, or when nothing was observed.
    public static func merge(_ maps: [RoomMap]) -> RoomMap? {
        guard let first=maps.first, maps.allSatisfy({ abs($0.cellSize-first.cellSize)<=1e-9 }) else { return nil }
        var votes: [FloorGrid.Cell: (blocked: Int, free: Int)]=[:]
        for map in maps { for iy in 0..<map.height { for ix in 0..<map.width {
            let state=map.cells[iy*map.width+ix]
            guard state != .unknown else { continue }
            let key=FloorGrid.Cell(map.minIX+ix,map.minIY+iy)
            var tally=votes[key] ?? (0,0)
            if state == .blocked { tally.blocked += 1 } else { tally.free += 1 }
            votes[key]=tally
        } } }
        return fromVotes(votes.mapValues { $0.blocked>=$0.free ? FloorGrid.State.blocked : .free },cellSize:first.cellSize)
    }

    /// The smallest map holding the given known cells (keyed by lattice indices: `x` is ix, `z` is iy).
    static func fromVotes(_ known: [FloorGrid.Cell: FloorGrid.State], cellSize: Double) -> RoomMap? {
        guard let minX=known.keys.map(\.x).min(), let maxX=known.keys.map(\.x).max(),
              let minY=known.keys.map(\.z).min(), let maxY=known.keys.map(\.z).max() else { return nil }
        let width=maxX-minX+1, height=maxY-minY+1
        guard width<=maxSide, height<=maxSide, width*height<=maxCells else { return nil }
        var cells=[FloorGrid.State](repeating:.unknown,count:width*height)
        for (key,state) in known { cells[(key.z-minY)*width+(key.x-minX)]=state }
        return RoomMap(cellSize:cellSize,originX:origin(minX,cellSize),originY:origin(minY,cellSize),width:width,height:height,cells:cells)
    }

    // MARK: The floor grid

    /// What the camera classified this session, as a map in the tag's levelled frame: a visit. Nil when nothing was
    /// observed or the tag is not upright on a wall. A prior the grid was given is not part of it. Cells map by their
    /// centres: exact for a tag square to the world's axes, and a wall seen at any other angle stays an unbroken chain
    /// of cells, which the planner cannot cut through.
    public init?(grid: FloorGrid, frame: RoomFrame) {
        guard let level=frame.levelled else { return nil }
        let size=grid.cellSize
        var marks: [FloorGrid.Cell: FloorGrid.State]=[:]
        for (cell,state) in grid.observedCells {
            let world=grid.center(cell)
            let tag=level.tagPoint(world:Vector3(world.x,level.origin.y,world.z))
            let key=FloorGrid.Cell(Int(floor(tag.x/size)),Int(floor(tag.y/size)))
            marks[key]=(state == .blocked || marks[key] == .blocked) ? .blocked : .free
        }
        guard let map=Self.fromVotes(marks,cellSize:size) else { return nil }
        self=map
    }
}

extension RoomMap: Codable {
    enum CodingKeys: String, CodingKey { case schema, cellSize="cell_size", originX="origin_x", originY="origin_y", width, height, cells }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        guard try c.decode(Int.self,forKey:.schema) == Self.schema else {
            throw DecodingError.dataCorruptedError(forKey:.schema,in:c,debugDescription:"unknown room map schema")
        }
        guard let map=RoomMap(cellSize:try c.decode(Double.self,forKey:.cellSize),originX:try c.decode(Double.self,forKey:.originX),
                              originY:try c.decode(Double.self,forKey:.originY),width:try c.decode(Int.self,forKey:.width),
                              height:try c.decode(Int.self,forKey:.height),encoded:try c.decode(String.self,forKey:.cells)) else {
            throw DecodingError.dataCorruptedError(forKey:.cells,in:c,debugDescription:"cells do not encode the map")
        }
        self=map
    }
    public func encode(to encoder: Encoder) throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(Self.schema,forKey:.schema); try c.encode(cellSize,forKey:.cellSize)
        try c.encode(originX,forKey:.originX); try c.encode(originY,forKey:.originY)
        try c.encode(width,forKey:.width); try c.encode(height,forKey:.height); try c.encode(encoded,forKey:.cells)
    }
}
