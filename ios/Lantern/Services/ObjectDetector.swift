import Foundation
import Vision
import CoreML
import CoreVideo

// Coordinates are normalized native-image coordinates with a bottom-left origin.
struct ImageDetection {
    let label: String
    let box: CGRect
    let confidence: Double
}
enum FinderMode: String, CaseIterable, Identifiable {
    case none="Obstacles", door="Door candidate", exit="EXIT sign", chair="Chair", person="Person", teammate="Teammate", barcode="QR / barcode"
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
        } else { modelStatus="No CoreML weights bundled; EXIT, person, door-candidate and barcode detection available" }
    }

    /// Payload is display-only data: never a URL to open or a command to execute.
    /// Bound both the inspected input and output, including pathological Unicode.
    static func barcodeLabel(_ payload: String?) -> String {
        guard let payload else { return "Barcode" }
        var label = String.UnicodeScalarView()
        var previousWasSpace = true
        for scalar in payload.unicodeScalars.prefix(512) {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !previousWasSpace { label.append(" "); previousWasSpace = true }
            } else {
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate:
                    continue
                default:
                    label.append(scalar); previousWasSpace = false
                }
            }
            if label.count >= 58 { break }
        }
        let text = String(label).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Barcode" : "Code: \(text)"
    }

    static func barcodeRequest() -> VNDetectBarcodesRequest {
        let request=VNDetectBarcodesRequest()
        #if targetEnvironment(simulator)
        // Deliberately select the CPU in simulator builds. The public property
        // supports the iOS 16 target and pinned SDK; it is deprecated in iOS 17.
        // Algorithm revision, symbologies and device compute selection are unchanged.
        request.usesCPUOnly=true
        #endif
        return request
    }

    func detect(pixelBuffer: CVPixelBuffer, mode: FinderMode) throws -> [ImageDetection] {
        let handler=VNImageRequestHandler(cvPixelBuffer:pixelBuffer,orientation:.up,options:[:])
        switch mode {
        case .none,.teammate: return []
        case .barcode:
            let request=Self.barcodeRequest()
            try handler.perform([request])
            return (request.results ?? []).filter { $0.confidence>=0.5 }.map {
                ImageDetection(label:Self.barcodeLabel($0.payloadStringValue),box:$0.boundingBox,confidence:Double($0.confidence))
            }
        case .exit:
            let request=VNRecognizeTextRequest(); request.recognitionLevel = .fast; request.usesLanguageCorrection=false; request.recognitionLanguages=["en-US"]
            try handler.perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let text=observation.topCandidates(1).first, text.string.lowercased().split(whereSeparator: { !$0.isLetter }).contains("exit"), text.confidence>=0.5 else { return nil }
                return ImageDetection(label:"EXIT",box:observation.boundingBox,confidence:Double(text.confidence))
            }
        case .door:
            let request=VNDetectRectanglesRequest(); request.maximumObservations=8; request.minimumConfidence=0.65; request.minimumSize=0.15; request.minimumAspectRatio=0.1; request.maximumAspectRatio=0.9
            try handler.perform([request])
            let imageRatio=Double(CVPixelBufferGetHeight(pixelBuffer))/Double(CVPixelBufferGetWidth(pixelBuffer))
            return (request.results ?? []).compactMap { observation in
                let box=observation.boundingBox
                let ratio=Double(box.height / max(box.width,0.001))*imageRatio
                guard ratio>=1.5,ratio<=3.5 else { return nil }
                return ImageDetection(label:"Door candidate (rectangle)",box:box,confidence:Double(observation.confidence))
            }
        case .chair,.person:
            if let model {
                let request=VNCoreMLRequest(model:model); request.imageCropAndScaleOption = .scaleFill
                try handler.perform([request])
                guard let observations=request.results as? [VNRecognizedObjectObservation] else {
                    throw NSError(domain:"FEELDetector",code:1,userInfo:[NSLocalizedDescriptionKey:"Model must expose Vision object detections with bounding boxes and labels"])
                }
                let wanted=mode == .chair ? "chair" : "person"
                return observations.compactMap { observation in
                    guard let label=observation.labels.first, label.identifier.lowercased()==wanted,label.confidence>=0.5 else { return nil }
                    return ImageDetection(label:wanted,box:observation.boundingBox,confidence:Double(label.confidence))
                }
            }
            guard mode == .person else { return [] }
            let request=VNDetectHumanRectanglesRequest(); request.upperBodyOnly=false
            try handler.perform([request])
            return (request.results ?? []).filter { $0.confidence>=0.5 }.map { ImageDetection(label:"Person",box:$0.boundingBox,confidence:Double($0.confidence)) }
        }
    }
}
