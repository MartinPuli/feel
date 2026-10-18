import Foundation

/// Floor-plane map of the wearer's immediate surroundings, built from LiDAR points in
/// world coordinates. Each 10 cm cell counts floor hits and obstacle hits. A cell is
/// blocked by anything 10 cm–2 m above the calibrated floor, so bags and chair legs below
/// the 0.6 m sector window still count. Cells the camera has not seen stay unknown.
/// Cells farther than `keepRadius` from the wearer are dropped: this is a map of the
/// current room, not a memory of places. A `RoomMap` from an earlier visit can be set as a
/// prior (`setPrior`): it fills in cells the camera has not classified yet, so a route can be
/// planned before the room is seen, and a live classification always overrides it.
public struct FloorGrid: Sendable {
    public struct Cell: Hashable, Sendable { public let x: Int, z: Int; public init(_ x: Int, _ z: Int) { self.x=x; self.z=z } }
    public enum State: Equatable, Sendable { case unknown, free, blocked }

    public let cellSize: Double
    public var minObstacleHeight = 0.10
    public var maxObstacleHeight = 2.0
    public var maxRange = 4.0
    public var keepRadius = 8.0
    private var floorHits: [Cell: Float] = [:]
    private var obstacleHits: [Cell: Float] = [:]
    /// Remembered structure in this world's cells, from a RoomMap; the camera never writes it.
    private var prior: [Cell: State] = [:]
    private var integrations = 0

    public init(cellSize: Double = 0.1) { self.cellSize=cellSize }

    /// Cells with live evidence, classified or not.
    public var cellCount: Int { Set(floorHits.keys).union(obstacleHits.keys).count }
    /// Cells the camera has classified this session, without the prior.
    public var observedCells: [Cell: State] {
        var result: [Cell: State]=[:]
        for cell in Set(floorHits.keys).union(obstacleHits.keys) { let state=liveState(cell); if state != .unknown { result[cell]=state } }
        return result
    }
    public var priorCells: [Cell: State] { prior }
    public var priorCellCount: Int { prior.count }
    /// A new world: everything goes, the prior included (it was placed in the old world's coordinates).
    public mutating func reset() { floorHits=[:]; obstacleHits=[:]; prior=[:] }
    /// Withdraw remembered structure without discarding observations from the live camera.
    public mutating func clearPrior() { prior = [:] }
    /// The floor level changed: live heights are stale, the remembered structure is not.
    public mutating func clearObservations() { floorHits=[:]; obstacleHits=[:] }

    public func cell(_ p: Vector3) -> Cell { Cell(Int(floor(p.x/cellSize)), Int(floor(p.z/cellSize))) }
    public func center(_ c: Cell) -> Vector3 { Vector3((Double(c.x)+0.5)*cellSize, 0, (Double(c.z)+0.5)*cellSize) }

    /// What the camera has classified in this cell this session.
    public func liveState(_ c: Cell) -> State {
        let o=obstacleHits[c] ?? 0, f=floorHits[c] ?? 0
        if o>=3 && o>=f { return .blocked }
        if f>=2 { return .free }
        return .unknown
    }
    /// The live classification, or the prior where the camera has not classified the cell yet.
    public func state(_ c: Cell) -> State {
        let live=liveState(c)
        return live == .unknown ? (prior[c] ?? .unknown) : live
    }

    /// Replaces the prior with a remembered map, placed through the tag's levelled frame into this world's cells.
    /// False, and no prior, when the map's cells are not this grid's cells or the tag is not upright on a wall. Cells
    /// map by their centres (see RoomMap); where two land in one cell, blocked wins.
    @discardableResult
    public mutating func setPrior(_ map: RoomMap, frame: RoomFrame) -> Bool {
        guard abs(map.cellSize-cellSize)<=1e-9, let level=frame.levelled else { return false }
        var next: [Cell: State]=[:]
        for iy in 0..<map.height { for ix in 0..<map.width {
            let state=map.cells[iy*map.width+ix]
            guard state != .unknown else { continue }
            let tag=Vector3((Double(map.minIX+ix)+0.5)*cellSize,(Double(map.minIY+iy)+0.5)*cellSize,0)
            let world=level.worldPoint(tag:tag)
            let key=cell(Vector3(world.x,0,world.z))
            next[key]=(state == .blocked || next[key] == .blocked) ? .blocked : .free
        } }
        prior=next
        return true
    }

