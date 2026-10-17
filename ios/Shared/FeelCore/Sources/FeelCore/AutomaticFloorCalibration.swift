import Foundation

/// Plane state sampled from a current camera frame, never a cached delegate callback.
/// Repeated samples of one AR anchor establish stability, not independent classifications.
public struct FloorPlaneObservation {
    public enum Classification { case floor, other, unknown }
    public let id: String
    public let classification: Classification
    public let worldY: Double
    public let width: Double
    public let length: Double

    public init(id: String, classification: Classification, worldY: Double, width: Double, length: Double) {
        self.id = id; self.classification = classification; self.worldY = worldY
        self.width = width; self.length = length
    }
}

/// Conservative, session-local calibration. Only a stable, explicitly classified floor
/// can be accepted. No assumed camera height or unclassified horizontal surface fallback.
public struct AutomaticFloorCalibration {
    public private(set) var floorY: Double?
    private var candidateID: String?
    private var startedAt: Double = 0
    private var lastTimestamp: Double?
    private var minimumY: Double = 0
    private var maximumY: Double = 0
    private var sumY: Double = 0
    private var count = 0

    public init() {}

    public mutating func reset() { self = Self() }

    /// Returns a latched floor once accepted; resets pending evidence on invalid input.
    /// At least 10 distinct frame timestamps spanning 1.5 seconds are required. Gaps above
    /// 250 ms break continuity, preventing a few isolated frames from looking stable.
    public mutating func observe(planes: [FloorPlaneObservation], timestamp: Double, now: Double,
                                 cameraY: Double, trackingNormal: Bool, mountValid: Bool) -> Double? {
        if let floorY { return floorY }
        guard timestamp.isFinite, now.isFinite, cameraY.isFinite, trackingNormal, mountValid,
              now >= timestamp, now - timestamp <= 0.25 else { clearCandidate(); return nil }
        let valid = planes.filter {
            $0.classification == .floor && $0.worldY.isFinite && $0.width.isFinite && $0.length.isFinite &&
            $0.width >= 0.5 && $0.length >= 0.5 && $0.width * $0.length >= 0.5 &&
            cameraY - $0.worldY >= 0.6 && cameraY - $0.worldY <= 2.1
        }
        // Keep one anchor while it remains eligible; switching anchors starts a new window.
        guard let plane = valid.first(where: { $0.id == candidateID }) ?? valid.sorted(by: {
            let a = $0.width * $0.length, b = $1.width * $1.length
            return a == b ? $0.id < $1.id : a > b
        }).first else { clearCandidate(); return nil }
        if let lastTimestamp, timestamp <= lastTimestamp {
            // Duplicate frames never add evidence. A backwards clock starts over.
            if timestamp < lastTimestamp { clearCandidate() }
            return nil
        }
        if candidateID != plane.id || lastTimestamp.map({ timestamp - $0 > 0.25 }) == true ||
            (count > 0 && max(maximumY, plane.worldY) - min(minimumY, plane.worldY) > 0.03) {
            clearCandidate()
        }
        if candidateID == nil {
            candidateID = plane.id; startedAt = timestamp
            minimumY = plane.worldY; maximumY = plane.worldY
        }
        lastTimestamp = timestamp
        minimumY = min(minimumY, plane.worldY); maximumY = max(maximumY, plane.worldY)
        sumY += plane.worldY; count += 1
        if count >= 10 && timestamp - startedAt >= 1.5 { floorY = sumY / Double(count) }
        return floorY
    }

    private mutating func clearCandidate() {
        candidateID = nil; lastTimestamp = nil; count = 0; sumY = 0
    }
}
