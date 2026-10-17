import Foundation

/// A copy of one LiDAR depth frame: metres per pixel plus ARKit's confidence level
/// (0 low, 1 medium, 2 high), in the captured image's own orientation.
public struct DepthGrid: Equatable, Sendable {
    public let width: Int, height: Int, depths: [Double], confidence: [UInt8]
    public init(width: Int, height: Int, depths: [Double], confidence: [UInt8]) {
        self.width = width; self.height = height; self.depths = depths; self.confidence = confidence
    }
    /// Median of the medium/high-confidence depths within 4 m in a 5×5 window.
    /// Needs at least three usable samples; otherwise there is no usable depth here.
    public func medianDepth(x: Double, y: Double) -> Double? {
        guard x.isFinite, y.isFinite, x >= 0, y >= 0, x < Double(width), y < Double(height) else { return nil }
        var values: [Double] = []
        for yy in max(0, Int(y) - 2)...min(height - 1, Int(y) + 2) {
            for xx in max(0, Int(x) - 2)...min(width - 1, Int(x) + 2) {
                let i = yy * width + xx, value = depths[i]
                if confidence[i] >= 1, confidence[i] <= 2, value.isFinite, value > 0, value <= 4 { values.append(value) }
            }
        }
        guard values.count >= 3 else { return nil }
        values.sort()
        return values[values.count / 2]
    }
}
