import Foundation

/// The "Where is X?" contract shared with chalk/feel_chalk/where_is.py: the prompt, the request body for
/// Chalk's OpenAI-compatible Model Gateway, and the strict answer parser. The app posts the body through
/// `ios/Lantern/Services/ChalkGateway.swift` (driven by `WhereIsService`); nothing here touches the network.
/// Prompt and parsing must match protocol/where-is-prompt.txt and protocol/where-is-cases.json.
public struct NormalizedBox: Equatable, Sendable {
    /// Fractions of image width/height, top-left origin.
    public let xMin: Double, yMin: Double, xMax: Double, yMax: Double
    public init(xMin: Double,yMin: Double,xMax: Double,yMax: Double) { self.xMin=xMin; self.yMin=yMin; self.xMax=xMax; self.yMax=yMax }
    /// From a Vision box (normalized, bottom-left origin), clamped to the image.
    public init(bottomLeftX x: Double,y: Double,width: Double,height: Double) {
        let clamp={ (v: Double) in min(1,max(0,v)) }
        self.init(xMin:clamp(x),yMin:clamp(1-(y+height)),xMax:clamp(x+width),yMax:clamp(1-y))
    }
    public var center: (x: Double, y: Double) { ((xMin+xMax)/2,(yMin+yMax)/2) }
}

public struct WhereIsAnswer: Equatable, Sendable {
    public let found: Bool
    public let label: String
    public let box: NormalizedBox?
    public let confidence: Double
    public init(found: Bool,label: String,box: NormalizedBox?,confidence: Double) { self.found=found; self.label=label; self.box=box; self.confidence=confidence }
}

public enum WhereIsError: Error, Equatable { case malformed(String) }

public enum WhereIs {
    /// Seconds from sending the request after which a reply is unusable and the phone falls back.
    public static let deadline: Double = 12
    public static let prompt = """
    You help a blind person find things using one photo from a chest-mounted phone camera.
    The user asks where something is. Look only at this photo.
    If the thing is clearly visible, give its bounding box.
    If it is not visible, or you are not sure, say it is not found. Never guess.
    Reply with one JSON object and nothing else, in exactly one of these two forms:
    {"found": true, "label": "<short name of what you found>", "box": [x_min, y_min, x_max, y_max], "confidence": <number from 0 to 1>}
    {"found": false, "label": "", "box": null, "confidence": 0}
    Box values are fractions of the image width and height, from 0 to 1, with (0, 0) at the top-left corner.
    """

    /// Strictly parse one model reply. Anything malformed throws; callers treat that as not found.
    public static func parse(_ text: String) throws -> WhereIsAnswer {
        var body=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body=body.trimmingCharacters(in:CharacterSet(charactersIn:"`")).trimmingCharacters(in:.whitespacesAndNewlines)
            if body.hasPrefix("json") { body=String(body.dropFirst(4)) }
        }
        // JSONDecoder is strict about types: "yes" or 1 is not a Bool, true is not a number.
        struct Reply: Decodable { let found: Bool; let label: String?; let box: [Double]?; let confidence: Double? }
        let reply: Reply
        do { reply=try JSONDecoder().decode(Reply.self,from:Data(body.utf8)) }
        catch { throw WhereIsError.malformed("reply is not the expected JSON object") }
        let label=reply.label ?? "", confidence=reply.confidence ?? 0
        guard confidence.isFinite,confidence>=0,confidence<=1 else { throw WhereIsError.malformed("confidence must be between 0 and 1") }
        guard reply.found else { return .init(found:false,label:label,box:nil,confidence:confidence) }
        guard let v=reply.box,v.count == 4,v.allSatisfy(\.isFinite) else { throw WhereIsError.malformed("a found answer needs a box of four numbers") }
        guard 0<=v[0],v[0]<v[2],v[2]<=1,0<=v[1],v[1]<v[3],v[3]<=1 else { throw WhereIsError.malformed("box must lie inside the image with positive width and height") }
        return .init(found:true,label:label,box:NormalizedBox(xMin:v[0],yMin:v[1],xMax:v[2],yMax:v[3]),confidence:confidence)
    }

    /// JSON body for POST {host}/v1/router/chat/completions.
    public static func requestBody(model: String, question: String, jpegBase64: String) throws -> Data {
        // No temperature: current Anthropic models reject sampling parameters.
        let body: [String:Any]=["model":model,"messages":[
            ["role":"system","content":prompt],
            ["role":"user","content":[["type":"text","text":question],["type":"image_url","image_url":["url":"data:image/jpeg;base64,\(jpegBase64)"]]]],
        ]]
        return try JSONSerialization.data(withJSONObject:body,options:[.sortedKeys])
    }
}