    /// Adds one frame of world points. A floor hit weakens old obstacle evidence in that cell,
    /// so a person who walks away stops blocking once the floor there is seen again.
    public mutating func integrate(points: [Vector3], floorY: Double, camera: Vector3) {
        guard floorY.isFinite, camera.isFinite else { return }
        for p in points where p.isFinite {
            let dx=p.x-camera.x, dz=p.z-camera.z
            guard dx*dx+dz*dz<=maxRange*maxRange else { continue }
            let h=p.y-floorY, c=cell(p)
            if h < minObstacleHeight && h > -0.15 {
                floorHits[c]=min(20,(floorHits[c] ?? 0)+1)
                if let o=obstacleHits[c] { obstacleHits[c]=o*0.9 }
            } else if h >= minObstacleHeight && h <= maxObstacleHeight {
                obstacleHits[c]=min(20,(obstacleHits[c] ?? 0)+1)
                if let f=floorHits[c] { floorHits[c]=f*0.9 }
            }
        }
        let keep=keepRadius*keepRadius
        let size=cellSize
        let far: (Cell) -> Bool = { c in
            let dx=(Double(c.x)+0.5)*size-camera.x, dz=(Double(c.z)+0.5)*size-camera.z; return dx*dx+dz*dz>keep
        }
        integrations += 1
        if integrations % 50 == 0 || floorHits.count+obstacleHits.count>40_000 {
            floorHits=floorHits.filter { !far($0.key) }; obstacleHits=obstacleHits.filter { !far($0.key) }
        }
    }

    // MARK: Planning

    /// Shortest route on the grid from `start` to any open cell within `goalRadius` of `goal`.
    /// Blocked cells are impassable; cells within `clearance` of a blocked cell and unknown cells
    /// cost extra, so the route prefers seen floor with room for a body. Returns world points
    /// (cell centres, y = 0) from start to goal, or nil when every route is blocked.
    public func route(from start: Vector3, to goal: Vector3, goalRadius: Double = 0.7, clearance: Double = 0.3, margin: Double = 2.5) -> [Vector3]? {
        guard start.isFinite, goal.isFinite else { return nil }
        let s=cell(start), g=cell(goal)
        let minX=min(s.x,g.x)-Int(margin/cellSize), maxX=max(s.x,g.x)+Int(margin/cellSize)
        let minZ=min(s.z,g.z)-Int(margin/cellSize), maxZ=max(s.z,g.z)+Int(margin/cellSize)
        let w=maxX-minX+1, h=maxZ-minZ+1
        guard w>0, h>0, w*h<=250_000 else { return nil }
        func idx(_ x: Int, _ z: Int) -> Int { (z-minZ)*w+(x-minX) }
        // Per-cell step cost; .infinity blocked.
        var cost=[Double](repeating:1,count:w*h)
        var blocked: [Cell]=[]
        for z in minZ...maxZ { for x in minX...maxX {
            switch state(Cell(x,z)) {
            case .blocked: cost[idx(x,z)] = .infinity; blocked.append(Cell(x,z))
            case .unknown: cost[idx(x,z)]=3
            case .free: break
            }
        } }
        let r=Int((clearance/cellSize).rounded(.up))
        for b in blocked { for dz in -r...r { for dx in -r...r where dx*dx+dz*dz<=r*r {
            let x=b.x+dx, z=b.z+dz
            guard x>=minX, x<=maxX, z>=minZ, z<=maxZ, cost[idx(x,z)].isFinite else { continue }
            cost[idx(x,z)]=max(cost[idx(x,z)],8)
        } } }
        // The wearer is standing there; their own cell is never blocked.
        cost[idx(s.x,s.z)]=1
        let gr=goalRadius/cellSize
        func isGoal(_ x: Int, _ z: Int) -> Bool { let dx=Double(x-g.x), dz=Double(z-g.z); return dx*dx+dz*dz<=gr*gr && cost[idx(x,z)].isFinite }
        func heuristic(_ x: Int, _ z: Int) -> Double { max(0,hypot(Double(x-g.x),Double(z-g.z))-gr) }

        var best=[Double](repeating:.infinity,count:w*h), parent=[Int](repeating:-1,count:w*h)
        var heap=MinHeap(); best[idx(s.x,s.z)]=0; heap.push(heuristic(s.x,s.z),idx(s.x,s.z))
        let steps=[(1,0,1.0),(-1,0,1.0),(0,1,1.0),(0,-1,1.0),(1,1,2.0.squareRoot()),(1,-1,2.0.squareRoot()),(-1,1,2.0.squareRoot()),(-1,-1,2.0.squareRoot())]
        var found = -1
        while let (_,i)=heap.pop() {
            let x=i%w+minX, z=i/w+minZ
            if isGoal(x,z) { found=i; break }
            for (dx,dz,len) in steps {
                let nx=x+dx, nz=z+dz
                guard nx>=minX, nx<=maxX, nz>=minZ, nz<=maxZ else { continue }
                let j=idx(nx,nz)
                guard cost[j].isFinite else { continue }
                // No corner cutting between two blocked cells.
                if dx != 0 && dz != 0 && (!cost[idx(x+dx,z)].isFinite || !cost[idx(x,z+dz)].isFinite) { continue }
                let next=best[i]+len*cost[j]
                if next<best[j] { best[j]=next; parent[j]=i; heap.push(next+heuristic(nx,nz),j) }
            }
        }
        guard found>=0 else { return nil }
        var path: [Vector3]=[]; var i=found
        while i>=0 { path.append(center(Cell(i%w+minX,i/w+minZ))); i=parent[i] }
        path.reverse()
        // Start exactly at the wearer.
        path[0]=Vector3(start.x,0,start.z)
        return path
    }
}

