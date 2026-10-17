import Foundation

/// What the phone's own detector can look for when Chalk is not set up or cannot be reached.
public enum LocalQuery: Equatable, Sendable {
    case exitSign                                        // Vision text recognition, the word EXIT
    case doorCandidate                                   // Vision rectangles with a door-like aspect ratio
    case person                                          // Core ML "person", else Vision human rectangles
    case object(labels: Set<String>, spoken: String)     // Core ML detections whose normalized label is in `labels`
}

/// Maps the user's words onto the fixed on-device vocabulary (80 COCO classes, EXIT signs, door candidates, people).
public enum LocalVocabulary {
    /// Lowercase letters and digits only, so "Dining Table", "diningtable" and "dining table" agree.
    public static func normalized(_ label: String) -> String {
        String(String.UnicodeScalarView(label.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
    public static func matches(label: String, query: LocalQuery) -> Bool {
        guard case .object(let labels,_)=query else { return false }
        return labels.contains(normalized(label))
    }
    /// Leading articles and possessives are ignored, plurals are tried as singulars, and an unknown phrase
    /// falls back to its last word ("registration desk" → desk). Nil when the vocabulary has nothing for it.
    public static func query(for thing: String) -> LocalQuery? {
        let words=thing.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let content=Array(words.drop(while: { articles.contains($0) }))
        guard !content.isEmpty else { return nil }
        if let query=lookup(content.joined(separator:" ")) { return query }
        if let last=content.last,let query=lookup(last) { return query }
        return nil
    }
    private static func lookup(_ phrase: String) -> LocalQuery? {
        if let query=table[phrase] { return query }
        if phrase.hasSuffix("es"),let query=table[String(phrase.dropLast(2))] { return query }
        if phrase.hasSuffix("s"),let query=table[String(phrase.dropLast())] { return query }
        return nil
    }
    private static let articles: Set<String>=["the","a","an","my","our","your","some","that","this","nearest","closest"]
    private static let table: [String: LocalQuery]={
        var t: [String: LocalQuery]=[:]
        for word in ["exit","exit sign","way out","emergency exit"] { t[word] = .exitSign }
        for word in ["door","doorway","entrance","entry"] { t[word] = .doorCandidate }
        for word in ["person","people","someone","somebody","human","friend","man","woman","guy","girl","boy","kid","child","anyone","anybody"] { t[word] = .person }
        // spoken name, model labels in either COCO or Darknet spelling, words the user may say
        let objects: [(String,[String],[String])]=[
            ("chair",["chair"],["chair","seat"]),
            ("couch",["couch","sofa"],["couch","sofa"]),
            ("table",["diningtable","table","desk"],["table","desk","dining table"]),
            ("laptop",["laptop"],["laptop","computer","macbook","notebook"]),
            ("phone",["cellphone","phone","mobilephone"],["phone","cell phone","cellphone","mobile","mobile phone","iphone"]),
            ("bottle",["bottle"],["bottle","water bottle","water"]),
            ("cup",["cup","wineglass"],["cup","mug","coffee","glass"]),
            ("backpack",["backpack"],["backpack","rucksack"]),
            ("bag",["backpack","handbag"],["bag","purse","handbag"]),
            ("suitcase",["suitcase"],["suitcase","luggage"]),
            ("screen",["tvmonitor","tv","television","monitor"],["tv","television","screen","monitor"]),
            ("bed",["bed"],["bed"]),("toilet",["toilet"],["toilet"]),("sink",["sink"],["sink"]),
            ("fridge",["refrigerator"],["fridge","refrigerator"]),("microwave",["microwave"],["microwave"]),("oven",["oven"],["oven","stove"]),
            ("plant",["pottedplant","plant"],["plant","potted plant"]),("umbrella",["umbrella"],["umbrella"]),("clock",["clock"],["clock"]),
            ("book",["book"],["book"]),("keyboard",["keyboard"],["keyboard"]),("mouse",["mouse"],["mouse"]),("remote",["remote"],["remote"]),
            ("bicycle",["bicycle"],["bicycle","bike"]),("dog",["dog"],["dog"]),("cat",["cat"],["cat"]),("bench",["bench"],["bench"]),
            ("bowl",["bowl"],["bowl"]),("vase",["vase"],["vase"]),("scissors",["scissors"],["scissors"]),("car",["car"],["car"]),
            ("bus",["bus"],["bus"]),("truck",["truck"],["truck"]),("stop sign",["stopsign"],["stop sign"]),("traffic light",["trafficlight"],["traffic light"]),
            ("fire hydrant",["firehydrant"],["fire hydrant","hydrant"]),("teddy bear",["teddybear"],["teddy bear","teddy"]),("toothbrush",["toothbrush"],["toothbrush"]),
            ("hair dryer",["hairdrier","hairdryer"],["hair dryer","hairdryer","hair drier"]),("fork",["fork"],["fork"]),("knife",["knife"],["knife"]),("spoon",["spoon"],["spoon"]),
        ]
        for (spoken,labels,words) in objects { for word in words { t[word] = .object(labels:Set(labels),spoken:spoken) } }
        return t
    }()
}

/// What a held Where-is target does on one frame. Pure, so the ARKit-driven tick stays a thin switch.
public enum HeldTargetGuidance {
    public enum Event: Equatable, Sendable { case keep, lostTracking, reached, speak(String) }
    /// A world change loses the target at once. Arrival and out-of-field directions count only while sensing
    /// is live, so a frozen pose never says "you're there"; the direction repeats every `interval` seconds.
    public static func event(target: HeldTarget,pose: CameraPose,worldEpoch: Int,now: Double,live: Bool,inField: Bool,lastSpokenAt: Double,interval: Double=5) -> Event {
        if target.worldEpoch != worldEpoch { return .lostTracking }
        guard live else { return .keep }
        if target.reached(pose:pose) { return .reached }
        if !inField,now-lastSpokenAt>=interval,let line=target.spokenDirection(pose:pose) { return .speak(line) }
        return .keep
    }
    /// While a target is held the pins show it or nothing; finder and teammate targets never shadow it.
    public static func pins(held: TargetObservation?,holding: Bool,finder: TargetObservation?) -> TargetObservation? { holding ? held : finder }
    /// "I no longer see your target" is for finder targets; a held target speaks its own direction instead.
    public static func announcesTargetLost(sawTarget: Bool,holding: Bool) -> Bool { sawTarget && !holding }
}
