import Foundation
import Vision
import CoreML
import CoreVideo
import ImageIO
import FeelCore

// Coordinates are normalized native-image coordinates with a bottom-left origin.
struct ImageDetection {
    let label: String
    let box: CGRect
    let confidence: Double
}
enum FinderMode: String, CaseIterable, Identifiable {
    case none="Obstacles", door="Door candidate", exit="EXIT sign", chair="Chair", person="Person", teammate="Teammate"
    var id: String { rawValue }
}

/// Executed only on the dedicated Vision queue by ARPerception.
final class ObjectDetector {
    private(set) var model: VNCoreMLModel?
    private(set) var modelStatus: String
    init() {
        if let url=Bundle.main.url(forResource:"FEELDetector",withExtension:"mlmodelc") {
            do {
                let configuration=MLModelConfiguration(); configuration.computeUnits = .all
                model=try VNCoreMLModel(for:MLModel(contentsOf:url,configuration:configuration)); modelStatus="CoreML detector loaded"
            } catch { modelStatus="CoreML unavailable: \(error.localizedDescription)" }
        } else { modelStatus="No CoreML weights bundled; EXIT, person and door-candidate fallbacks available" }
    }
    /// The live finder's query for a mode; nil for modes without a detector.
    static func query(for mode: FinderMode) -> LocalQuery? {
        switch mode {
        case .none,.teammate: return nil
        case .exit: return .exitSign
        case .door: return .doorCandidate
        case .person: return .person
        case .chair: return .object(labels:["chair"],spoken:"chair")
        }
    }
    /// Object queries need the bundled Core ML weights; the Vision-only queries always run.
    func canRun(_ query: LocalQuery) -> Bool {
        if case .object=query { return model != nil }
        return true
    }
    func detect(pixelBuffer: CVPixelBuffer, mode: FinderMode) throws -> [ImageDetection] {
        guard let query=Self.query(for:mode) else { return [] }
        let imageRatio=Double(CVPixelBufferGetHeight(pixelBuffer))/Double(CVPixelBufferGetWidth(pixelBuffer))
        return try detect(handler:VNImageRequestHandler(cvPixelBuffer:pixelBuffer,orientation:.up,options:[:]),imageRatio:imageRatio,query:query)
    }
    /// A Where-is photo (native orientation, like the live frames) for the on-device fallback.
    func detect(jpeg: Data, query: LocalQuery) throws -> [ImageDetection] {
        try detect(handler:VNImageRequestHandler(data:jpeg,orientation:.up,options:[:]),imageRatio:Self.aspectRatio(jpeg) ?? 0.75,query:query)
    }
    private static func aspectRatio(_ jpeg: Data) -> Double? {
        guard let source=CGImageSourceCreateWithData(jpeg as CFData,nil),
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString: Any],
              let width=properties[kCGImagePropertyPixelWidth] as? Double,let height=properties[kCGImagePropertyPixelHeight] as? Double,width>0 else { return nil }
        return height/width
    }
    private func detect(handler: VNImageRequestHandler,imageRatio: Double,query: LocalQuery) throws -> [ImageDetection] {
        switch query {
        case .exitSign:
            let request=VNRecognizeTextRequest(); request.recognitionLevel = .fast; request.usesLanguageCorrection=false; request.recognitionLanguages=["en-US"]
            try handler.perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let text=observation.topCandidates(1).first, text.string.lowercased().split(whereSeparator: { !$0.isLetter }).contains("exit"), text.confidence>=0.5 else { return nil }
                return ImageDetection(label:"EXIT",box:observation.boundingBox,confidence:Double(text.confidence))
            }
        case .doorCandidate:
            let request=VNDetectRectanglesRequest(); request.maximumObservations=8; request.minimumConfidence=0.65; request.minimumSize=0.15; request.minimumAspectRatio=0.1; request.maximumAspectRatio=0.9
            try handler.perform([request])
            return (request.results ?? []).compactMap { observation in
                let box=observation.boundingBox
                let ratio=Double(box.height / max(box.width,0.001))*imageRatio
                guard ratio>=1.5,ratio<=3.5 else { return nil }
                return ImageDetection(label:"Door candidate (rectangle)",box:box,confidence:Double(observation.confidence))
            }
        case .person,.object:
            if let model {
                let request=VNCoreMLRequest(model:model); request.imageCropAndScaleOption = .scaleFill
                try handler.perform([request])
                guard let observations=request.results as? [VNRecognizedObjectObservation] else {
                    throw NSError(domain:"FEELDetector",code:1,userInfo:[NSLocalizedDescriptionKey:"Model must expose Vision object detections with bounding boxes and labels"])
                }
                return observations.compactMap { observation in
                    guard let label=observation.labels.first,label.confidence>=0.5 else { return nil }
                    switch query {
                    case .object(_,let spoken):
                        guard LocalVocabulary.matches(label:label.identifier,query:query) else { return nil }
                        return ImageDetection(label:spoken,box:observation.boundingBox,confidence:Double(label.confidence))
                    default:
                        guard LocalVocabulary.normalized(label.identifier)=="person" else { return nil }
                        return ImageDetection(label:"person",box:observation.boundingBox,confidence:Double(label.confidence))
                    }
                }
            }
            guard case .person=query else { return [] }
            let request=VNDetectHumanRectanglesRequest(); request.upperBodyOnly=false
            try handler.perform([request])
            return (request.results ?? []).filter { $0.confidence>=0.5 }.map { ImageDetection(label:"Person",box:$0.boundingBox,confidence:Double($0.confidence)) }
        }
    }
}