private struct MinHeap {
    private var items: [(Double,Int)]=[]
    mutating func push(_ key: Double, _ value: Int) {
        items.append((key,value)); var i=items.count-1
        while i>0 { let p=(i-1)/2; if items[p].0<=items[i].0 { break }; items.swapAt(p,i); i=p }
    }
    mutating func pop() -> (Double,Int)? {
        guard !items.isEmpty else { return nil }
        let top=items[0]; let last=items.removeLast()
        if !items.isEmpty {
            items[0]=last; var i=0
            while true {
                let l=2*i+1, r=l+1; var m=i
                if l<items.count && items[l].0<items[m].0 { m=l }
                if r<items.count && items[r].0<items[m].0 { m=r }
                if m==i { break }; items.swapAt(i,m); i=m
            }
        }
        return top
    }
}

/// Where the planned route goes next, relative to the way the wearer faces.
public struct RouteHint: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case route, blocked }
    public let timestamp: Double
    public let status: Status
    /// Right-positive bearing of the route's next stretch, degrees.
    public let bearingDegrees: Double
    /// Straight-line distance to the target, metres.
    public let targetDistance: Double
    public let routeLength: Double
    public let label: String
    public init(timestamp: Double, status: Status, bearingDegrees: Double, targetDistance: Double, routeLength: Double, label: String) {
        self.timestamp=timestamp; self.status=status; self.bearingDegrees=bearingDegrees; self.targetDistance=targetDistance; self.routeLength=routeLength; self.label=label
    }

    /// How far along the route the "next stretch" is aimed.
    public static let lookahead = 1.2

    public static func make(path: [Vector3]?, pose: CameraPose, target: Vector3, timestamp: Double, label: String) -> RouteHint? {
        guard pose.isValid, target.isFinite else { return nil }
        // Facing direction: camera forward (-back) flattened onto the floor.
        let fx = -pose.back.x, fz = -pose.back.z, fl=hypot(fx,fz)
        let rx = pose.right.x, rz = pose.right.z, rl=hypot(rx,rz)
        guard fl>0.3, rl>0.3 else { return nil }
        func bearing(_ p: Vector3) -> Double {
            let dx=p.x-pose.position.x, dz=p.z-pose.position.z
            return atan2((dx*rx+dz*rz)/rl,(dx*fx+dz*fz)/fl)*180 / .pi
        }
        let direct=hypot(target.x-pose.position.x,target.z-pose.position.z)
        guard let path, path.count>=2 else {
            return RouteHint(timestamp:timestamp,status:.blocked,bearingDegrees:bearing(target),targetDistance:direct,routeLength:0,label:label)
        }
        var walked=0.0, aim=path[path.count-1]
        for k in 1..<path.count {
            let step=hypot(path[k].x-path[k-1].x,path[k].z-path[k-1].z)
            if walked+step>=lookahead { aim=path[k]; walked += step; break }
            walked += step
        }
        let length=zip(path,path.dropFirst()).reduce(0) { $0+hypot($1.1.x-$1.0.x,$1.1.z-$1.0.z) }
        return RouteHint(timestamp:timestamp,status:.route,bearingDegrees:bearing(aim),targetDistance:direct,routeLength:length,label:label)
    }
}
